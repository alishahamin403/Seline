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

struct WeeklyVisitSummaryItem {
    let placeId: UUID
    let placeName: String
    let totalMinutes: Int
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
    /// OPTIMIZATION: Parallel fetching with backpressure control (max 3 concurrent)
    func fetchAllStats(for places: [SavedPlace]) async {
        await withTaskGroup(of: Void.self) { group in
            var activeCount = 0
            let maxConcurrent = 3

            for place in places {
                // Wait if we've hit the concurrency limit
                if activeCount >= maxConcurrent {
                    await group.next()
                    activeCount -= 1
                }

                group.addTask {
                    await self.fetchStats(for: place.id)
                }
                activeCount += 1
            }

            // Wait for remaining tasks
            await group.waitForAll()
        }
    }

    /// Get visit history for a specific place
    /// CRITICAL: Handles midnight-spanning visits by splitting them and deduplicating
    func fetchVisitHistory(for placeId: UUID, limit: Int = 20) async -> [VisitHistoryItem] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            errorMessage = "User not authenticated"
            return []
        }

        do {
            let visits = try await fetchVisits(for: placeId, userId: userId)
            let place = LocationsManager.shared.savedPlaces.first { $0.id == placeId }

            // CRITICAL FIX: Process visits to handle midnight splits properly
            var processedVisits: [LocationVisitRecord] = []
            var hasMidnightSpanningVisits = false

            // Track which time ranges have split visits to avoid duplicates
            var splitVisitTimeRanges: Set<String> = []

            // First pass: identify all split visits and their time ranges
            for visit in visits {
                if visit.mergeReason?.contains("midnight_split") == true {
                    // Create a key for this split's original time range
                    // Use the session_id to group related splits
                    if let sessionId = visit.sessionId {
                        splitVisitTimeRanges.insert(sessionId.uuidString)
                    }
                }
            }

            // Second pass: process visits
            for visit in visits {
                // Skip unsplit visits that have corresponding split versions
                // These are "orphaned" original visits that weren't deleted after splitting
                if visit.spansMidnight() && visit.exitTime != nil && visit.mergeReason?.contains("midnight_split") != true {
                    // Check if this visit has split versions by looking for visits with same session_id
                    if let sessionId = visit.sessionId, splitVisitTimeRanges.contains(sessionId.uuidString) {
                        print("🔄 fetchVisitHistory: Skipping orphaned unsplit visit \(visit.id) (has split versions)")
                        hasMidnightSpanningVisits = true
                        continue
                    }

                    // No split versions exist - split on the fly for display
                    hasMidnightSpanningVisits = true
                    let splitVisits = visit.splitAtMidnightIfNeeded()
                    processedVisits.append(contentsOf: splitVisits)
                    print("🌙 fetchVisitHistory: Split midnight-spanning visit \(visit.id) into \(splitVisits.count) parts for display")
                } else {
                    // Normal visit or already split - add as-is
                    processedVisits.append(visit)
                }
            }

            // Trigger background fix if we found midnight-spanning visits
            if hasMidnightSpanningVisits {
                Task.detached(priority: .background) {
                    print("🌙 AUTO-FIX: Detected midnight-spanning visits in history, running fix...")
                    let result = await LocationVisitAnalytics.shared.fixMidnightSpanningVisits()
                    if result.fixed > 0 {
                        print("✅ AUTO-FIX: Fixed \(result.fixed) midnight-spanning visits")
                        await MainActor.run {
                            LocationVisitAnalytics.shared.invalidateAllCache()
                        }
                    }
                }
            }

            // Sort by entry time (most recent first) and limit
            let sortedVisits = processedVisits
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
    /// CRITICAL: This now handles midnight-spanning visits by splitting them for display
    func getVisitsInDateRange(for placeId: UUID, startDate: Date, endDate: Date) async -> [LocationVisitRecord] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return []
        }

        do {
            let visits = try await fetchVisits(for: placeId, userId: userId)

            // Process visits - split any that span midnight for proper display
            var processedVisits: [LocationVisitRecord] = []
            var hasMidnightSpanningVisits = false

            for visit in visits {
                // Check if this visit spans midnight
                if visit.spansMidnight(), visit.exitTime != nil {
                    hasMidnightSpanningVisits = true
                    
                    // Split the visit into parts for each day
                    let splitVisits = visit.splitAtMidnightIfNeeded()
                    
                    // Add splits that fall within our date range
                    for splitVisit in splitVisits {
                        if splitVisit.entryTime >= startDate && splitVisit.entryTime <= endDate {
                            processedVisits.append(splitVisit)
                        }
                    }
                } else {
                    // Normal visit - just check if it's in range
                    if visit.entryTime >= startDate && visit.entryTime <= endDate {
                        processedVisits.append(visit)
                    }
                }
            }

            // CRITICAL: If we found midnight-spanning visits, trigger a background fix
            // This ensures the database gets cleaned up over time
            if hasMidnightSpanningVisits {
                Task.detached(priority: .background) {
                    print("🌙 AUTO-FIX: Detected midnight-spanning visits, running fix in background...")
                    let result = await LocationVisitAnalytics.shared.fixMidnightSpanningVisits()
                    if result.fixed > 0 {
                        print("✅ AUTO-FIX: Fixed \(result.fixed) midnight-spanning visits")
                        // Invalidate cache to show corrected data
                        await MainActor.run {
                            LocationVisitAnalytics.shared.invalidateAllCache()
                        }
                    }
                }
            }

            return processedVisits
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Task was cancelled (e.g., view refreshed) - this is expected, don't log as error
            return []
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

    /// Get summary of visits for the current week starting from a specific date
    func getWeeklyVisitsSummary(from startDate: Date) async -> [WeeklyVisitSummaryItem] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return []
        }
        
        // End date is today
        let endDate = Date()
        
        // Fetch all saved places
        let allPlaces = LocationsManager.shared.savedPlaces
        var summaryItems: [WeeklyVisitSummaryItem] = []
        
        // For each place, get visits in range
        // Note: This could be optimized with a specialized Supabase query, but reusing existing logic for now
        for place in allPlaces {
            let visits = await getVisitsInDateRange(for: place.id, startDate: startDate, endDate: endDate)
            if !visits.isEmpty {
                let totalMinutes = visits.reduce(0) { $0 + ($1.durationMinutes ?? 0) }
                if totalMinutes > 0 {
                    summaryItems.append(WeeklyVisitSummaryItem(placeId: place.id, placeName: place.displayName, totalMinutes: totalMinutes))
                }
            }
        }
        
        return summaryItems
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
                // Calculate total duration for today ONLY (clip to today's boundaries)
                var totalMinutes = 0
                var latestVisitTime: Date = .distantPast

                for visit in visits {
                    // Calculate how much of this visit occurred TODAY
                    let visitStart = visit.entryTime
                    let visitEnd = visit.exitTime ?? Date()
                    
                    // Clip visit to today's boundaries
                    let effectiveStart = max(visitStart, startOfDay)
                    let effectiveEnd = min(visitEnd, endOfDay)
                    
                    // Only count if there's overlap with today
                    if effectiveStart < effectiveEnd {
                        let minutesInToday = Int(effectiveEnd.timeIntervalSince(effectiveStart) / 60)
                        totalMinutes += minutesInToday
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

    /// Manually merge two visits together
    /// Uses the entry time of the first visit and exit time of the second visit
    /// The second visit is deleted after merging
    /// - Parameters:
    ///   - firstVisitId: UUID of the first visit (will keep its entry time)
    ///   - secondVisitId: UUID of the second visit (will be deleted, its exit time is used)
    /// - Returns: True if merge was successful
    func manualMergeVisits(firstVisitId: UUID, secondVisitId: UUID) async -> Bool {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            errorMessage = "User not authenticated"
            print("❌ LocationVisitAnalytics: User not authenticated when merging visits")
            return false
        }

        let client = await SupabaseManager.shared.getPostgrestClient()

        do {
            // Fetch both visits
            print("🔍 LocationVisitAnalytics: Looking for visits with IDs:")
            print("   First: \(firstVisitId.uuidString)")
            print("   Second: \(secondVisitId.uuidString)")
            
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .in("id", values: [firstVisitId.uuidString, secondVisitId.uuidString])
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
            
            print("🔍 LocationVisitAnalytics: Found \(visits.count) visits in database")
            for visit in visits {
                print("   - ID: \(visit.id), Entry: \(visit.entryTime), PlaceID: \(visit.savedPlaceId)")
            }

            guard visits.count == 2 else {
                print("❌ LocationVisitAnalytics: Could not find both visits to merge (found \(visits.count))")
                errorMessage = "Could not find both visits (found \(visits.count) of 2)"
                return false
            }

            // Find the first and second visits by ID
            guard let firstVisit = visits.first(where: { $0.id == firstVisitId }),
                  let secondVisit = visits.first(where: { $0.id == secondVisitId }) else {
                print("❌ LocationVisitAnalytics: Could not identify visits by ID")
                return false
            }

            // Verify both visits are at the same place
            guard firstVisit.savedPlaceId == secondVisit.savedPlaceId else {
                print("❌ LocationVisitAnalytics: Cannot merge visits at different locations")
                errorMessage = "Cannot merge visits at different locations"
                return false
            }

            // Get the exit time from the second visit (use current time if no exit time)
            let newExitTime = secondVisit.exitTime ?? Date()

            // Calculate new duration
            let newDurationMinutes = max(1, Int(newExitTime.timeIntervalSince(firstVisit.entryTime) / 60))

            // Preserve visit notes from either visit (prefer first visit's notes, but use second's if first is empty)
            let mergedNotes: String? = {
                let firstNotes = firstVisit.visitNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let secondNotes = secondVisit.visitNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !firstNotes.isEmpty && !secondNotes.isEmpty {
                    // Both have notes - combine them
                    return "\(firstNotes); \(secondNotes)"
                } else if !firstNotes.isEmpty {
                    return firstNotes
                } else if !secondNotes.isEmpty {
                    return secondNotes
                }
                return nil
            }()

            // Update first visit with new exit time, duration, and preserved notes
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            var updateData: [String: PostgREST.AnyJSON] = [
                "exit_time": .string(formatter.string(from: newExitTime)),
                "duration_minutes": .double(Double(newDurationMinutes)),
                "merge_reason": .string("manual_merge"),
                "updated_at": .string(formatter.string(from: Date()))
            ]

            // Add visit_notes to update if we have any notes to preserve
            if let notes = mergedNotes {
                updateData["visit_notes"] = .string(notes)
                print("📝 Preserving visit notes in merged visit: \(notes)")
            }

            try await client
                .from("location_visits")
                .update(updateData)
                .eq("id", value: firstVisitId.uuidString)
                .execute()

            print("✅ Updated first visit with merged data")

            // Delete the second visit
            try await client
                .from("location_visits")
                .delete()
                .eq("id", value: secondVisitId.uuidString)
                .execute()

            print("✅ Deleted second visit after merge")

            // Invalidate caches
            invalidateCache(for: firstVisit.savedPlaceId)
            invalidateAllCache()

            print("✅ Successfully merged visits: \(firstVisit.entryTime) to \(newExitTime) (duration: \(newDurationMinutes) min)")

            return true
        } catch {
            errorMessage = "Failed to merge visits: \(error.localizedDescription)"
            print("❌ LocationVisitAnalytics: Failed to merge visits: \(error)")
            return false
        }
    }

    /// Merge consecutive visits with gaps <= 5 minutes
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
                                // Skip merging - visits should remain separate
                                i += 1
                                continue
                            }

                            // Merge if gap is 5 minutes or less AND on same day
                            if gapMinutes <= 5 && gapMinutes >= 0 {
                                print("🔄 Merging visits: \(currentVisit.id) and \(nextVisit.id) (gap: \(gapMinutes) min)")

                                // Merge: update first visit to have exit time of second visit
                                if let nextExit = nextVisit.exitTime {
                                    let newDuration = max(Int(nextExit.timeIntervalSince(currentVisit.entryTime) / 60), 1)

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
            formatter.timeZone = TimeZone(identifier: "UTC") // CRITICAL: Ensure UTC for Supabase compatibility

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
                print("   DEBUG: startOfExitDay formatted = \(formatter.string(from: startOfExitDay))")

                do {
                    // IDEMPOTENCY CHECK: Check if split visits already exist
                    // NOTE: We check for ANY visit starting at midnight with midnight_split merge_reason
                    let searchStartTime = formatter.string(from: startOfExitDay)
                    print("   DEBUG: Searching for existing splits at entry_time = \(searchStartTime)")
                    
                    let response = try await client
                        .from("location_visits")
                        .select()
                        .eq("user_id", value: userId.uuidString)
                        .eq("saved_place_id", value: visit.savedPlaceId.uuidString)
                        .eq("entry_time", value: searchStartTime)
                        .execute()
                    
                    let decoder = JSONDecoder.supabaseDecoder()
                    let existingVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)
                    
                    print("   DEBUG: Found \(existingVisits.count) existing visits at that time")
                    for ev in existingVisits {
                        print("     - ID: \(ev.id), merge_reason: \(ev.mergeReason ?? "nil")")
                    }
                    
                    let existingSplits = existingVisits.filter { $0.mergeReason?.contains("midnight_split") == true }

                    if !existingSplits.isEmpty {
                        // Verify splits are complete (should have 2 parts covering full duration)
                        let expectedDuration = visit.durationMinutes ?? 0
                        let splitsDuration = existingSplits.compactMap { $0.durationMinutes }.reduce(0, +)
                        let hasBothParts = existingSplits.contains { $0.mergeReason?.contains("part1") == true } &&
                                          existingSplits.contains { $0.mergeReason?.contains("part2") == true }

                        if hasBothParts && abs(expectedDuration - splitsDuration) < 5 {
                            print("   ⚠️ IDEMPOTENCY: Complete split visits already exist")
                            print("   🧹 CLEANUP: Deleting orphaned original visit...")

                            try await client
                                .from("location_visits")
                                .delete()
                                .eq("id", value: visit.id.uuidString)
                                .execute()

                            print("   ✅ Deleted orphaned original visit: \(visit.id)")
                            fixedCount += 1
                        } else {
                            print("   ⚠️ Incomplete splits found, keeping original for safety")
                            skippedCount += 1
                        }
                        continue
                    }

                    // CRITICAL FIX: Create BOTH splits FIRST, then delete original
                    print("   📝 Creating split visits BEFORE deleting original...")

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

                    // CRITICAL: Only delete original AFTER both splits are confirmed saved
                    try await client
                        .from("location_visits")
                        .delete()
                        .eq("id", value: visit.id.uuidString)
                        .execute()

                    print("   ✅ Deleted original visit after successful split creation")

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

                        // CRITICAL: Skip midnight split pairs - they are NOT duplicates!
                        // Split pairs have complementary merge reasons (part1/part2) and adjacent times
                        let visit1IsSplit = visit1.mergeReason?.contains("midnight_split") == true
                        let visit2IsSplit = visit2.mergeReason?.contains("midnight_split") == true

                        if visit1IsSplit && visit2IsSplit {
                            // Check if they're a valid split pair (part1 ends at midnight, part2 starts at midnight)
                            let calendar = Calendar.current
                            if let exit1 = visit1.exitTime {
                                let hour1 = calendar.component(.hour, from: exit1)
                                let minute1 = calendar.component(.minute, from: exit1)
                                let hour2 = calendar.component(.hour, from: visit2.entryTime)
                                let minute2 = calendar.component(.minute, from: visit2.entryTime)

                                // Part1 ends at 23:59, Part2 starts at 00:00 = valid split pair
                                let isValidSplitPair = (hour1 == 23 && minute1 >= 59 && hour2 == 0 && minute2 == 0)
                                if isValidSplitPair {
                                    print("   ⏭️ Skipping valid midnight split pair")
                                    continue
                                }
                            }
                        }

                        // Check if these visits overlap significantly
                        let overlap = visitsOverlap(visit1, visit2)

                        if overlap {
                            print("\n🧹 Found duplicate visits:")
                            print("   Visit 1: \(visit1.entryTime) to \(visit1.exitTime?.description ?? "nil") (\(visit1.durationMinutes ?? 0) min) [merge: \(visit1.mergeReason ?? "none")]")
                            print("   Visit 2: \(visit2.entryTime) to \(visit2.exitTime?.description ?? "nil") (\(visit2.durationMinutes ?? 0) min) [merge: \(visit2.mergeReason ?? "none")]")

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

    /// CLEANUP: Deletes orphaned unsplit visits that have corresponding split versions
    /// This handles the case where a midnight-spanning visit was split but the original wasn't deleted
    /// Returns (deleted count, error count)
    func cleanupOrphanedUnsplitVisits() async -> (deleted: Int, errors: Int) {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("❌ LocationVisitAnalytics: User not authenticated")
            return (0, 0)
        }

        let client = await SupabaseManager.shared.getPostgrestClient()

        do {
            print("\n🧹 ===== CLEANING UP ORPHANED UNSPLIT VISITS =====")

            // Fetch all visits
            let response = try await client
                .from("location_visits")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("entry_time", ascending: false)
                .execute()

            let decoder = JSONDecoder.supabaseDecoder()
            let allVisits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

            print("🧹 Total visits: \(allVisits.count)")

            var deletedCount = 0
            var errorCount = 0

            // Find unsplit visits that span midnight
            let unsplitMidnightVisits = allVisits.filter { visit in
                // Must have exit time, span midnight, and NOT have merge_reason set
                visit.exitTime != nil &&
                visit.spansMidnight() &&
                (visit.mergeReason == nil || !visit.mergeReason!.contains("midnight_split"))
            }

            print("🧹 Found \(unsplitMidnightVisits.count) unsplit midnight-spanning visits")

            // Find all split visits (with midnight_split merge_reason)
            let splitVisits = allVisits.filter { $0.mergeReason?.contains("midnight_split") == true }

            for unsplitVisit in unsplitMidnightVisits {
                // Check if corresponding split visits exist
                // They would have the same session_id and merge_reason containing "midnight_split"
                let correspondingSplits = splitVisits.filter { splitVisit in
                    // Match by session_id
                    if let unsplitSession = unsplitVisit.sessionId, let splitSession = splitVisit.sessionId {
                        return unsplitSession == splitSession
                    }
                    // Or match by overlapping time range (same place, times overlap)
                    return splitVisit.savedPlaceId == unsplitVisit.savedPlaceId &&
                           splitVisit.entryTime >= unsplitVisit.entryTime &&
                           (splitVisit.exitTime ?? Date()) <= (unsplitVisit.exitTime ?? Date())
                }

                if correspondingSplits.count >= 2 {
                    // Verify splits cover the expected time range
                    let hasPart1 = correspondingSplits.contains { $0.mergeReason?.contains("part1") == true }
                    let hasPart2 = correspondingSplits.contains { $0.mergeReason?.contains("part2") == true }

                    if hasPart1 && hasPart2 {
                        print("🧹 Found orphaned unsplit visit: \(unsplitVisit.id)")
                        print("   Entry: \(unsplitVisit.entryTime), Exit: \(unsplitVisit.exitTime?.description ?? "nil")")
                        print("   Has \(correspondingSplits.count) corresponding split visits")

                        // Delete the orphaned unsplit visit
                        do {
                            try await client
                                .from("location_visits")
                                .delete()
                                .eq("id", value: unsplitVisit.id.uuidString)
                                .execute()

                            deletedCount += 1
                            print("   ✅ Deleted orphaned visit: \(unsplitVisit.id)")
                        } catch {
                            errorCount += 1
                            print("   ❌ Failed to delete: \(error)")
                        }
                    }
                }
            }

            print("\n🧹 ===== ORPHANED CLEANUP COMPLETE =====")
            print("🧹 Deleted: \(deletedCount) orphaned visits")
            print("🧹 Errors: \(errorCount)")
            print("🧹 ========================================\n")

            // Invalidate caches
            invalidateAllCache()

            return (deletedCount, errorCount)
        } catch {
            print("❌ LocationVisitAnalytics: Failed to cleanup orphaned visits: \(error)")
            return (0, 1)
        }
    }

    /// Run all visit cleanup operations: fix midnight spans, remove duplicates, cleanup orphans
    /// This is a comprehensive cleanup that should be run periodically or on user request
    func runFullVisitCleanup() async -> (midnightFixed: Int, duplicatesRemoved: Int, orphansDeleted: Int, errors: Int) {
        print("\n🧹🧹🧹 ===== RUNNING FULL VISIT CLEANUP ===== 🧹🧹🧹\n")

        // Step 1: Fix midnight-spanning visits
        let midnightResult = await fixMidnightSpanningVisits()

        // Step 2: Cleanup orphaned unsplit visits
        let orphanResult = await cleanupOrphanedUnsplitVisits()

        // Step 3: Remove any remaining duplicates
        let duplicateResult = await removeDuplicateVisits()

        // Step 4: Merge close visits (optional cleanup)
        let mergeResult = await mergeAndCleanupVisits()

        print("\n🧹🧹🧹 ===== FULL CLEANUP COMPLETE ===== 🧹🧹🧹")
        print("   Midnight splits fixed: \(midnightResult.fixed)")
        print("   Orphaned visits deleted: \(orphanResult.deleted)")
        print("   Duplicates removed: \(duplicateResult.removed)")
        print("   Visits merged: \(mergeResult.merged)")
        print("   Total errors: \(midnightResult.errors + orphanResult.errors + duplicateResult.errors)")
        print("🧹🧹🧹 ========================================= 🧹🧹🧹\n")

        return (
            midnightFixed: midnightResult.fixed,
            duplicatesRemoved: duplicateResult.removed,
            orphansDeleted: orphanResult.deleted,
            errors: midnightResult.errors + orphanResult.errors + duplicateResult.errors
        )
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

            // DATA INTEGRITY FIX: Sanitize visits with invalid timestamps or negative durations
            return response.map { visit in
                var sanitized = visit
                
                // Case 1: Exit time is before entry time (impossible)
                if let exit = sanitized.exitTime, exit < sanitized.entryTime {
                    print("⚠️ LocationVisitAnalytics: Found invalid visit timestamps (exit < entry): \(visit.id)")
                    // Fix: Set exit to entry + 1 minute
                    let newExit = sanitized.entryTime.addingTimeInterval(60)
                    sanitized.exitTime = newExit
                    sanitized.durationMinutes = 1
                }
                
                // Case 2: Negative duration (but timestamps might be okay)
                else if let duration = sanitized.durationMinutes, duration <= 0, let exit = sanitized.exitTime {
                    print("⚠️ LocationVisitAnalytics: Found invalid visit duration (\(duration)m): \(visit.id)")
                    // Recalculate duration from timestamps
                    let calculatedData = Int(exit.timeIntervalSince(sanitized.entryTime) / 60)
                    sanitized.durationMinutes = max(calculatedData, 1)
                }
                
            return sanitized
            }
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Task was cancelled (e.g., view refreshed) - this is expected, don't log as error
            throw urlError
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
