import SwiftUI

struct EmailView: View, Searchable {
    @StateObject private var emailService = EmailService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: EmailTab = .inbox

    var currentEmails: [Email] {
        return emailService.getEmails(for: selectedTab.folder)
    }

    var currentLoadingState: EmailLoadingState {
        return emailService.getLoadingState(for: selectedTab.folder)
    }

    var currentSections: [EmailSection] {
        return emailService.getCategorizedEmails(for: selectedTab.folder)
    }


    var body: some View {
        GeometryReader { geometry in
            let topPadding = CGFloat(8)

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Tab selector - always visible now
                    EmailTabView(selectedTab: $selectedTab)
                        .onChange(of: selectedTab) { newTab in
                            // Load emails for the selected folder, respecting cache
                            Task {
                                await emailService.loadEmailsForFolder(newTab.folder)
                            }
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
            Task {
                // Load emails for current tab, respecting cache
                await emailService.loadEmailsForFolder(selectedTab.folder)
            }

            // Register with search service
            SearchService.shared.registerSearchableProvider(self, for: .email)
        }
    }

    private func refreshCurrentFolder() async {
        await emailService.loadEmailsForFolder(selectedTab.folder, forceRefresh: true)
    }

    private func openGmailCompose() {
        // Most reliable Gmail compose URL scheme
        let composeURL = "googlegmail://co?to=&subject=&body="

        if let url = URL(string: composeURL) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                print("✅ Opening Gmail compose with URL: \(composeURL)")
                return
            } else {
                print("❌ Cannot open Gmail compose URL: \(composeURL)")
            }
        }

        // Fallback: Try to open Gmail app main screen
        let gmailMainURL = "googlegmail://"
        if let url = URL(string: gmailMainURL) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                print("✅ Opening Gmail main app as fallback")
                return
            } else {
                print("❌ Cannot open Gmail main app")
            }
        }

        print("❌ Gmail app not found or not accessible")
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
