import Foundation

/// EmailNotificationIntelligence: Smart filtering and prioritization for email notifications
/// Reduces notification fatigue by intelligently determining which emails deserve immediate attention
@MainActor
class EmailNotificationIntelligence: ObservableObject {
    static let shared = EmailNotificationIntelligence()

    private let deepSeekService = DeepSeekService.shared

    // Thread consolidation tracking
    private var recentThreadActivity: [String: ThreadActivity] = [:] // [threadId: activity]
    private let threadConsolidationWindow: TimeInterval = 600 // 10 minutes

    // Time-sensitive keywords
    private let urgencyKeywords = [
        "urgent", "asap", "immediately", "right away", "time-sensitive",
        "deadline", "due today", "by eod", "by end of day", "expires",
        "urgent:", "urgent -", "urgent!", "[urgent]",
        "important:", "important!", "[important]"
    ]

    private let questionKeywords = [
        "?", "can you", "could you", "would you", "will you",
        "do you", "did you", "have you", "please", "need you",
        "waiting for", "waiting on"
    ]

    private struct ThreadActivity {
        var emailIds: [String]
        var lastActivityTime: Date
        var senders: Set<String>

        mutating func addEmail(id: String, from sender: String) {
            emailIds.append(id)
            senders.insert(sender)
            lastActivityTime = Date()
        }
    }

    private init() {}

    // MARK: - Priority Filtering

    /// Determines if an email should trigger a notification
    /// Returns nil if notification should be suppressed, or NotificationPriority if it should be sent
    func shouldNotify(for email: Email, vipSenders: Set<String> = []) async -> NotificationPriority? {
        // Check VIP senders first
        if vipSenders.contains(email.sender.email.lowercased()) {
            return .high(reason: "VIP sender")
        }

        // Check time-sensitive signals
        if let urgencyLevel = detectTimeSensitivity(email: email) {
            return urgencyLevel
        }

        // Check if it's a question/action required
        if containsQuestion(email: email) {
            return .medium(reason: "Question or action required")
        }

        // Check thread activity for consolidation
        if let threadId = email.threadId ?? email.gmailThreadId {
            if shouldConsolidateThread(threadId: threadId) {
                // Suppress this notification - will be consolidated
                return nil
            }
        }

        // Check if it's part of a long thread (likely not urgent)
        if let threadId = email.threadId ?? email.gmailThreadId {
            // If thread has recent activity, it might be consolidated
            if let activity = recentThreadActivity[threadId], activity.emailIds.count >= 3 {
                return nil // Will be batched
            }
        }

        // Default: Allow notification but with low priority
        return .low(reason: "Regular email")
    }

    // MARK: - Thread Consolidation

    /// Checks if a thread should be consolidated (multiple emails in short time)
    private func shouldConsolidateThread(threadId: String) -> Bool {
        if let activity = recentThreadActivity[threadId] {
            let timeSinceLastEmail = Date().timeIntervalSince(activity.lastActivityTime)

            // If we've seen this thread in the last 10 minutes, consolidate
            if timeSinceLastEmail < threadConsolidationWindow {
                return true
            }
        }

        return false
    }

    /// Records email activity for thread consolidation
    func recordEmailActivity(email: Email) {
        guard let threadId = email.threadId ?? email.gmailThreadId else { return }

        if var activity = recentThreadActivity[threadId] {
            activity.addEmail(id: email.id, from: email.sender.email)
            recentThreadActivity[threadId] = activity
        } else {
            recentThreadActivity[threadId] = ThreadActivity(
                emailIds: [email.id],
                lastActivityTime: Date(),
                senders: [email.sender.email]
            )
        }

        // Clean up old thread activity (older than consolidation window)
        cleanupOldThreadActivity()
    }

    /// Gets consolidated thread notification info
    func getConsolidatedThreadInfo(threadId: String) -> (emailCount: Int, senders: [String])? {
        guard let activity = recentThreadActivity[threadId] else { return nil }

        let timeSinceLastEmail = Date().timeIntervalSince(activity.lastActivityTime)

        // Only return if activity is recent
        if timeSinceLastEmail < threadConsolidationWindow {
            return (activity.emailIds.count, Array(activity.senders))
        }

        return nil
    }

    /// Clears thread activity for a specific thread (after notification is sent)
    func clearThreadActivity(threadId: String) {
        recentThreadActivity.removeValue(forKey: threadId)
    }

    private func cleanupOldThreadActivity() {
        let now = Date()
        recentThreadActivity = recentThreadActivity.filter { (_, activity) in
            now.timeIntervalSince(activity.lastActivityTime) < threadConsolidationWindow
        }
    }

    // MARK: - Time-Sensitive Detection

    /// Detects time-sensitive signals in email
    private func detectTimeSensitivity(email: Email) -> NotificationPriority? {
        let searchText = "\(email.subject) \(email.snippet)".lowercased()

        // Check for urgent keywords
        for keyword in urgencyKeywords {
            if searchText.contains(keyword.lowercased()) {
                return .high(reason: "Time-sensitive: '\(keyword)'")
            }
        }

        // Check for deadlines with dates
        if let deadline = extractDeadline(from: searchText) {
            // If deadline is within 24 hours, high priority
            if deadline.timeIntervalSinceNow < 86400 && deadline.timeIntervalSinceNow > 0 {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return .high(reason: "Deadline: \(formatter.string(from: deadline))")
            } else if deadline.timeIntervalSinceNow < 172800 && deadline.timeIntervalSinceNow > 0 {
                // Within 48 hours, medium priority
                return .medium(reason: "Upcoming deadline")
            }
        }

        // Check for meeting invites within 2 hours
        if searchText.contains("meeting") || searchText.contains("call") || searchText.contains("zoom") {
            if let meetingTime = extractMeetingTime(from: searchText) {
                if meetingTime.timeIntervalSinceNow < 7200 && meetingTime.timeIntervalSinceNow > 0 {
                    return .high(reason: "Meeting soon")
                }
            }
        }

        return nil
    }

    private func containsQuestion(email: Email) -> Bool {
        let searchText = "\(email.subject) \(email.snippet)".lowercased()

        // Check for question mark
        if searchText.contains("?") {
            return true
        }

        // Check for question keywords
        for keyword in questionKeywords {
            if searchText.contains(keyword.lowercased()) {
                return true
            }
        }

        return false
    }

    private func extractDeadline(from text: String) -> Date? {
        // Look for patterns like "by EOD", "by 5pm", "due today", "deadline: MM/DD"
        // This is a simplified version - could be enhanced with NLP

        let eodKeywords = ["by eod", "by end of day", "due today"]
        for keyword in eodKeywords {
            if text.contains(keyword) {
                // Return 5 PM today
                let calendar = Calendar.current
                var components = calendar.dateComponents([.year, .month, .day], from: Date())
                components.hour = 17
                components.minute = 0
                return calendar.date(from: components)
            }
        }

        // Could add more sophisticated date parsing here
        return nil
    }

    private func extractMeetingTime(from text: String) -> Date? {
        // Look for time patterns - simplified version
        // Could be enhanced with more sophisticated parsing
        return nil
    }

    // MARK: - AI-Powered Analysis

    /// Uses AI to analyze email importance (optional enhancement)
    func analyzeEmailImportance(email: Email) async throws -> NotificationPriority {
        let prompt = """
        Analyze this email and determine if it requires immediate attention.

        From: \(email.sender.displayName)
        Subject: \(email.subject)
        Preview: \(email.snippet)

        Respond with ONE of:
        - HIGH: Urgent, time-sensitive, or from important person
        - MEDIUM: Question, action required, or moderately important
        - LOW: FYI, newsletter, or can wait

        Also provide a brief reason (10 words max).
        Format: PRIORITY|reason
        """

        let response = try await deepSeekService.answerQuestion(query: prompt)
        let parts = response.components(separatedBy: "|")

        guard parts.count == 2 else {
            return .low(reason: "Could not analyze")
        }

        let priority = parts[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).uppercased()
        let reason = parts[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        switch priority {
        case "HIGH":
            return .high(reason: reason)
        case "MEDIUM":
            return .medium(reason: reason)
        default:
            return .low(reason: reason)
        }
    }
}

// MARK: - Supporting Types

enum NotificationPriority {
    case high(reason: String)
    case medium(reason: String)
    case low(reason: String)

    var shouldNotify: Bool {
        switch self {
        case .high, .medium, .low:
            // ALL emails should notify by default
            // Users can choose to suppress specific categories in settings
            return true
        }
    }

    var displayReason: String {
        switch self {
        case .high(let reason), .medium(let reason), .low(let reason):
            return reason
        }
    }
}
