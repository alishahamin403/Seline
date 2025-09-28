import Foundation

enum TimePeriod: String, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case night = "Night"

    var timeRange: String {
        switch self {
        case .morning: return "6:00 AM - 11:59 AM"
        case .afternoon: return "12:00 PM - 4:59 PM"
        case .night: return "5:00 PM - 5:59 AM"
        }
    }

    var icon: String {
        switch self {
        case .morning: return "sunrise"
        case .afternoon: return "sun.max"
        case .night: return "moon"
        }
    }

    static func from(date: Date) -> TimePeriod {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)

        switch hour {
        case 6..<12:  // 6:00 AM - 11:59 AM
            return .morning
        case 12..<17: // 12:00 PM - 4:59 PM
            return .afternoon
        default:      // 5:00 PM - 5:59 AM (next day)
            return .night
        }
    }

    static func categorizeEmails(_ emails: [Email], for targetDate: Date = Date()) -> [TimePeriod: [Email]] {
        let calendar = Calendar.current
        var categorized: [TimePeriod: [Email]] = [
            .morning: [],
            .afternoon: [],
            .night: []
        ]

        for email in emails {
            let emailDate = email.timestamp
            let emailHour = calendar.component(.hour, from: emailDate)

            // Check if email belongs to the target date's categories
            let isTargetDate = calendar.isDate(emailDate, inSameDayAs: targetDate)
            let isPreviousDay = calendar.isDate(emailDate, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: targetDate) ?? targetDate)

            switch emailHour {
            case 6..<12:  // Morning: 6:00 AM - 11:59 AM (same day only)
                if isTargetDate {
                    categorized[.morning]?.append(email)
                }
            case 12..<17: // Afternoon: 12:00 PM - 4:59 PM (same day only)
                if isTargetDate {
                    categorized[.afternoon]?.append(email)
                }
            default:      // Night: 5:00 PM - 5:59 AM (spans 2 days)
                // Include night emails from target date (5 PM - 11:59 PM)
                // AND early morning emails from target date (12:00 AM - 5:59 AM)
                if isTargetDate || (isPreviousDay && emailHour >= 17) {
                    categorized[.night]?.append(email)
                }
            }
        }

        // Sort emails within each category by timestamp (newest first)
        for period in TimePeriod.allCases {
            categorized[period]?.sort { $0.timestamp > $1.timestamp }
        }

        return categorized
    }
}

struct EmailAttachment: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let size: Int64
    let mimeType: String
    let url: String?

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    var fileExtension: String {
        return (name as NSString).pathExtension.lowercased()
    }

    var isImage: Bool {
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
        return imageExtensions.contains(fileExtension)
    }

    var isPDF: Bool {
        return fileExtension == "pdf"
    }

    var systemIcon: String {
        if isImage {
            return "photo"
        } else if isPDF {
            return "doc.text"
        } else if fileExtension == "zip" || fileExtension == "rar" {
            return "archivebox"
        } else {
            return "doc"
        }
    }
}

struct Email: Identifiable, Codable, Equatable {
    let id: String
    let threadId: String
    let sender: EmailAddress
    let recipients: [EmailAddress]
    let ccRecipients: [EmailAddress]
    let subject: String
    let snippet: String
    let body: String?
    let timestamp: Date
    let isRead: Bool
    let isImportant: Bool
    let hasAttachments: Bool
    let attachments: [EmailAttachment]
    let labels: [String]
    let aiSummary: String?
    let gmailMessageId: String?
    let gmailThreadId: String?

    var formattedTime: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(timestamp) {
            formatter.timeStyle = .short
            return formatter.string(from: timestamp)
        } else if calendar.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .short
            return formatter.string(from: timestamp)
        }
    }

    var previewText: String {
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var timePeriod: TimePeriod {
        return TimePeriod.from(date: timestamp)
    }
}

struct EmailAddress: Codable, Hashable {
    let name: String?
    let email: String

    var displayName: String {
        return name ?? email
    }

    var shortDisplayName: String {
        if let name = name, !name.isEmpty {
            return name
        }

        let parts = email.components(separatedBy: "@")
        return parts.first ?? email
    }
}

enum EmailFolder: String, CaseIterable {
    case inbox = "INBOX"
    case sent = "SENT"
    case drafts = "DRAFT"
    case trash = "TRASH"
    case spam = "SPAM"

    var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .trash: return "Trash"
        case .spam: return "Spam"
        }
    }

    var systemIcon: String {
        switch self {
        case .inbox: return "tray"
        case .sent: return "paperplane"
        case .drafts: return "doc.text"
        case .trash: return "trash"
        case .spam: return "exclamationmark.shield"
        }
    }
}

enum EmailLoadingState: Equatable {
    case idle
    case loading
    case loaded([Email])
    case error(String)

    static func == (lhs: EmailLoadingState, rhs: EmailLoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading):
            return true
        case let (.loaded(lhsEmails), .loaded(rhsEmails)):
            return lhsEmails.count == rhsEmails.count && lhsEmails.map(\.id) == rhsEmails.map(\.id)
        case let (.error(lhsMessage), .error(rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

struct EmailSearchQuery {
    let text: String
    let folder: EmailFolder?
    let isRead: Bool?
    let hasAttachments: Bool?
    let dateRange: DateInterval?

    init(text: String = "", folder: EmailFolder? = nil, isRead: Bool? = nil, hasAttachments: Bool? = nil, dateRange: DateInterval? = nil) {
        self.text = text
        self.folder = folder
        self.isRead = isRead
        self.hasAttachments = hasAttachments
        self.dateRange = dateRange
    }
}

struct EmailSection: Identifiable {
    let id = UUID()
    let timePeriod: TimePeriod
    let emails: [Email]
    var isExpanded: Bool = true

    var title: String {
        timePeriod.rawValue
    }

    var subtitle: String {
        timePeriod.timeRange
    }

    var emailCount: Int {
        emails.count
    }

    var isEmpty: Bool {
        emails.isEmpty
    }
}

extension Email {
    static var sampleEmails: [Email] {
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today

        return [
            Email(
                id: "1",
                threadId: "thread1",
                sender: EmailAddress(name: "John Doe", email: "john@example.com"),
                recipients: [EmailAddress(name: "Me", email: "me@example.com")],
                ccRecipients: [EmailAddress(name: "Sarah Wilson", email: "sarah@company.com")],
                subject: "Project Update - Q4 Review",
                snippet: "Hi there! I wanted to give you a quick update on our Q4 project status. Everything is looking good and we're on track...",
                body: """
                Hi there!

                I wanted to give you a quick update on our Q4 project status. Everything is looking good and we're on track to meet our December deadline.

                Key highlights:
                • All major milestones completed on schedule
                • Team performance has been exceptional
                • Budget tracking shows we're within 5% of target
                • Client feedback has been overwhelmingly positive

                Next steps:
                1. Finalize the presentation materials
                2. Schedule the client review meeting
                3. Prepare for the final implementation phase

                Please let me know if you have any questions or concerns.

                Best regards,
                John
                """,
                timestamp: today,
                isRead: false,
                isImportant: true,
                hasAttachments: true,
                attachments: [
                    EmailAttachment(
                        id: "att1",
                        name: "Q4_Report.pdf",
                        size: 2048576,
                        mimeType: "application/pdf",
                        url: nil
                    ),
                    EmailAttachment(
                        id: "att2",
                        name: "Project_Timeline.xlsx",
                        size: 512000,
                        mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                        url: nil
                    )
                ],
                labels: ["Important"],
                aiSummary: "Q4 marketing campaign exceeded targets by 23%, generating $2.4M in revenue. Social media engagement increased 45% with video content performing best. Budget allocation for Q1 needs approval by December 15th. Team recommends doubling investment in video marketing for next quarter.",
                gmailMessageId: "1784d63938119544",
                gmailThreadId: "1784d63938119544"
            ),
            Email(
                id: "2",
                threadId: "thread2",
                sender: EmailAddress(name: "Sarah Wilson", email: "sarah@company.com"),
                recipients: [EmailAddress(name: "Me", email: "me@example.com")],
                ccRecipients: [],
                subject: "Meeting Reminder: Design Review",
                snippet: "Just a friendly reminder about our design review meeting scheduled for tomorrow at 2 PM. Please make sure to...",
                body: "Just a friendly reminder about our design review meeting scheduled for tomorrow at 2 PM. Please make sure to bring your latest wireframes and prototypes. We'll be reviewing the user interface designs and discussing the feedback from the stakeholder meeting.",
                timestamp: Calendar.current.date(byAdding: .hour, value: -2, to: today) ?? today,
                isRead: true,
                isImportant: false,
                hasAttachments: false,
                attachments: [],
                labels: ["Work"],
                aiSummary: nil,
                gmailMessageId: "1784d63938119545",
                gmailThreadId: "1784d63938119545"
            ),
            Email(
                id: "3",
                threadId: "thread3",
                sender: EmailAddress(name: "GitHub", email: "noreply@github.com"),
                recipients: [EmailAddress(name: "Me", email: "me@example.com")],
                ccRecipients: [],
                subject: "[GitHub] New pull request opened",
                snippet: "A new pull request has been opened in your repository. The changes include updates to the authentication system...",
                body: "A new pull request has been opened in your repository. The changes include updates to the authentication system and improved error handling. Please review the changes and provide feedback.",
                timestamp: Calendar.current.date(byAdding: .hour, value: -4, to: today) ?? today,
                isRead: true,
                isImportant: false,
                hasAttachments: false,
                attachments: [],
                labels: ["GitHub", "Notifications"],
                aiSummary: nil,
                gmailMessageId: "1784d63938119546",
                gmailThreadId: "1784d63938119546"
            ),
            Email(
                id: "4",
                threadId: "thread4",
                sender: EmailAddress(name: "Team Lead", email: "lead@company.com"),
                recipients: [EmailAddress(name: "Me", email: "me@example.com")],
                ccRecipients: [],
                subject: "Standup Notes - Daily Sync",
                snippet: "Here are today's standup notes and action items. Please review and let me know if I missed anything...",
                body: "Here are today's standup notes and action items. Please review and let me know if I missed anything. The team made good progress on the sprint goals and we're on track for the release.",
                timestamp: yesterday,
                isRead: false,
                isImportant: false,
                hasAttachments: true,
                attachments: [
                    EmailAttachment(
                        id: "att3",
                        name: "standup_notes.docx",
                        size: 256000,
                        mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                        url: nil
                    )
                ],
                labels: ["Work", "Daily"],
                aiSummary: nil,
                gmailMessageId: "1784d63938119547",
                gmailThreadId: "1784d63938119547"
            )
        ]
    }
}

enum EmailCategory: String, CaseIterable, Identifiable {
    case promotional = "promotional"
    case updates = "updates"
    case social = "social"
    case work = "work"
    case personal = "personal"
    case automated = "automated"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .promotional: return "Promotional"
        case .updates: return "Updates"
        case .social: return "Social"
        case .work: return "Work"
        case .personal: return "Personal"
        case .automated: return "Automated"
        }
    }

    var description: String {
        switch self {
        case .promotional: return "Marketing, sales, newsletters, offers"
        case .updates: return "Notifications, digests, system updates"
        case .social: return "Social media, community notifications"
        case .work: return "Work-related communications"
        case .personal: return "Personal communications"
        case .automated: return "No-reply, system-generated emails"
        }
    }

    var icon: String {
        switch self {
        case .promotional: return "megaphone"
        case .updates: return "bell"
        case .social: return "person.2"
        case .work: return "briefcase"
        case .personal: return "heart"
        case .automated: return "gearshape"
        }
    }
}

struct EmailFilterPreferences: Codable {
    private var enabledCategoryStrings: Set<String>

    var enabledCategories: Set<EmailCategory> {
        get {
            Set(enabledCategoryStrings.compactMap { EmailCategory(rawValue: $0) })
        }
        set {
            enabledCategoryStrings = Set(newValue.map { $0.rawValue })
        }
    }

    static let `default` = EmailFilterPreferences(
        enabledCategories: Set(EmailCategory.allCases.filter { $0 != .promotional && $0 != .automated })
    )

    init(enabledCategories: Set<EmailCategory> = Set(EmailCategory.allCases)) {
        self.enabledCategoryStrings = Set(enabledCategories.map { $0.rawValue })
    }

    func isCategoryEnabled(_ category: EmailCategory) -> Bool {
        return enabledCategories.contains(category)
    }

    mutating func toggleCategory(_ category: EmailCategory) {
        var categories = enabledCategories
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
        enabledCategories = categories
    }
}