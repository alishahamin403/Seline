import Foundation
import PostgREST

// MARK: - Visit Statistics Models

struct LocationVisitStats {
    let totalVisits: Int
    let averageDurationMinutes: Double
    let lastVisitDate: Date?
    let mostCommonTimeOfDay: String?
    let mostCommonDayOfWeek: String?
    let thisMonthVisits: Int
    let thisYearVisits: Int
}

struct VisitHistoryItem {
    let visit: LocationVisitRecord
    let placeName: String
}

// MARK: - LocationVisitAnalytics Service

@MainActor
class LocationVisitAnalytics: ObservableObject {
    static let shared = LocationVisitAnalytics()

    @Published var visitStats: [UUID: LocationVisitStats] = [:] // [placeId: stats]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let authManager = AuthenticationManager.shared

    // MARK: - Public Methods

    /// Fetch and calculate stats for a specific saved place
    func fetchStats(for placeId: UUID) async {
        let cacheKey = CacheManager.CacheKey.locationStats(placeId.uuidString)

        // OPTIMIZATION: Check CacheManager first before querying Supabase
        if let cachedStats: LocationVisitStats = CacheManager.shared.get(forKey: cacheKey) {
            await MainActor.run {
                self.visitStats[placeId] = cachedStats
            }
            return
        }

        isLoading = true
        errorMessage = nil

        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            errorMessage = "User not authenticated"
            isLoading = false
            print("❌ LocationVisitAnalytics: User not authenticated when fetching stats for \(placeId)")
            return
        }

        do {
            let visits = try await fetchVisits(for: placeId, userId: userId)

            // Include the active visit if one exists for this location
            let activeVisit = GeofenceManager.shared.activeVisits[placeId]
            let stats = calculateStats(from: visits, activeVisit: activeVisit)

            await MainActor.run {
                self.visitStats[placeId] = stats
                // OPTIMIZATION: Cache using CacheManager with 5-minute TTL for faster updates
                CacheManager.shared.set(stats, forKey: cacheKey, ttl: CacheManager.TTL.medium)
            }
        } catch {
            errorMessage = "Failed to fetch visit stats: \(error.localizedDescription)"
            print("❌ Error fetching stats for place \(placeId): \(error.localizedDescription)")
            print("   Full error: \(error)")
        }

        isLoading = false
    }

    /// Fetch all visit stats for all locations (not just favorites)
    func fetchAllStats(for places: [SavedPlace]) async {
        // Fetch stats for ALL locations to ensure complete data for LLM queries
        for place in places {
            await fetchStats(for: place.id)
        }
    }

    /// Get visit history for a specific place
    func fetchVisitHistory(for placeId: UUID, limit: Int = 20) async -> [VisitHistoryItem] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            errorMessage = "User not authenticated"
            return []
        }

        do {
            let visits = try await fetchVisits(for: placeId, userId: userId)
            let place = LocationsManager.shared.savedPlaces.first { $0.id == placeId }

            // Sort by entry time (most recent first) and limit
            let sortedVisits = visits
                .sorted { $0.entryTime > $1.entryTime }
                .prefix(limit)

            return sortedVisits.map { visit in
                VisitHistoryItem(
                    visit: visit,
                    placeName: place?.displayName ?? "Unknown Location"
                )
            }
        } catch {
            errorMessage = "Failed to fetch visit history: \(error.localizedDescription)"
            return []
        }
    }

    /// Get stats grouped by time of day and day of week (batched together for performance)
    func getBothTimeAndDayStats(for placeId: UUID) async -> (timeOfDay: [String: Int], dayOfWeek: [String: Int]) {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return ([:], [:]) }

        do {
            // OPTIMIZATION: Fetch visits once and calculate both stats
            let visits = try await fetchVisits(for: placeId, userId: userId)

            var timeOfDayStats: [String: Int] = [:]
            var dayStats: [String: Int] = [:]

            // Calculate both in a single loop
            for visit in visits {
                timeOfDayStats[visit.timeOfDay, default: 0] += 1
                dayStats[visit.dayOfWeek, default: 0] += 1
            }

            return (timeOfDayStats, dayStats)
        } catch {
            print("❌ Error fetching time/day stats: \(error)")
            return ([:], [:])
        }
    }

    /// Get stats grouped by time of day
    func getStatsByTimeOfDay(for placeId: UUID) async -> [String: Int] {
        let (timeOfDay, _) = await getBothTimeAndDayStats(for: placeId)
        return timeOfDay
    }

    /// Get stats grouped by day of week
    func getStatsByDayOfWeek(for placeId: UUID) async -> [String: Int] {
        let (_, dayOfWeek) = await getBothTimeAndDayStats(for: placeId)
        return dayOfWeek
    }

    /// Fetch visits for a specific place within a date range
    func getVisitsInDateRange(for placeId: UUID, startDate: Date, endDate: Date) async -> [LocationVisitRecord] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return []
        }

        do {
            let visits = try await fetchVisits(for: placeId, userId: userId)

            // Filter visits within the specified date range
            let filteredVisits = visits.filter { visit in
                return visit.entryTime >= startDate && visit.entryTime <= endDate
            }

            return filteredVisits
        } catch {
            print("❌ Error fetching visits in date range: \(error)")
            return []
        }
    }

    /// Get all locations visited on a specific date
    func getLocationsVisitedOnDate(_ date: Date) async -> [UUID: [LocationVisitRecord]] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return [:]
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .second, value: -1, to: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: date)!))!

        var locationVisits: [UUID: [LocationVisitRecord]] = [:]

        // Get all saved places
        let allPlaces = LocationsManager.shared.savedPlaces

        for place in allPlaces {
            let visits = await getVisitsInDateRange(for: place.id, startDate: startOfDay, endDate: endOfDay)
            if !visits.isEmpty {
                locationVisits[place.id] = visits
            }
        }

        return locationVisits
    }

    /// Get today's visits with total duration per location
    /// Returns array of (placeId, displayName, totalDurationMinutes, isActive) sorted by most recent visit
    func getTodaysVisitsWithDuration() async -> [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)] {
        guard SupabaseManager.shared.getCurrentUser()?.id != nil else {
            return []
        }

        // OPTIMIZATION: Cache today's visits with 1-minute TTL for fast refresh
        let cacheKey = CacheManager.CacheKey.todaysVisits
        if let cached: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)] = CacheManager.shared.get(forKey: cacheKey) {
            return cached
        }

        let calendar = Calendar.current
        let today = Date()
        let startOfDay = calendar.startOfDay(for: today)
        let endOfDay = calendar.date(byAdding: .second, value: -1, to: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: today)!))!

        var results: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool, lastVisitTime: Date)] = []
        var processedPlaceIds: Set<UUID> = [] // Track which places we've already processed

        // Get all saved places
        let allPlaces = LocationsManager.shared.savedPlaces

        // FIRST: Check for active visits from GeofenceManager (these might have started yesterday)
        let activeVisits = GeofenceManager.shared.activeVisits

        for (placeId, activeVisit) in activeVisits {
            guard let place = allPlaces.first(where: { $0.id == placeId }) else { continue }

            processedPlaceIds.insert(placeId)

            // Calculate duration spent TODAY only
            let visitEntryTime = activeVisit.entryTime

            // If visit started before today, use start of today as the effective start time
            let effectiveStartTime = visitEntryTime < startOfDay ? startOfDay : visitEntryTime

            // Calculate minutes from effective start to now
            let minutesToday = Int(Date().timeIntervalSince(effectiveStartTime) / 60)

            // Also check for any completed visits today from the database
            let visitsToday = await getVisitsInDateRange(for: placeId, startDate: startOfDay, endDate: endOfDay)
            let completedMinutesToday = visitsToday.compactMap { $0.durationMinutes }.reduce(0, +)

            let totalMinutes = minutesToday + completedMinutesToday

            results.append((
                id: placeId,
                displayName: place.displayName,
                totalDurationMinutes: totalMinutes,
                isActive: true,
                lastVisitTime: Date() // Active visit is always most recent
            ))
        }

        // SECOND: Process places with completed visits today (that aren't already active)
        for place in allPlaces {
            // Skip if we already processed this place as an active visit
            if processedPlaceIds.contains(place.id) {
                continue
            }

            let visits = await getVisitsInDateRange(for: place.id, startDate: startOfDay, endDate: endOfDay)
            if !visits.isEmpty {
                // Calculate total duration for today
                var totalMinutes = 0
                var latestVisitTime: Date = .distantPast

                for visit in visits {
                    if let duration = visit.durationMinutes {
                        totalMinutes += duration
                    }

                    // Track latest visit time for sorting
                    if visit.entryTime > latestVisitTime {
                        latestVisitTime = visit.entryTime
                    }
                }

                results.append((
                    id: place.id,
                    displayName: place.displayName,
                    totalDurationMinutes: totalMinutes,
                    isActive: false,
                    lastVisitTime: latestVisitTime
                ))
            }
        }

        // Sort by most recent visit first
        let sorted = results.sorted { $0.lastVisitTime > $1.lastVisitTime }

        // Return without the lastVisitTime (internal sorting field)
        let resultData = sorted.map { (id: $0.id, displayName: $0.displayName, totalDurationMinutes: $0.totalDurationMinutes, isActive: $0.isActive) }

        // OPTIMIZATION: Cache for 1 minute
        CacheManager.shared.set(resultData, forKey: cacheKey, ttl: CacheManager.TTL.short)

        return resultData
    }

    // MARK: - Cache Management

    /// Invalidate cache for a specific place (call when visit is recorded/updated)
    func invalidateCache(for placeId: UUID) {
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.locationStats(placeId.uuidString))
        // Also invalidate today's visits since it aggregates all locations
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.todaysVisits)
        print("🔄 Invalidated stats cache for place \(placeId)")
    }

    /// Invalidate all cached stats
    func invalidateAllCache() {
        CacheManager.shared.invalidate(keysWithPrefix: "cache.location")
        CacheManager.shared.invalidate(forKey: CacheManager.CacheKey.todaysVisits)
        print("🔄 Invalidated all stats caches")
    }

    /// Delete a specific visit from history
    func deleteVisit(id: String) async -> Bool {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            errorMessage = "User not authenticated"
            print("❌ LocationVisitAnalytics: User not authenticated when deleting visit")
            return false
        }

        let client = await SupabaseManager.shared.getPostgrestClient()

        do {
            try await client
                .from("location_visits")
                .delete()
                .eq("id", value: id)
                .eq("user_id", value: userId.uuidString)
                .execute()

            print("✅ LocationVisitAnalytics: Successfully deleted visit \(id)")
            // Invalidate cache to force refresh on next fetch
            invalidateAllCache()
            return true
        } catch {
            errorMessage = "Failed to delete visit: \(error.localizedDescription)"
            print("❌ LocationVisitAnalytics: Failed to delete visit: \(error.localizedDescription)")
            return false
        }
    }

    /// Merge consecutive visits with gaps <= 10 minutes
    /// Returns (mergedCount, deletedCount)
    func mergeAndCleanupVisits() async -> (merged: Int, deleted: Int) {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ LocationVisitAnalytics: User not authenticated")
            return (0, 0)
        }

        let client = await SupabaseManager.shared.getPostgrestClient()

        do {
            // Fetch all completed visits sorted by entry_time
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: true)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            var allVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            // Only process completed visits
            allVisits = allVisits.filter { $0.exitTime != nil && $0.durationMinutes != nil }

            if allVisits.isEmpty {
                print("✅ No completed visits to process")
                return (0, 0)
            }

            // Group by saved_place_id
            let groupedVisits = Dictionary(grouping: allVisits) { $0.savedPlaceId }

            var totalMerged = 0
            var totalDeleted = 0
            var visitsToDelete: Set<UUID> = []

            // Process each location's visits
            for (placeId, visits) in groupedVisits {
                let sortedVisits = visits.sorted { $0.entryTime < $1.entryTime }

                var i = 0
                while i < sortedVisits.count {
                    let currentVisit = sortedVisits[i]

                    // Check if we can merge with next visit
                    if i + 1 < sortedVisits.count {
                        let nextVisit = sortedVisits[i + 1]

                        // Calculate gap between visits
                        if let currentExit = currentVisit.exitTime {
                            let gapMinutes = Int(nextVisit.entryTime.timeIntervalSince(currentExit) / 60)

                            // CRITICAL: Never merge visits on different calendar days
                            // This preserves midnight splits (e.g., 11:59:59 PM → 12:00:00 AM)
                            let calendar = Calendar.current
                            let currentExitDay = calendar.dateComponents([.year, .month, .day], from: currentExit)
                            let nextEntryDay = calendar.dateComponents([.year, .month, .day], from: nextVisit.entryTime)
                            
                            let areDifferentDays = currentExitDay != nextEntryDay
                            
                            // Also check if either visit was split at midnight (indicated by merge_reason)
                            // Split visits have merge_reason containing "midnight_split"
                            let isMidnightSplit = (currentVisit.mergeReason?.contains("midnight_split") == true) ||
                                                  (nextVisit.mergeReason?.contains("midnight_split") == true)

                            // BLOCK merge if on different days OR if it's a midnight split
                            if areDifferentDays || isMidnightSplit {
                                if areDifferentDays {
                                    print("🚫 MERGE BLOCKED: Visits are on different calendar days")
                                    print("   Current exit: \(currentExit) (day: \(currentExitDay.year ?? 0)-\(currentExitDay.month ?? 0)-\(currentExitDay.day ?? 0))")
                                    print("   Next entry: \(nextVisit.entryTime) (day: \(nextEntryDay.year ?? 0)-\(nextEntryDay.month ?? 0)-\(nextEntryDay.day ?? 0))")
                                }
                                if isMidnightSplit {
                                    print("🚫 MERGE BLOCKED: One or both visits were split at midnight")
                                    print("   Current merge_reason: \(currentVisit.mergeReason ?? "nil")")
                                    print("   Next merge_reason: \(nextVisit.mergeReason ?? "nil")")
                                }
                                i += 1
                                continue
                            }

                            // Merge if gap is 10 minutes or less AND on same day
                            if gapMinutes <= 10 && gapMinutes >= 0 {
                                print("🔄 Merging visits: \(currentVisit.id) and \(nextVisit.id) (gap: \(gapMinutes) min)")

                                // Merge: update first visit to have exit time of second visit
                                if let nextExit = nextVisit.exitTime {
                                    let newDuration = Int(nextExit.timeIntervalSince(currentVisit.entryTime) / 60)

                                    let formatter = ISO8601DateFormatter()
                                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                                    let updateData: [String: PostgREST.AnyJSON] = [
                                        "exit_time": .string(formatter.string(from: nextExit)),
                                        "duration_minutes": .double(Double(newDuration)),
                                        "updated_at": .string(formatter.string(from: Date()))
                                    ]

                                    try await client
                                        .from("location_visits")
                                        .update(updateData)
                                        .eq("id", value: currentVisit.id.uuidString)
                                        .execute()

                                    // Mark second visit for deletion
                                    visitsToDelete.insert(nextVisit.id)
                                    totalMerged += 1

                                    // Skip next visit since it's been merged
                                    i += 2
                                    continue
                                }
                            }
                        }
                    }

                    // Keep all visits regardless of duration
                    i += 1
                }
            }

            // Delete all marked visits
            for visitId in visitsToDelete {
                do {
                    try await client
                        .from("location_visits")
                        .delete()
                        .eq("id", value: visitId.uuidString)
                        .execute()
                } catch {
                    print("⚠️ Failed to delete visit \(visitId): \(error)")
                }
            }

            print("✅ Merged \(totalMerged) visit(s), deleted \(totalDeleted) short visit(s)")

            // Invalidate cache to force refresh
            invalidateAllCache()

            return (totalMerged, totalDeleted)
        } catch {
            print("❌ LocationVisitAnalytics: Failed to merge and cleanup visits: \(error)")
            return (0, 0)
        }
    }

    func cleanupShortVisits() async -> Int {
        // Deprecated: Use mergeAndCleanupVisits() instead
        let (_, deleted) = await mergeAndCleanupVisits()
        return deleted
    }

    /// Fix all visits that span midnight by splitting them into separate day records
    /// This cleans up any existing visits that weren't split at midnight
    /// Returns (fixed count, error count, skipped count)
    /// CRITICAL: This function MUST be called to fix historical visits
    func fixMidnightSpanningVisits() async -> (fixed: Int, errors: Int, skipped: Int) {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ LocationVisitAnalytics: User not authenticated - cannot fix visits")
            return (0, 0, 0)
        }

        let client = await SupabaseManager.shared.getPostgrestClient()

        do {
            print("\n🌙 ===== FIXING MIDNIGHT-SPANNING VISITS =====")
            print("🌙 User ID: \(userId.uuidString)")

            // Fetch all visits
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: false)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let allVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            print("🌙 Total visits fetched: \(allVisits.count)")

            // Filter for completed visits (with exit_time set)
            let completedVisits = allVisits.filter { $0.exitTime != nil }
            print("🌙 Completed visits: \(completedVisits.count)")
            
            // Find visits that span midnight (entry and exit on different days)
            let midnightSpanningVisits = completedVisits.filter { visit in
                guard let exitTime = visit.exitTime else { return false }
                let calendar = Calendar.current
                let entryDay = calendar.component(.day, from: visit.entryTime)
                let exitDay = calendar.component(.day, from: exitTime)
                let entryMonth = calendar.component(.month, from: visit.entryTime)
                let exitMonth = calendar.component(.month, from: exitTime)
                return entryDay != exitDay || entryMonth != exitMonth
            }
            
            print("🌙 Found \(midnightSpanningVisits.count) visits that span midnight!")
            
            if midnightSpanningVisits.isEmpty {
                print("🌙 No midnight-spanning visits to fix")
                return (0, 0, 0)
            }

            var fixedCount = 0
            var errorCount = 0
            var skippedCount = 0
            
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            for visit in midnightSpanningVisits {
                let calendar = Calendar.current
                
                print("\n🌙 Processing visit:")
                print("   ID: \(visit.id)")
                print("   Entry: \(visit.entryTime)")
                print("   Exit: \(visit.exitTime!)")
                print("   Duration: \(visit.durationMinutes ?? 0) min")

                // Calculate the split times
                // Visit 1: entry_time to 11:59:59 PM of entry day
                var endOfEntryDayComponents = calendar.dateComponents([.year, .month, .day], from: visit.entryTime)
                endOfEntryDayComponents.hour = 23
                endOfEntryDayComponents.minute = 59
                endOfEntryDayComponents.second = 59
                
                guard let endOfEntryDay = calendar.date(from: endOfEntryDayComponents) else {
                    print("   ❌ Failed to calculate end of entry day")
                    errorCount += 1
                    continue
                }
                
                // Visit 2: 12:00:00 AM of exit day to exit_time
                let startOfExitDay = calendar.startOfDay(for: visit.exitTime!)
                
                let duration1 = Int(endOfEntryDay.timeIntervalSince(visit.entryTime) / 60)
                let duration2 = Int(visit.exitTime!.timeIntervalSince(startOfExitDay) / 60)
                
                print("   Split 1: \(visit.entryTime) to \(endOfEntryDay) (\(duration1) min)")
                print("   Split 2: \(startOfExitDay) to \(visit.exitTime!) (\(duration2) min)")

                do {
                    // Step 1: Delete the original visit
                    try await client
                        .from("location_visits")
                        .delete()
                        .eq("id", value: visit.id.uuidString)
                        .execute()
                    
                    print("   ✅ Deleted original visit")

                    // Step 2: Create visit 1 (entry day, ends at 11:59:59 PM)
                    let visit1Id = UUID()
                    let visit1Data: [String: PostgREST.AnyJSON] = [
                        "id": .string(visit1Id.uuidString),
                        "user_id": .string(visit.userId.uuidString),
                        "saved_place_id": .string(visit.savedPlaceId.uuidString),
                        "session_id": visit.sessionId != nil ? .string(visit.sessionId!.uuidString) : .null,
                        "entry_time": .string(formatter.string(from: visit.entryTime)),
                        "exit_time": .string(formatter.string(from: endOfEntryDay)),
                        "duration_minutes": .double(Double(max(duration1, 1))),
                        "day_of_week": .string(visit.dayOfWeek),
                        "time_of_day": .string(visit.timeOfDay),
                        "month": .double(Double(visit.month)),
                        "year": .double(Double(visit.year)),
                        "confidence_score": visit.confidenceScore != nil ? .double(visit.confidenceScore!) : .null,
                        "merge_reason": .string("midnight_split_part1"),
                        "created_at": .string(formatter.string(from: visit.createdAt)),
                        "updated_at": .string(formatter.string(from: Date()))
                    ]

                    try await client
                        .from("location_visits")
                        .insert(visit1Data)
                        .execute()
                    
                    print("   ✅ Created split visit 1: ends at 11:59:59 PM")

                    // Step 3: Create visit 2 (exit day, starts at 12:00:00 AM)
                    let visit2Id = UUID()
                    let exitDayComponents = calendar.dateComponents([.weekday, .month, .year], from: startOfExitDay)
                    let exitDayOfWeek = Self.dayOfWeekNameStatic(for: exitDayComponents.weekday ?? 1)
                    
                    let visit2Data: [String: PostgREST.AnyJSON] = [
                        "id": .string(visit2Id.uuidString),
                        "user_id": .string(visit.userId.uuidString),
                        "saved_place_id": .string(visit.savedPlaceId.uuidString),
                        "session_id": visit.sessionId != nil ? .string(visit.sessionId!.uuidString) : .null,
                        "entry_time": .string(formatter.string(from: startOfExitDay)),
                        "exit_time": .string(formatter.string(from: visit.exitTime!)),
                        "duration_minutes": .double(Double(max(duration2, 1))),
                        "day_of_week": .string(exitDayOfWeek),
                        "time_of_day": .string("Night"),
                        "month": .double(Double(exitDayComponents.month ?? 12)),
                        "year": .double(Double(exitDayComponents.year ?? 2025)),
                        "confidence_score": visit.confidenceScore != nil ? .double(visit.confidenceScore!) : .null,
                        "merge_reason": .string("midnight_split_part2"),
                        "created_at": .string(formatter.string(from: visit.createdAt)),
                        "updated_at": .string(formatter.string(from: Date()))
                    ]

                    try await client
                        .from("location_visits")
                        .insert(visit2Data)
                        .execute()
                    
                    print("   ✅ Created split visit 2: starts at 12:00:00 AM")
                    
                    fixedCount += 1
                    
                    // Invalidate cache for this location
                    invalidateCache(for: visit.savedPlaceId)
                    
                } catch {
                    print("   ❌ Error fixing visit: \(error)")
                    errorCount += 1
                }
            }

            print("\n🌙 ===== MIDNIGHT SPLIT FIX COMPLETE =====")
            print("🌙 Fixed: \(fixedCount) visits")
            print("🌙 Errors: \(errorCount)")
            print("🌙 Skipped: \(skippedCount)")
            print("🌙 ==========================================\n")

            // Invalidate all caches to force refresh
            invalidateAllCache()

            return (fixedCount, errorCount, skippedCount)
        } catch {
            print("❌ LocationVisitAnalytics: Failed to fix midnight-spanning visits: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            return (0, 1, 0)
        }
    }
    
    /// Static helper to get day of week name
    private static func dayOfWeekNameStatic(for dayIndex: Int) -> String {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        if dayIndex >= 1 && dayIndex <= 7 {
            return days[dayIndex - 1]
        }
        return "Unknown"
    }

    /// ONE-TIME CLEANUP: Remove duplicate visits created by the midnight split bug
    /// This finds and removes duplicate visits that have overlapping time periods
    func removeDuplicateVisits() async -> (removed: Int, errors: Int) {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ LocationVisitAnalytics: User not authenticated")
            return (0, 0)
        }

        let client = await SupabaseManager.shared.getPostgrestClient()

        do {
            print("\n🧹 ===== REMOVING DUPLICATE VISITS =====")

            // Fetch all visits
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: false)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let allVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            print("🧹 Checking \(allVisits.count) total visits for duplicates...")

            var removedCount = 0
            var errorCount = 0
            var processedIds = Set<UUID>()
            var idsToDelete = Set<UUID>()

            // Group visits by place
            let visitsByPlace = Dictionary(grouping: allVisits) { $0.savedPlaceId }

            for (placeId, visits) in visitsByPlace {
                // Sort by entry time
                let sortedVisits = visits.sorted { $0.entryTime < $1.entryTime }

                for i in 0..<sortedVisits.count {
                    let visit1 = sortedVisits[i]

                    // Skip if already marked for deletion
                    if idsToDelete.contains(visit1.id) || processedIds.contains(visit1.id) {
                        continue
                    }

                    // Check for duplicates with overlapping times
                    for j in (i+1)..<sortedVisits.count {
                        let visit2 = sortedVisits[j]

                        // Skip if already marked for deletion
                        if idsToDelete.contains(visit2.id) {
                            continue
                        }

                        // Check if these visits overlap significantly
                        let overlap = visitsOverlap(visit1, visit2)

                        if overlap {
                            print("\n🧹 Found duplicate visits:")
                            print("   Visit 1: \(visit1.entryTime) to \(visit1.exitTime?.description ?? "nil") (\(visit1.durationMinutes ?? 0) min)")
                            print("   Visit 2: \(visit2.entryTime) to \(visit2.exitTime?.description ?? "nil") (\(visit2.durationMinutes ?? 0) min)")

                            // Keep the one with earlier creation date (original), delete the duplicate
                            let toDelete = visit1.createdAt > visit2.createdAt ? visit1 : visit2
                            idsToDelete.insert(toDelete.id)

                            print("   → Marking for deletion: \(toDelete.id)")
                        }
                    }

                    processedIds.insert(visit1.id)
                }
            }

            // Delete all marked duplicates
            for visitId in idsToDelete {
                do {
                    try await client
                        .from("location_visits")
                        .delete()
                        .eq("id", value: visitId.uuidString)
                        .execute()

                    removedCount += 1
                    print("   ✅ Deleted duplicate visit: \(visitId)")
                } catch {
                    errorCount += 1
                    print("   ❌ Failed to delete visit \(visitId): \(error)")
                }
            }

            print("\n🧹 ===== DUPLICATE REMOVAL COMPLETE =====")
            print("🧹 Removed: \(removedCount) visits")
            print("🧹 Errors: \(errorCount)")
            print("🧹 ==========================================\n")

            // Invalidate all caches to force refresh
            invalidateAllCache()

            return (removedCount, errorCount)
        } catch {
            print("❌ LocationVisitAnalytics: Failed to remove duplicates: \(error)")
            return (0, 1)
        }
    }

    /// Helper function to check if two visits overlap significantly
    private func visitsOverlap(_ visit1: LocationVisitRecord, _ visit2: LocationVisitRecord) -> Bool {
        // Both visits must have exit times to check overlap
        guard let exit1 = visit1.exitTime, let exit2 = visit2.exitTime else {
            return false
        }

        // Check if the time ranges overlap by at least 80%
        let start1 = visit1.entryTime
        let start2 = visit2.entryTime
        let end1 = exit1
        let end2 = exit2

        // Calculate overlap
        let overlapStart = max(start1, start2)
        let overlapEnd = min(end1, end2)

        // If overlap is negative, there's no overlap
        guard overlapEnd > overlapStart else {
            return false
        }

        let overlapDuration = overlapEnd.timeIntervalSince(overlapStart)
        let duration1 = end1.timeIntervalSince(start1)
        let duration2 = end2.timeIntervalSince(start2)
        let shorterDuration = min(duration1, duration2)

        // Consider it a duplicate if overlap is 80% or more of the shorter visit
        let overlapPercentage = overlapDuration / shorterDuration

        return overlapPercentage >= 0.8
    }

    // MARK: - Private Methods

    private func fetchVisits(for placeId: UUID, userId: UUID) async throws -> [LocationVisitRecord] {
        // Removed excessive logging

        let client = await SupabaseManager.shared.getPostgrestClient()

        do {
            let response: [LocationVisitRecord] = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("saved_place_id", value: placeId.uuidString)
                .order("entry_time", ascending: false)
                .execute()
                .value

            return response
        } catch {
            print("❌ LocationVisitAnalytics.fetchVisits: Query failed with error: \(error)")
            throw error
        }
    }

    private func calculateStats(from visits: [LocationVisitRecord], activeVisit: LocationVisitRecord? = nil) -> LocationVisitStats {
        let now = Date()
        let calendar = Calendar.current
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        let totalVisits = visits.count
        let thisMonthVisits = visits.filter { $0.month == currentMonth && $0.year == currentYear }.count
        let thisYearVisits = visits.filter { $0.year == currentYear }.count

        // Calculate average duration including active visit
        var durationsWithValue = visits.compactMap { $0.durationMinutes }

        // If there's an active visit, calculate its elapsed time and include it
        if let active = activeVisit {
            let elapsedMinutes = Int(now.timeIntervalSince(active.entryTime) / 60)
            let durationToInclude = max(elapsedMinutes, 1) // At least 1 minute like completed visits
            durationsWithValue.append(durationToInclude)
        }

        let averageDuration = durationsWithValue.isEmpty
            ? 0.0
            : Double(durationsWithValue.reduce(0, +)) / Double(durationsWithValue.count)

        // Find most common time of day
        let timeOfDayFrequency = Dictionary(grouping: visits, by: { $0.timeOfDay })
        let mostCommonTimeOfDay = timeOfDayFrequency.max { $0.value.count < $1.value.count }?.key

        // Find most common day of week
        let dayFrequency = Dictionary(grouping: visits, by: { $0.dayOfWeek })
        let mostCommonDayOfWeek = dayFrequency.max { $0.value.count < $1.value.count }?.key

        return LocationVisitStats(
            totalVisits: totalVisits,
            averageDurationMinutes: averageDuration,
            lastVisitDate: visits.first?.entryTime,
            mostCommonTimeOfDay: mostCommonTimeOfDay,
            mostCommonDayOfWeek: mostCommonDayOfWeek,
            thisMonthVisits: thisMonthVisits,
            thisYearVisits: thisYearVisits
        )
    }
}

// MARK: - Formatting Extensions

extension LocationVisitStats {
    var formattedLastVisit: String {
        guard let lastVisit = lastVisitDate else { return "Never" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastVisit, relativeTo: Date())
    }

    var formattedAverageDuration: String {
        if averageDurationMinutes < 1 {
            return "< 1 min"
        } else if averageDurationMinutes < 60 {
            return String(format: "%.0f min", averageDurationMinutes)
        } else {
            let hours = Int(averageDurationMinutes) / 60
            let minutes = Int(averageDurationMinutes) % 60
            return "\(hours)h \(minutes)m"
        }
    }

    var formattedPeakTime: String {
        let components: [String?] = [mostCommonDayOfWeek, mostCommonTimeOfDay]
        let nonNilComponents = components.compactMap { $0 }

        if nonNilComponents.isEmpty {
            return "No data"
        }

        return nonNilComponents.joined(separator: " • ")
    }

    var summaryText: String {
        var parts: [String] = []

        parts.append("Visited \(totalVisits) times")

        if averageDurationMinutes > 0 {
            parts.append("Avg \(formattedAverageDuration)")
        }

        if !formattedPeakTime.isEmpty && formattedPeakTime != "No data" {
            parts.append("Usually \(formattedPeakTime)")
        }

        return parts.joined(separator: " • ")
    }
}
