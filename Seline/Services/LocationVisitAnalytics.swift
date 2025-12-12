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

// MARK: - Cache Models

struct CachedStats {
    let stats: LocationVisitStats
    let timestamp: Date

    func isExpired(ttlSeconds: TimeInterval = 3600) -> Bool {
        return Date().timeIntervalSince(timestamp) > ttlSeconds
    }
}

@MainActor
class LocationVisitAnalytics: ObservableObject {
    static let shared = LocationVisitAnalytics()

    @Published var visitStats: [UUID: LocationVisitStats] = [:] // [placeId: stats]
    @Published var isLoading = false
    @Published var errorMessage: String?

    // OPTIMIZATION: Cache stats with TTL (time-to-live)
    // Avoids redundant Supabase queries for the same location within 1 hour
    private var statsCache: [UUID: CachedStats] = [:]
    private let statscacheTTL: TimeInterval = 3600 // 1 hour

    private let authManager = AuthenticationManager.shared

    // MARK: - Public Methods

    /// Fetch and calculate stats for a specific saved place
    func fetchStats(for placeId: UUID) async {
        // OPTIMIZATION: Check cache first before querying Supabase
        if let cachedStats = statsCache[placeId], !cachedStats.isExpired(ttlSeconds: statscacheTTL) {
            // DEBUG: Commented out to reduce console spam
            // print("📊 Using cached stats for place \(placeId) (age: \(Int(Date().timeIntervalSince(cachedStats.timestamp)))s)")
            self.visitStats[placeId] = cachedStats.stats
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

        // Removed excessive logging
        do {
            let visits = try await fetchVisits(for: placeId, userId: userId)

            // Include the active visit if one exists for this location
            let activeVisit = GeofenceManager.shared.activeVisits[placeId]
            let stats = calculateStats(from: visits, activeVisit: activeVisit)

            await MainActor.run {
                self.visitStats[placeId] = stats
                // OPTIMIZATION: Cache the stats with current timestamp
                self.statsCache[placeId] = CachedStats(stats: stats, timestamp: Date())
            }

            // DEBUG: Commented out to reduce console spam
            // print("📊 Fetched stats for place \(placeId): \(stats.totalVisits) visits, Peak time: \(stats.mostCommonTimeOfDay ?? "N/A")")
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
        return sorted.map { (id: $0.id, displayName: $0.displayName, totalDurationMinutes: $0.totalDurationMinutes, isActive: $0.isActive) }
    }

    // MARK: - Cache Management

    /// Invalidate cache for a specific place (call when visit is recorded/updated)
    func invalidateCache(for placeId: UUID) {
        statsCache.removeValue(forKey: placeId)
        print("🔄 Invalidated stats cache for place \(placeId)")
    }

    /// Invalidate all cached stats
    func invalidateAllCache() {
        statsCache.removeAll()
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

    /// Clean up all visits shorter than 10 minutes (false positives from GPS glitches, passing by, etc.)
    /// Merge consecutive visits and cleanup short visits
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

                            // Merge if gap is 10 minutes or less
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

                    // If visit is < 10 minutes and wasn't merged, mark for deletion
                    if let duration = currentVisit.durationMinutes, duration < 10 {
                        print("🗑️ Marking short visit for deletion: \(currentVisit.id) (duration: \(duration) min)")
                        visitsToDelete.insert(currentVisit.id)
                        totalDeleted += 1
                    }

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
