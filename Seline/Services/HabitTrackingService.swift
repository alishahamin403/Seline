import Foundation
import CoreLocation

/// HabitTrackingService: Tracks location visit patterns and notifies users about streaks and habits
/// Analyzes visit data to identify routines and encourage habit formation
@MainActor
class HabitTrackingService: ObservableObject {
    static let shared = HabitTrackingService()

    private let notificationService = NotificationService.shared
    private let visitAnalytics = LocationVisitAnalytics.shared

    // Preferences
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "habitTrackingEnabled")
        }
    }

    // Track which locations have been notified for streaks to avoid spam
    private var streakNotificationsShown: Set<String> = [] // "placeId-streakCount"

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "habitTrackingEnabled")

        // Default: enabled
        if !UserDefaults.standard.bool(forKey: "habitTrackingEnabledSet") {
            self.isEnabled = true
            UserDefaults.standard.set(true, forKey: "habitTrackingEnabledSet")
        }
    }

    // MARK: - Streak Detection

    /// Check for streaks when a new visit is created
    func checkForStreaks(at placeId: UUID) async {
        guard isEnabled else { return }

        // Fetch visit statistics for this location
        await visitAnalytics.fetchStats(for: placeId)

        // Check for consecutive day streaks
        if let streak = await detectConsecutiveDayStreak(placeId: placeId) {
            await handleStreakDetected(
                placeId: placeId,
                locationName: getLocationName(for: placeId) ?? "Unknown Location",
                streakDays: streak
            )
        }
    }

    /// Detect consecutive day streaks for a location
    private func detectConsecutiveDayStreak(placeId: UUID) async -> Int? {
        // Fetch visit history for this location
        guard let visits = try? await fetchRecentVisits(placeId: placeId, days: 30) else {
            return nil
        }

        // Group visits by day
        let calendar = Calendar.current
        var visitDays: Set<Date> = []

        for visit in visits {
            let dayStart = calendar.startOfDay(for: visit.entryTime)
            visitDays.insert(dayStart)
        }

        // Sort days in descending order (most recent first)
        let sortedDays = visitDays.sorted(by: >)

        // Count consecutive days starting from today
        var streakCount = 0
        var checkDate = calendar.startOfDay(for: Date())

        for day in sortedDays {
            if calendar.isDate(day, inSameDayAs: checkDate) {
                streakCount += 1
                // Move to previous day
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else if day < checkDate {
                // Gap in streak
                break
            }
        }

        // Only return streaks of 3+ days
        return streakCount >= 3 ? streakCount : nil
    }

    /// Handle streak detection and send notifications
    private func handleStreakDetected(placeId: UUID, locationName: String, streakDays: Int) async {
        // Check if we've already notified for this streak level
        let notificationKey = "\(placeId.uuidString)-\(streakDays)"

        guard !streakNotificationsShown.contains(notificationKey) else {
            return // Already notified
        }

        // Send notification for milestone streaks (3, 7, 14, 30, 60, 100 days)
        let milestones = [3, 7, 14, 30, 60, 100]

        if milestones.contains(streakDays) {
            await notificationService.scheduleHabitStreakNotification(
                locationName: locationName,
                streakDays: streakDays,
                habitType: "visit"
            )

            // Mark as shown
            streakNotificationsShown.insert(notificationKey)

            print("🔥 Sent streak notification for \(locationName): \(streakDays) days")
        }
    }

    // MARK: - Habit Pattern Detection

    /// Analyze location patterns and send habit reminders
    func analyzeHabitPatterns() async {
        guard isEnabled else { return }

        let locationsManager = LocationsManager.shared
        let savedPlaces = locationsManager.savedPlaces

        for place in savedPlaces {
            await analyzePattern(for: place)
        }
    }

    /// Analyze visit pattern for a specific location
    private func analyzePattern(for place: SavedPlace) async {
        // Fetch stats for this location
        await visitAnalytics.fetchStats(for: place.id)

        guard let stats = visitAnalytics.visitStats[place.id] else {
            return
        }

        // Get detailed time and day breakdown
        let (timeOfDayBreakdown, dayOfWeekBreakdown) = await visitAnalytics.getBothTimeAndDayStats(for: place.id)

        // Check if there's a consistent pattern (e.g., "usually visit on Thursdays at 6 PM")
        if let pattern = detectConsistentPattern(
            stats: stats,
            timeOfDayBreakdown: timeOfDayBreakdown,
            dayOfWeekBreakdown: dayOfWeekBreakdown
        ) {
            // Check if user hasn't visited yet today and it's near their usual time
            let shouldRemind = await shouldSendHabitReminder(
                for: place.id,
                pattern: pattern
            )

            if shouldRemind {
                await notificationService.scheduleHabitReminderNotification(
                    locationName: place.displayName,
                    usualTime: pattern.timeDescription,
                    daysActive: stats.totalVisits
                )

                print("💪 Sent habit reminder for \(place.displayName)")
            }
        }
    }

    private struct HabitPattern {
        let dayOfWeek: String?
        let timeOfDay: String
        let frequency: Int // visits per week/month

        var timeDescription: String {
            if let day = dayOfWeek {
                return "\(day)s at \(timeOfDay)"
            }
            return timeOfDay
        }
    }

    /// Detect if there's a consistent visit pattern
    private func detectConsistentPattern(
        stats: LocationVisitStats,
        timeOfDayBreakdown: [String: Int],
        dayOfWeekBreakdown: [String: Int]
    ) -> HabitPattern? {
        // Check if there's a dominant day of week
        if let mostCommonDay = dayOfWeekBreakdown.max(by: { $0.value < $1.value }) {
            // If more than 40% of visits are on this day, consider it a pattern
            let percentage = Double(mostCommonDay.value) / Double(stats.totalVisits)

            if percentage > 0.4 {
                // Find most common time of day
                if let mostCommonTime = timeOfDayBreakdown.max(by: { $0.value < $1.value }) {
                    return HabitPattern(
                        dayOfWeek: mostCommonDay.key,
                        timeOfDay: mostCommonTime.key,
                        frequency: mostCommonDay.value
                    )
                }
            }
        }

        // Check for consistent time of day (even if not specific day)
        if let mostCommonTime = timeOfDayBreakdown.max(by: { $0.value < $1.value }) {
            let percentage = Double(mostCommonTime.value) / Double(stats.totalVisits)

            if percentage > 0.5 {
                return HabitPattern(
                    dayOfWeek: nil,
                    timeOfDay: mostCommonTime.key,
                    frequency: mostCommonTime.value
                )
            }
        }

        return nil
    }

    /// Check if we should send a habit reminder based on pattern and current context
    private func shouldSendHabitReminder(for placeId: UUID, pattern: HabitPattern) async -> Bool {
        let calendar = Calendar.current
        let now = Date()

        // Check if we've already visited today
        if let visits = try? await fetchRecentVisits(placeId: placeId, days: 1) {
            let todayVisits = visits.filter { calendar.isDateInToday($0.entryTime) }
            if !todayVisits.isEmpty {
                return false // Already visited today
            }
        }

        // Check if it's around the usual time (within 30 minutes before usual time)
        let currentHour = calendar.component(.hour, from: now)

        switch pattern.timeOfDay {
        case "Morning":
            return currentHour >= 7 && currentHour < 12
        case "Afternoon":
            return currentHour >= 12 && currentHour < 17
        case "Evening":
            return currentHour >= 17 && currentHour < 21
        case "Night":
            return currentHour >= 21 || currentHour < 5
        default:
            return false
        }
    }

    // MARK: - Data Fetching

    private func fetchRecentVisits(placeId: UUID, days: Int) async throws -> [LocationVisitRecord] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return []
        }

        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let client = await SupabaseManager.shared.getPostgrestClient()
        let response = try await client
            .from("location_visits")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("saved_place_id", value: placeId.uuidString)
            .gte("entry_time", value: ISO8601DateFormatter().string(from: startDate))
            .order("entry_time", ascending: false)
            .execute()

        let decoder = JSONDecoder.supabaseDecoder()
        return try decoder.decode([LocationVisitRecord].self, from: response.data)
    }

    private func getLocationName(for placeId: UUID) -> String? {
        let locationsManager = LocationsManager.shared
        return locationsManager.savedPlaces.first(where: { $0.id == placeId })?.displayName
    }

    // MARK: - Periodic Analysis

    /// Schedule periodic habit analysis (called by app lifecycle)
    func schedulePeriodicAnalysis() {
        // Run analysis once per day
        Task {
            await analyzeHabitPatterns()
        }
    }
}
