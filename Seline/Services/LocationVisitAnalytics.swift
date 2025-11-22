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
            print("📊 Using cached stats for place \(placeId) (age: \(Int(Date().timeIntervalSince(cachedStats.timestamp)))s)")
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

        print("📊 LocationVisitAnalytics: Fetching visits for place \(placeId) with user \(userId)")

        do {
            let visits = try await fetchVisits(for: placeId, userId: userId)
            print("📊 LocationVisitAnalytics: Found \(visits.count) visits for place \(placeId)")

            // Include the active visit if one exists for this location
            let activeVisit = GeofenceManager.shared.activeVisits[placeId]
            let stats = calculateStats(from: visits, activeVisit: activeVisit)

            await MainActor.run {
                self.visitStats[placeId] = stats
                // OPTIMIZATION: Cache the stats with current timestamp
                self.statsCache[placeId] = CachedStats(stats: stats, timestamp: Date())
            }

            print("📊 Fetched stats for place \(placeId): \(stats.totalVisits) visits, Peak time: \(stats.mostCommonTimeOfDay ?? "N/A")")
        } catch {
            errorMessage = "Failed to fetch visit stats: \(error.localizedDescription)"
            print("❌ Error fetching stats for place \(placeId): \(error.localizedDescription)")
            print("   Full error: \(error)")
        }

        isLoading = false
    }

    /// Fetch all visit stats for all favorite locations
    func fetchAllStats(for places: [SavedPlace]) async {
        for place in places where place.isFavourite {
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

    // MARK: - Private Methods

    private func fetchVisits(for placeId: UUID, userId: UUID) async throws -> [LocationVisitRecord] {
        print("📊 LocationVisitAnalytics.fetchVisits: Querying location_visits for place=\(placeId), user=\(userId)")

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

            print("📊 LocationVisitAnalytics.fetchVisits: Query returned \(response.count) records")
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
