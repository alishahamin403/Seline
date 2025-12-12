import Foundation
import EventKit

/// DailyBriefingService: Generates and schedules daily morning briefing notifications
/// Aggregates information from emails, calendar, expenses, and weather
@MainActor
class DailyBriefingService: ObservableObject {
    static let shared = DailyBriefingService()

    private let notificationService = NotificationService.shared
    private let emailService = EmailService.shared
    private let calendarService = CalendarSyncService.shared

    // User preferences
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "dailyBriefingEnabled")
            if isEnabled {
                Task {
                    await scheduleDailyBriefing()
                }
            } else {
                cancelDailyBriefing()
            }
        }
    }

    @Published var briefingHour: Int {
        didSet {
            UserDefaults.standard.set(briefingHour, forKey: "dailyBriefingHour")
            if isEnabled {
                Task {
                    await scheduleDailyBriefing()
                }
            }
        }
    }

    @Published var briefingMinute: Int {
        didSet {
            UserDefaults.standard.set(briefingMinute, forKey: "dailyBriefingMinute")
            if isEnabled {
                Task {
                    await scheduleDailyBriefing()
                }
            }
        }
    }

    private init() {
        // Load preferences
        self.isEnabled = UserDefaults.standard.bool(forKey: "dailyBriefingEnabled")
        self.briefingHour = UserDefaults.standard.integer(forKey: "dailyBriefingHour")
        self.briefingMinute = UserDefaults.standard.integer(forKey: "dailyBriefingMinute")

        // Default: 7:00 AM if not set
        if briefingHour == 0 && briefingMinute == 0 {
            briefingHour = 7
        }
    }

    // MARK: - Schedule Daily Briefing

    /// Schedule recurring daily briefing at configured time
    func scheduleDailyBriefing() async {
        guard isEnabled else { return }

        // Schedule the recurring notification
        await notificationService.scheduleDailyBriefingAt(hour: briefingHour, minute: briefingMinute)
        print("🌅 Daily briefing scheduled for \(briefingHour):\(String(format: "%02d", briefingMinute))")
    }

    /// Generate and send immediate daily briefing
    func sendBriefingNow() async {
        let briefingData = await generateBriefingData()

        await notificationService.scheduleDailyBriefing(
            emailCount: briefingData.unreadEmailCount,
            eventsToday: briefingData.eventsCount,
            upcomingExpenses: briefingData.upcomingExpenses,
            weather: briefingData.weatherSummary
        )
    }

    func cancelDailyBriefing() {
        notificationService.cancelNotifications(ofType: "daily_briefing_scheduled")
        print("🛑 Daily briefing cancelled")
    }

    // MARK: - Briefing Data Generation

    private struct BriefingData {
        let unreadEmailCount: Int
        let eventsCount: Int
        let upcomingExpenses: [(String, Double)]
        let weatherSummary: String?
    }

    private func generateBriefingData() async -> BriefingData {
        // Get unread email count
        let unreadEmails = emailService.inboxEmails.filter { !$0.isRead }.count

        // Get today's events
        let allEvents = await calendarService.fetchCalendarEventsFromCurrentMonthOnwards()
        let calendar = Calendar.current
        let eventsToday = allEvents.filter { event in
            calendar.isDateInToday(event.startDate)
        }.count

        // Get upcoming expenses (next 7 days)
        let upcomingExpenses = await fetchUpcomingExpenses()

        // Get weather summary
        let weatherSummary = await fetchWeatherSummary()

        return BriefingData(
            unreadEmailCount: unreadEmails,
            eventsCount: eventsToday,
            upcomingExpenses: upcomingExpenses,
            weatherSummary: weatherSummary
        )
    }

    private func fetchUpcomingExpenses() async -> [(String, Double)] {
        // Fetch recurring expenses due in the next 7 days
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return []
        }

        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let nextWeek = calendar.date(byAdding: .day, value: 7, to: today) ?? today

            // This is a simplified query - adjust based on your actual database schema
            let response = try await client
                .from("recurring_expenses")
                .select()
                .eq("user_id", value: userId.uuidString)
                .gte("next_due_date", value: ISO8601DateFormatter().string(from: today))
                .lte("next_due_date", value: ISO8601DateFormatter().string(from: nextWeek))
                .execute()

            struct RecurringExpense: Decodable {
                let name: String
                let amount: Double
            }

            let decoder = JSONDecoder()
            let expenses = try decoder.decode([RecurringExpense].self, from: response.data)

            return expenses.map { ($0.name, $0.amount) }
        } catch {
            print("⚠️ Error fetching upcoming expenses: \(error)")
            return []
        }
    }

    private func fetchWeatherSummary() async -> String? {
        // TODO: Integrate with WeatherService if available
        // For now, return nil
        return nil
    }

    // MARK: - Utility Methods

    /// Format briefing time as string
    func getBriefingTimeString() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        var components = DateComponents()
        components.hour = briefingHour
        components.minute = briefingMinute
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(briefingHour):\(String(format: "%02d", briefingMinute))"
    }
}
