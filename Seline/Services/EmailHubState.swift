import Combine
import Foundation

@MainActor
final class EmailHubState: ObservableObject {
    struct Inputs: Equatable {
        let selectedTab: EmailTab
        let selectedCategory: EmailCategory?
        let showUnreadOnly: Bool
    }

    @Published private(set) var filteredEmails: [Email] = []
    @Published private(set) var daySections: [EmailDaySection] = []

    private let emailService: EmailService
    private var inputs = Inputs(selectedTab: .inbox, selectedCategory: nil, showUnreadOnly: false)
    private var cancellables = Set<AnyCancellable>()

    init(emailService: EmailService = .shared) {
        self.emailService = emailService

        emailService.$inboxEmails
            .merge(with: emailService.$sentEmails)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func updateInputs(
        selectedTab: EmailTab,
        selectedCategory: EmailCategory?,
        showUnreadOnly: Bool
    ) {
        let nextInputs = Inputs(
            selectedTab: selectedTab,
            selectedCategory: selectedCategory,
            showUnreadOnly: showUnreadOnly
        )

        guard nextInputs != inputs else { return }
        inputs = nextInputs
        refresh()
    }

    func refresh() {
        guard inputs.selectedTab != .events else {
            filteredEmails = []
            daySections = []
            return
        }

        let folder = inputs.selectedTab.folder
        let emails: [Email]

        if let selectedCategory = inputs.selectedCategory {
            emails = emailService.getFilteredEmails(for: folder, category: selectedCategory)
        } else {
            emails = emailService.getEmails(for: folder)
        }

        let filtered = inputs.showUnreadOnly
            ? emails.filter { !$0.isRead }
            : emails

        filteredEmails = filtered.sorted { $0.timestamp > $1.timestamp }
        daySections = EmailDaySection.categorizeByDay(filteredEmails)
    }
}
