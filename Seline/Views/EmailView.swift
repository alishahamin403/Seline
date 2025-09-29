import SwiftUI

struct EmailView: View, Searchable {
    @StateObject private var emailService = EmailService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: EmailTab = .inbox
    @State private var selectedCategory: EmailCategory? = nil // nil means show all emails
    @State private var lastRefreshTime: Date? = nil

    var currentEmails: [Email] {
        return emailService.getEmails(for: selectedTab.folder)
    }

    var currentLoadingState: EmailLoadingState {
        return emailService.getLoadingState(for: selectedTab.folder)
    }

    var currentSections: [EmailSection] {
        if let selectedCategory = selectedCategory {
            return emailService.getCategorizedEmails(for: selectedTab.folder, category: selectedCategory)
        } else {
            // Show all emails when no category is selected
            return emailService.getCategorizedEmails(for: selectedTab.folder)
        }
    }


    var body: some View {
        GeometryReader { geometry in
            let topPadding = CGFloat(8)

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    // Tab selector - always visible now
                    EmailTabView(selectedTab: $selectedTab)
                        .onChange(of: selectedTab) { newTab in
                            // Load emails for the selected folder - cache will be respected
                            // This will show cached content immediately if available
                            Task {
                                await emailService.loadEmailsForFolder(newTab.folder)
                            }
                        }

                    // Category filter buttons
                    EmailCategoryFilterView(selectedCategory: $selectedCategory)
                        .onChange(of: selectedCategory) { _ in
                            // Category change doesn't require reloading data, just filtering
                            // The currentSections computed property will handle the filtering
                        }
                }
                .padding(.horizontal, 20)
                .padding(.top, topPadding)
                .padding(.bottom, 12)

                // Email list - only categorized view, no search results
                EmailListWithCategories(
                    sections: currentSections,
                    loadingState: currentLoadingState,
                    onRefresh: {
                        await refreshCurrentFolder()
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                    .ignoresSafeArea()
            )
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .overlay(
            // Floating compose button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        openGmailCompose()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(
                                        colorScheme == .dark ?
                                            Color(red: 0.518, green: 0.792, blue: 0.914) :
                                            Color(red: 0.20, green: 0.34, blue: 0.40)
                                    )
                            )
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 60) // Move lower, closer to maps icon
                }
            }
            )
        }
        .onAppear {
            // Register with search service first
            SearchService.shared.registerSearchableProvider(self, for: .email)

            // Clear any email notifications when user opens email view
            Task {
                await emailService.notificationService.clearEmailNotifications()

                // Load emails for current tab - will show cached content immediately
                await emailService.loadEmailsForFolder(selectedTab.folder)

                // Update app badge to reflect current unread count
                let unreadCount = emailService.inboxEmails.filter { !$0.isRead }.count
                await emailService.notificationService.updateAppBadge(count: unreadCount)
            }
        }
    }

    private func refreshCurrentFolder() async {
        lastRefreshTime = Date()
        await emailService.loadEmailsForFolder(selectedTab.folder, forceRefresh: true)
    }

    private func openGmailCompose() {
        // Try Gmail compose URL schemes in order of reliability
        let composeURLs = [
            "googlegmail://co",           // Direct compose
            "googlegmail:///co",          // Alternative compose
            "googlegmail://compose",      // Another compose variant
            "googlegmail://"              // Fallback to general Gmail
        ]

        for urlString in composeURLs {
            if let url = URL(string: urlString) {
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url) { success in
                        if success {
                            print("✅ Successfully opened Gmail with: \(urlString)")
                            return
                        }
                    }
                    return
                }
            }
        }

        // If none worked, Gmail app might not be installed
        print("Gmail app is not installed or none of the URL schemes worked")
    }

    // MARK: - Searchable Protocol

    func getSearchableContent() -> [SearchableItem] {
        var items: [SearchableItem] = []

        // Add main email functionality
        items.append(SearchableItem(
            title: "Email",
            content: "Manage your emails, inbox, drafts, and sent messages. Stay organized with smart categorization and search.",
            type: .email,
            identifier: "email-main",
            metadata: ["category": "communication"]
        ))

        // Add time period content
        items.append(SearchableItem(
            title: "Morning Emails",
            content: "View emails from morning hours (6:00 AM - 11:59 AM). Stay on top of morning communications and start your day organized.",
            type: .email,
            identifier: "email-morning",
            metadata: ["timePeriod": "morning", "priority": "high"]
        ))

        items.append(SearchableItem(
            title: "Afternoon Emails",
            content: "View emails from afternoon hours (12:00 PM - 4:59 PM). Manage your midday communications and follow up on important messages.",
            type: .email,
            identifier: "email-afternoon",
            metadata: ["timePeriod": "afternoon", "priority": "medium"]
        ))

        items.append(SearchableItem(
            title: "Night Emails",
            content: "View emails from evening and night hours (5:00 PM - 5:59 AM). Catch up on end-of-day communications.",
            type: .email,
            identifier: "email-night",
            metadata: ["timePeriod": "night", "priority": "low"]
        ))

        // Add search functionality
        items.append(SearchableItem(
            title: "Search Emails",
            content: "Search through your emails to find specific messages, senders, or content. Quick and powerful email search.",
            type: .email,
            identifier: "email-search",
            metadata: ["feature": "search", "scope": "emails"]
        ))

        // Add dynamic content from actual emails
        for email in emailService.inboxEmails + emailService.sentEmails {
            items.append(SearchableItem(
                title: email.subject,
                content: "\(email.sender.displayName): \(email.snippet)",
                type: .email,
                identifier: "email-\(email.id)",
                metadata: [
                    "sender": email.sender.email,
                    "timestamp": email.formattedTime,
                    "isRead": email.isRead ? "true" : "false"
                ]
            ))
        }

        return items
    }
}

// MARK: - View Helpers

extension View {
    func hideScrollContentInsetIfAvailable() -> some View {
        return self
    }
}

#Preview {
    EmailView()
        .environmentObject(AuthenticationManager.shared)
}
