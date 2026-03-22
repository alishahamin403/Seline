import Combine
import Foundation

@MainActor
final class EmailHubState: ObservableObject {
    enum ContextFilter: Hashable {
        case inboxToday
        case inboxAction
        case inboxUnread
        case sentToday
        case sentWeek
        case sentWaiting
    }

    struct Inputs: Equatable {
        let selectedTab: EmailTab
        let selectedCategory: EmailCategory?
        let selectedContextFilter: ContextFilter?
    }

    @Published private(set) var filteredEmails: [Email] = []
    @Published private(set) var displayedDaySections: [EmailDaySection] = []
    @Published private(set) var inboxUnreadCount: Int = 0
    @Published private(set) var inboxActionRequiredCount: Int = 0
    @Published private(set) var todayInboxCount: Int = 0
    @Published private(set) var inboxTodaySummary: String = "No new mail has landed today, so this view is mostly for quick checks and cleanup."
    @Published private(set) var sentTodayCount: Int = 0
    @Published private(set) var sentThisWeekCount: Int = 0
    @Published private(set) var sentAwaitingReplyCount: Int = 0

    private let emailService: EmailService
    private var inputs = Inputs(selectedTab: .inbox, selectedCategory: nil, selectedContextFilter: nil)
    private var cancellables = Set<AnyCancellable>()
    private var refreshGeneration = 0

    init(emailService: EmailService? = nil) {
        self.emailService = emailService ?? .shared

        self.emailService.$inboxEmails
            .merge(with: self.emailService.$sentEmails)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func updateInputs(
        selectedTab: EmailTab,
        selectedCategory: EmailCategory?,
        selectedContextFilter: ContextFilter?
    ) {
        let nextInputs = Inputs(
            selectedTab: selectedTab,
            selectedCategory: selectedCategory,
            selectedContextFilter: selectedContextFilter
        )

        guard nextInputs != inputs else { return }
        inputs = nextInputs
        refresh()
    }

    func refresh() {
        let inboxEmails = emailService.getEmails(for: .inbox)
        let sentEmails = emailService.getEmails(for: .sent)
        let currentInputs = inputs
        refreshGeneration += 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            let nextFilteredEmails = Self.filteredEmails(
                for: currentInputs,
                inboxEmails: inboxEmails,
                sentEmails: sentEmails
            )
            let sortedEmails = nextFilteredEmails.sorted { $0.timestamp > $1.timestamp }
            let nextSections = EmailDaySection.categorizeByDay(sortedEmails)

            let nextInboxUnreadCount = inboxEmails.filter { !$0.isRead }.count
            let nextInboxActionRequiredCount = inboxEmails.filter(Self.isActionRequired).count
            let todayInboxEmails = inboxEmails
                .filter { Calendar.current.isDateInToday($0.timestamp) }
                .sorted { $0.timestamp > $1.timestamp }
            let nextTodayInboxCount = todayInboxEmails.count
            let nextInboxSummary = Self.inboxSummary(
                todayInboxEmails: todayInboxEmails,
                actionRequiredCount: nextInboxActionRequiredCount
            )

            let nextSentTodayCount = sentEmails.filter { Calendar.current.isDateInToday($0.timestamp) }.count
            let nextSentThisWeekCount = sentEmails.filter {
                Calendar.current.isDate($0.timestamp, equalTo: Date(), toGranularity: .weekOfYear)
            }.count
            let nextSentAwaitingReplyCount = sentEmails.filter {
                Self.isAwaitingReply($0, inboxEmails: inboxEmails)
            }.count

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.refreshGeneration == generation, self.inputs == currentInputs else { return }

                if self.filteredEmails != sortedEmails {
                    self.filteredEmails = sortedEmails
                }

                if self.displayedDaySections != nextSections {
                    self.displayedDaySections = nextSections
                }

                self.inboxUnreadCount = nextInboxUnreadCount
                self.inboxActionRequiredCount = nextInboxActionRequiredCount
                self.todayInboxCount = nextTodayInboxCount
                self.inboxTodaySummary = nextInboxSummary
                self.sentTodayCount = nextSentTodayCount
                self.sentThisWeekCount = nextSentThisWeekCount
                self.sentAwaitingReplyCount = nextSentAwaitingReplyCount
            }
        }
    }

    private static func filteredEmails(
        for inputs: Inputs,
        inboxEmails: [Email],
        sentEmails: [Email]
    ) -> [Email] {
        guard inputs.selectedTab != .calendar else { return [] }

        let baseEmails: [Email]
        switch inputs.selectedTab {
        case .inbox:
            baseEmails = filteredByCategory(inboxEmails, category: inputs.selectedCategory)
        case .calendar:
            baseEmails = []
        case .sent:
            baseEmails = filteredByCategory(sentEmails, category: inputs.selectedCategory)
        }

        guard let contextFilter = inputs.selectedContextFilter else {
            return baseEmails
        }

        switch contextFilter {
        case .inboxToday:
            return baseEmails.filter { Calendar.current.isDateInToday($0.timestamp) }
        case .inboxAction:
            return baseEmails.filter(isActionRequired)
        case .inboxUnread:
            return baseEmails.filter { !$0.isRead }
        case .sentToday:
            return baseEmails.filter { Calendar.current.isDateInToday($0.timestamp) }
        case .sentWeek:
            return baseEmails.filter { Calendar.current.isDate($0.timestamp, equalTo: Date(), toGranularity: .weekOfYear) }
        case .sentWaiting:
            return baseEmails.filter { isAwaitingReply($0, inboxEmails: inboxEmails) }
        }
    }

    private static func filteredByCategory(_ emails: [Email], category: EmailCategory?) -> [Email] {
        guard let category else { return emails }
        return emails.filter { $0.category == category }
    }

    private static func inboxSummary(todayInboxEmails: [Email], actionRequiredCount: Int) -> String {
        guard !todayInboxEmails.isEmpty else {
            return "No new mail has landed today, so this view is mostly for quick checks and cleanup."
        }

        let dominantCategory = Dictionary(grouping: todayInboxEmails, by: \.category)
            .max { lhs, rhs in lhs.value.count < rhs.value.count }?
            .key
            .displayName
            .lowercased() ?? "mixed"

        var seenSenders = Set<String>()
        var topSenders: [String] = []

        for email in todayInboxEmails {
            let displayName = email.sender.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let senderName = displayName.isEmpty ? email.sender.email : displayName

            guard !senderName.isEmpty else { continue }
            guard seenSenders.insert(senderName).inserted else { continue }

            topSenders.append(senderName)
            if topSenders.count == 2 {
                break
            }
        }

        let senderText: String
        if topSenders.count == 1 {
            senderText = "from \(topSenders[0])"
        } else if topSenders.count == 2 {
            senderText = "from \(topSenders[0]) and \(topSenders[1])"
        } else {
            senderText = ""
        }

        if actionRequiredCount > 0 {
            return "\(todayInboxEmails.count) emails arrived today, mostly \(dominantCategory) mail \(senderText). \(actionRequiredCount) threads still look like they need a reply."
                .replacingOccurrences(of: "  ", with: " ")
        }

        return "\(todayInboxEmails.count) emails arrived today, mostly \(dominantCategory) mail \(senderText)."
            .replacingOccurrences(of: "  ", with: " ")
    }

    private static func isActionRequired(_ email: Email) -> Bool {
        email.requiresAction
    }

    private static func isAwaitingReply(_ email: Email, inboxEmails: [Email]) -> Bool {
        let sentThreadId = email.gmailThreadId ?? email.threadId
        guard let sentThreadId else { return false }

        return !inboxEmails.contains { inboxEmail in
            let inboxThreadId = inboxEmail.gmailThreadId ?? inboxEmail.threadId
            return inboxThreadId == sentThreadId && inboxEmail.timestamp > email.timestamp
        }
    }
}
