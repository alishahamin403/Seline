import Foundation
import PostgREST

@MainActor
class VisitDeduplicationService {
    static let shared = VisitDeduplicationService()

    struct DeduplicationResult {
        var duplicateGroupsFound: Int = 0
        var totalDuplicates: Int = 0
        var visitsDeleted: Int = 0
        var notesPreserved: Int = 0
        var peoplePreserved: Int = 0
    }

    private init() {}

    // MARK: - Main Deduplication Entry Point

    func deduplicateAllVisits() async -> DeduplicationResult {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ User not authenticated")
            return DeduplicationResult()
        }

        print("\n🔍 ===== STARTING COMPREHENSIVE DUPLICATE CLEANUP =====")
        print("🔍 User ID: \(userId.uuidString)")

        let client = await SupabaseManager.shared.getPostgrestClient()
        var result = DeduplicationResult()

        do {
            // Fetch ALL visits
            let allVisits: [LocationVisitRecord] = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: true)
                .execute()
                .value

            print("🔍 Total visits fetched: \(allVisits.count)")

            // Group by location
            let grouped = Dictionary(grouping: allVisits, by: { $0.savedPlaceId })
            print("🔍 Grouped into \(grouped.count) unique locations")

            // Process each location's visits
            for (placeId, placeVisits) in grouped {
                let locationResult = await deduplicateLocationVisits(placeId: placeId, visits: placeVisits)
                result.duplicateGroupsFound += locationResult.duplicateGroupsFound
                result.totalDuplicates += locationResult.totalDuplicates
                result.visitsDeleted += locationResult.visitsDeleted
                result.notesPreserved += locationResult.notesPreserved
                result.peoplePreserved += locationResult.peoplePreserved
            }

            print("\n✅ ===== DEDUPLICATION COMPLETE =====")
            print("✅ Duplicate groups found: \(result.duplicateGroupsFound)")
            print("✅ Total duplicates: \(result.totalDuplicates)")
            print("✅ Visits deleted: \(result.visitsDeleted)")
            print("✅ Notes preserved: \(result.notesPreserved)")
            print("✅ People associations preserved: \(result.peoplePreserved)")

            // Invalidate all caches after cleanup
            LocationVisitAnalytics.shared.invalidateAllVisitCaches()

        } catch {
            print("❌ Error during deduplication: \(error)")
        }

        return result
    }

    // MARK: - Location-Level Deduplication

    private func deduplicateLocationVisits(placeId: UUID, visits: [LocationVisitRecord]) async -> DeduplicationResult {
        var result = DeduplicationResult()

        // Sort by entry time
        let sorted = visits.sorted { $0.entryTime < $1.entryTime }

        // Find duplicate groups
        let duplicateGroups = findDuplicateGroups(sorted)

        if duplicateGroups.isEmpty {
            return result
        }

        print("\n📍 Processing location with \(duplicateGroups.count) duplicate groups")
        result.duplicateGroupsFound = duplicateGroups.count

        // Consolidate each group
        for group in duplicateGroups {
            result.totalDuplicates += group.count
            let groupResult = await consolidateVisitGroup(group)
            result.visitsDeleted += groupResult.deleted
            result.notesPreserved += groupResult.notesPreserved
            result.peoplePreserved += groupResult.peoplePreserved
        }

        return result
    }

    // MARK: - Duplicate Detection

    private func findDuplicateGroups(_ visits: [LocationVisitRecord]) -> [[LocationVisitRecord]] {
        var groups: [[LocationVisitRecord]] = []
        var processed: Set<UUID> = []

        for i in 0..<visits.count {
            if processed.contains(visits[i].id) { continue }

            var group = [visits[i]]
            processed.insert(visits[i].id)

            // Check subsequent visits for duplicates
            for j in (i+1)..<visits.count {
                if processed.contains(visits[j].id) { continue }

                if isDuplicate(visits[i], visits[j]) {
                    group.append(visits[j])
                    processed.insert(visits[j].id)
                }
            }

            // Only keep groups with 2+ visits
            if group.count > 1 {
                groups.append(group)
            }
        }

        return groups
    }

    private func isDuplicate(_ v1: LocationVisitRecord, _ v2: LocationVisitRecord) -> Bool {
        // Criterion 1: Significant time overlap (80%+)
        if hasSignificantOverlap(v1, v2) {
            return true
        }

        // Criterion 2: Small gap (<5 minutes) AND same calendar day
        if hasSmallGap(v1, v2) && sameCalendarDay(v1, v2) {
            return true
        }

        // Criterion 3: Same session_id (failed merge)
        if v1.sessionId == v2.sessionId && v1.sessionId != nil {
            return true
        }

        // Criterion 4: Entry times within 30 seconds (rapid fire duplicates)
        if abs(v1.entryTime.timeIntervalSince(v2.entryTime)) < 30 {
            return true
        }

        return false
    }

    private func hasSignificantOverlap(_ v1: LocationVisitRecord, _ v2: LocationVisitRecord) -> Bool {
        guard let exit1 = v1.exitTime, let exit2 = v2.exitTime else { return false }

        let start1 = v1.entryTime
        let end1 = exit1
        let start2 = v2.entryTime
        let end2 = exit2

        // Calculate overlap
        let overlapStart = max(start1, start2)
        let overlapEnd = min(end1, end2)

        guard overlapStart < overlapEnd else { return false }

        let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)
        let duration1 = end1.timeIntervalSince(start1)
        let duration2 = end2.timeIntervalSince(start2)

        let minDuration = min(duration1, duration2)
        let overlapPercentage = overlapDuration / minDuration

        return overlapPercentage >= 0.8
    }

    private func hasSmallGap(_ v1: LocationVisitRecord, _ v2: LocationVisitRecord) -> Bool {
        guard let exit1 = v1.exitTime else { return false }

        let gap = v2.entryTime.timeIntervalSince(exit1)
        return gap >= 0 && gap < 300 // 5 minutes
    }

    private func sameCalendarDay(_ v1: LocationVisitRecord, _ v2: LocationVisitRecord) -> Bool {
        let calendar = Calendar.current
        let day1 = calendar.dateComponents([.year, .month, .day], from: v1.entryTime)
        let day2 = calendar.dateComponents([.year, .month, .day], from: v2.entryTime)
        return day1 == day2
    }

    // MARK: - Consolidation

    struct ConsolidationResult {
        var deleted: Int = 0
        var notesPreserved: Int = 0
        var peoplePreserved: Int = 0
    }

    private func consolidateVisitGroup(_ group: [LocationVisitRecord]) async -> ConsolidationResult {
        var result = ConsolidationResult()

        // Select the keeper (earliest entry, latest exit, longest duration)
        let keeper = selectKeeperVisit(group)
        let toDelete = group.filter { $0.id != keeper.id }

        print("  🔄 Consolidating group: keeping \(keeper.id), deleting \(toDelete.count) duplicates")

        // Merge notes from all visits
        let allNotes = group.compactMap { $0.visitNotes }.filter { !$0.isEmpty }
        if !allNotes.isEmpty {
            let mergedNotes = allNotes.joined(separator: "\n\n")
            await updateVisitNotes(keeper.id, notes: mergedNotes)
            result.notesPreserved = allNotes.count
        }

        // Merge people associations
        let allPeopleIds = await fetchAllPeopleForVisits(group.map { $0.id })
        if !allPeopleIds.isEmpty {
            await linkPeopleToVisit(keeper.id, peopleIds: Array(allPeopleIds))
            result.peoplePreserved = allPeopleIds.count
        }

        // Delete duplicates
        for visit in toDelete {
            await deleteVisit(visit.id)
            result.deleted += 1
        }

        return result
    }

    private func selectKeeperVisit(_ visits: [LocationVisitRecord]) -> LocationVisitRecord {
        // Prefer visit with notes
        if let withNotes = visits.first(where: { $0.visitNotes != nil && !$0.visitNotes!.isEmpty }) {
            return withNotes
        }

        // Prefer visit with longest duration
        if let withDuration = visits.max(by: { ($0.durationMinutes ?? 0) < ($1.durationMinutes ?? 0) }) {
            return withDuration
        }

        // Default: earliest created
        return visits.min(by: { $0.createdAt < $1.createdAt })!
    }

    // MARK: - Database Operations

    private func updateVisitNotes(_ visitId: UUID, notes: String) async {
        let client = await SupabaseManager.shared.getPostgrestClient()
        do {
            let formatter = ISO8601DateFormatter()
            let updateData: [String: PostgREST.AnyJSON] = [
                "visit_notes": .string(notes),
                "updated_at": .string(formatter.string(from: Date()))
            ]

            _ = try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: visitId.uuidString)
                .execute()
        } catch {
            print("❌ Error updating notes: \(error)")
        }
    }

    private func fetchAllPeopleForVisits(_ visitIds: [UUID]) async -> Set<UUID> {
        let client = await SupabaseManager.shared.getPostgrestClient()
        var allPeopleIds = Set<UUID>()

        for visitId in visitIds {
            do {
                struct PersonIdResult: Codable {
                    let person_id: String
                }

                let results: [PersonIdResult] = try await client
                    .from("location_visit_people")
                    .select("person_id")
                    .eq("visit_id", value: visitId.uuidString)
                    .execute()
                    .value

                results.compactMap { UUID(uuidString: $0.person_id) }.forEach { allPeopleIds.insert($0) }
            } catch {
                print("❌ Error fetching people for visit \(visitId): \(error)")
            }
        }

        return allPeopleIds
    }

    private func linkPeopleToVisit(_ visitId: UUID, peopleIds: [UUID]) async {
        let client = await SupabaseManager.shared.getPostgrestClient()

        // First delete existing associations
        do {
            _ = try await client
                .from("location_visit_people")
                .delete()
                .eq("visit_id", value: visitId.uuidString)
                .execute()
        } catch {
            print("❌ Error deleting existing people links: \(error)")
        }

        // Insert new associations
        let formatter = ISO8601DateFormatter()
        for personId in peopleIds {
            do {
                let data: [String: PostgREST.AnyJSON] = [
                    "id": .string(UUID().uuidString),
                    "visit_id": .string(visitId.uuidString),
                    "person_id": .string(personId.uuidString),
                    "created_at": .string(formatter.string(from: Date()))
                ]

                _ = try await client
                    .from("location_visit_people")
                    .insert(data)
                    .execute()
            } catch {
                print("❌ Error linking person \(personId): \(error)")
            }
        }
    }

    private func deleteVisit(_ visitId: UUID) async {
        let client = await SupabaseManager.shared.getPostgrestClient()

        do {
            // Delete people associations first
            _ = try await client
                .from("location_visit_people")
                .delete()
                .eq("visit_id", value: visitId.uuidString)
                .execute()

            // Delete visit
            _ = try await client
                .from("location_visits")
                .delete()
                .eq("id", value: visitId.uuidString)
                .execute()

            print("  ✅ Deleted visit: \(visitId)")
        } catch {
            print("  ❌ Error deleting visit \(visitId): \(error)")
        }
    }
}
