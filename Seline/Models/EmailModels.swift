import Foundation

enum TimePeriod: String, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case night = "Night"

    var timeRange: String {
        switch self {
        case .morning: return "12:00 AM - 11:59 AM"
        case .afternoon: return "12:00 PM - 4:59 PM"
        case .night: return "5:00 PM - 11:59 PM"
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
        case 0..<12:  // 12:00 AM - 11:59 AM
            return .morning
        case 12..<17: // 12:00 PM - 4:59 PM
            return .afternoon
        case 17..<24: // 5:00 PM - 11:59 PM
            return .night
        default:
            return .night // Fallback (shouldn't happen)
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
            let _ = calendar.isDate(emailDate, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: targetDate) ?? targetDate)

            switch emailHour {
            case 0..<12:  // Morning: 12:00 AM - 11:59 AM (same day only)
                if isTargetDate {
                    categorized[.morning]?.append(email)
                }
            case 12..<17: // Afternoon: 12:00 PM - 4:59 PM (same day only)
                if isTargetDate {
                    categorized[.afternoon]?.append(email)
                }
            case 17..<24: // Night: 5:00 PM - 11:59 PM (same day only)
                if isTargetDate {
                    categorized[.night]?.append(email)
                }
            default:
                break // Shouldn't happen with 24-hour format
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
    let avatarUrl: String?

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

    var initials: String {
        if let name = name, !name.isEmpty {
            let components = name.components(separatedBy: " ")
            if components.count >= 2 {
                let firstInitial = components[0].prefix(1).uppercased()
                let lastInitial = components[1].prefix(1).uppercased()
                return "\(firstInitial)\(lastInitial)"
            } else if let first = components.first {
                return first.prefix(1).uppercased()
            }
        }

        // Fallback to first letter of email
        return email.prefix(1).uppercased()
    }
}

// MARK: - Custom Email Folder Models

/// Represents a custom email folder created by the user
struct CustomEmailFolder: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let name: String
    let color: String // Hex color code (e.g., "#84cae9")
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case color
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayColor: Color {
        Color(hex: color) ?? Color.blue
    }
}

/// Represents an email saved in a custom folder with full content
struct SavedEmail: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let emailFolderId: UUID
    let gmailMessageId: String // Reference to original Gmail message
    let subject: String
    let senderName: String?
    let senderEmail: String
    let recipients: [String] // Array of recipient emails
    let ccRecipients: [String] // Array of CC recipient emails
    let body: String? // Full HTML body
    let snippet: String?
    let timestamp: Date // Original email date
    let savedAt: Date
    let updatedAt: Date
    var attachments: [SavedEmailAttachment] = []

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case emailFolderId = "email_folder_id"
        case gmailMessageId = "gmail_message_id"
        case subject
        case senderName = "sender_name"
        case senderEmail = "sender_email"
        case recipients
        case ccRecipients = "cc_recipients"
        case body
        case snippet
        case timestamp
        case savedAt = "saved_at"
        case updatedAt = "updated_at"
    }

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
        return (snippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Represents an attachment for a saved email
struct SavedEmailAttachment: Identifiable, Codable, Equatable {
    let id: UUID
    let savedEmailId: UUID
    let fileName: String
    let fileSize: Int64
    let mimeType: String?
    let storagePath: String // Path in Supabase Storage
    let uploadedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case savedEmailId = "saved_email_id"
        case fileName = "file_name"
        case fileSize = "file_size"
        case mimeType = "mime_type"
        case storagePath = "storage_path"
        case uploadedAt = "uploaded_at"
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }

    var fileExtension: String {
        return (fileName as NSString).pathExtension.lowercased()
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
                sender: EmailAddress(name: "John Doe", email: "john@example.com", avatarUrl: nil),
                recipients: [EmailAddress(name: "Me", email: "me@example.com", avatarUrl: nil)],
                ccRecipients: [EmailAddress(name: "Sarah Wilson", email: "sarah@company.com", avatarUrl: nil)],
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
                sender: EmailAddress(name: "Sarah Wilson", email: "sarah@company.com", avatarUrl: nil),
                recipients: [EmailAddress(name: "Me", email: "me@example.com", avatarUrl: nil)],
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
                sender: EmailAddress(name: "GitHub", email: "noreply@github.com", avatarUrl: nil),
                recipients: [EmailAddress(name: "Me", email: "me@example.com", avatarUrl: nil)],
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
                sender: EmailAddress(name: "Team Lead", email: "lead@company.com", avatarUrl: nil),
                recipients: [EmailAddress(name: "Me", email: "me@example.com", avatarUrl: nil)],
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

// MARK: - Email Category System

enum EmailCategory: String, CaseIterable, Identifiable {
    case primary = "Primary"
    case social = "Social"
    case promotions = "Promotions"
    case updates = "Updates"
    case forums = "Forums"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .primary: return "envelope.fill"
        case .social: return "person.2.fill"
        case .promotions: return "megaphone.fill"
        case .updates: return "bell.fill"
        case .forums: return "bubble.left.and.bubble.right.fill"
        }
    }

    var displayName: String {
        return rawValue
    }

    var gmailLabel: String {
        switch self {
        case .primary: return "CATEGORY_PRIMARY"
        case .social: return "CATEGORY_SOCIAL"
        case .promotions: return "CATEGORY_PROMOTIONS"
        case .updates: return "CATEGORY_UPDATES"
        case .forums: return "CATEGORY_FORUMS"
        }
    }
}

// MARK: - Email Categorization Extension

extension Email {
    var category: EmailCategory {
        // Check Gmail native labels first (most reliable)
        if labels.contains("CATEGORY_SOCIAL") {
            return .social
        }

        if labels.contains("CATEGORY_PROMOTIONS") {
            return .promotions
        }

        if labels.contains("CATEGORY_UPDATES") {
            return .updates
        }

        if labels.contains("CATEGORY_FORUMS") {
            return .forums
        }

        if labels.contains("CATEGORY_PRIMARY") {
            return .primary
        }

        // Fallback: Use heuristics if Gmail labels are not present

        // Check for social media emails
        if isSocialEmail {
            return .social
        }

        // Check for promotional emails
        if isPromotionalEmail {
            return .promotions
        }

        // Check for update/notification emails
        if isUpdateEmail {
            return .updates
        }

        // Check for forum/mailing list emails
        if isForumEmail {
            return .forums
        }

        // Default to primary for everything else (personal/important emails)
        return .primary
    }

    private var isSocialEmail: Bool {
        let senderEmail = sender.email.lowercased()
        let senderName = sender.name?.lowercased() ?? ""

        let socialPlatforms = [
            "facebook", "instagram", "twitter", "linkedin", "tiktok", "snapchat",
            "pinterest", "reddit", "tumblr", "youtube", "whatsapp", "telegram",
            "discord", "slack", "signal"
        ]

        return socialPlatforms.contains { platform in
            senderEmail.contains(platform) || senderName.contains(platform)
        }
    }

    private var isPromotionalEmail: Bool {
        let subject = subject.lowercased()
        let senderEmail = sender.email.lowercased()
        let senderName = sender.name?.lowercased() ?? ""
        let snippet = snippet.lowercased()

        let promotionalKeywords = [
            "unsubscribe", "promotion", "promo", "sale", "discount", "offer", "deal",
            "marketing", "advertisement", "special offer", "limited time", "newsletter",
            "shop now", "buy now", "% off", "free shipping", "coupon", "voucher"
        ]

        let promotionalSenders = [
            "marketing", "promo", "newsletter", "offers", "deals", "sales"
        ]

        let hasPromotionalKeywords = promotionalKeywords.contains { keyword in
            subject.contains(keyword) || snippet.contains(keyword)
        }

        let hasPromotionalSender = promotionalSenders.contains { indicator in
            senderEmail.contains(indicator) || senderName.contains(indicator)
        }

        return hasPromotionalKeywords || hasPromotionalSender
    }

    private var isUpdateEmail: Bool {
        let subject = subject.lowercased()
        let senderEmail = sender.email.lowercased()
        let snippet = snippet.lowercased()

        let updateKeywords = [
            "update", "notification", "digest", "summary", "weekly", "daily", "monthly",
            "reminder", "alert", "notice", "report", "activity", "confirmation",
            "receipt", "invoice", "order", "shipment", "delivery", "tracking"
        ]

        let updateSenders = [
            "notification", "updates", "alerts", "noreply", "no-reply", "donotreply",
            "automated", "system"
        ]

        let hasUpdateKeywords = updateKeywords.contains { keyword in
            subject.contains(keyword) || snippet.contains(keyword)
        }

        let hasUpdateSender = updateSenders.contains { indicator in
            senderEmail.contains(indicator)
        }

        return hasUpdateKeywords || hasUpdateSender
    }

    private var isForumEmail: Bool {
        let subject = subject.lowercased()
        let senderEmail = sender.email.lowercased()

        let forumKeywords = [
            "mailing list", "discussion", "forum", "group", "community",
            "thread", "reply to:", "re:", "fwd:"
        ]

        let forumDomains = [
            "googlegroups", "groups.io", "listserv", "mailman"
        ]

        let hasForumKeywords = forumKeywords.contains { keyword in
            subject.contains(keyword)
        }

        let hasForumDomain = forumDomains.contains { domain in
            senderEmail.contains(domain)
        }

        return hasForumKeywords || hasForumDomain
    }
}

