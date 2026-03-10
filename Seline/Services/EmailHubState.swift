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
        let currentInputs = inputs
        refreshGeneration += 1
        let generation = refreshGeneration

        DispatchQueue.global(qos: .userInitiated).async {
            let sortedEmails = filtered.sorted { $0.timestamp > $1.timestamp }
            let nextSections = EmailDaySection.categorizeByDay(sortedEmails)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.refreshGeneration == generation, self.inputs == currentInputs else { return }

                if self.filteredEmails != sortedEmails {
                    self.filteredEmails = sortedEmails
                }

                if self.daySections != nextSections {
                    self.daySections = nextSections
                }
            }
        }
    }
}
