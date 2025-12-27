import SwiftUI

struct EmailView: View, Searchable {
    @StateObject private var emailService = EmailService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: EmailTab = .inbox
    @State private var selectedCategory: EmailCategory? = nil // nil means show all emails
    @State private var showUnreadOnly: Bool = false
    @State private var lastRefreshTime: Date? = nil
    @State private var showingEmailFolderSidebar: Bool = false
    @State private var searchText: String = ""
    @State private var selectedSearchEmail: Email? = nil
    @State private var isSearchActive: Bool = false

    var currentEmails: [Email] {
        return emailService.getEmails(for: selectedTab.folder)
    }

    var currentLoadingState: EmailLoadingState {
        return emailService.getLoadingState(for: selectedTab.folder)
    }

    var currentDaySections: [EmailDaySection] {
        if let selectedCategory = selectedCategory {
            return emailService.getDayCategorizedEmails(for: selectedTab.folder, category: selectedCategory, unreadOnly: showUnreadOnly)
        } else {
            // Show all emails when no category is selected
            return emailService.getDayCategorizedEmails(for: selectedTab.folder, unreadOnly: showUnreadOnly)
        }
    }


    var body: some View {
        GeometryReader { geometry in
            mainContentView(geometry: geometry)
        }
        .onAppear {
            // Register with search service first
            SearchService.shared.registerSearchableProvider(self, for: .email)
            // Also register EmailService to provide saved emails for LLM access
            SearchService.shared.registerSearchableProvider(EmailService.shared, for: .email)

            // Clear any email notifications when user opens email view
            Task {
                emailService.notificationService.clearEmailNotifications()

                // Load emails for current tab - will show cached content immediately
                await emailService.loadEmailsForFolder(selectedTab.folder)

                // Update app badge to reflect current unread count
                let unreadCount = emailService.inboxEmails.filter { !$0.isRead }.count
                emailService.notificationService.updateAppBadge(count: unreadCount)
            }
        }
    }

    // MARK: - View Components
    
    @ViewBuilder
    private func mainContentView(geometry: GeometryProxy) -> some View {
        let topPadding = CGFloat(4)
        
        VStack(spacing: 0) {
            headerSection(topPadding: topPadding)
            contentSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(composeButtonOverlay)
        .overlay(folderSidebarOverlay(geometry: geometry))
        .sheet(item: $selectedSearchEmail) { email in
            EmailDetailView(email: email)
                .presentationBg()
        }
    }
    
    @ViewBuilder
    private func headerSection(topPadding: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Tab selector and buttons
            tabSelectorSection(topPadding: topPadding)

            // Search bar - show when search is active
            if isSearchActive {
                searchBarSection(topPadding: 0)
            }

            // Category filter slider
            EmailCategoryFilterView(selectedCategory: $selectedCategory)
                .onChange(of: selectedCategory) { _ in
                    // Category change doesn't require reloading data, just filtering
                }
        }
        .background(
            (colorScheme == .dark ? Color.black : Color.white)
        )
    }
    
    @ViewBuilder
    private func searchBarSection(topPadding: CGFloat) -> some View {
        EmailSearchBar(searchText: $searchText) { query in
            Task { @MainActor in
                await emailService.searchEmails(query: query)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, topPadding)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
    
    @ViewBuilder
    private func tabSelectorSection(topPadding: CGFloat) -> some View {
        HStack(spacing: 12) {
            folderButton
            searchButton

            Spacer()

            EmailTabView(selectedTab: $selectedTab)
                .onChange(of: selectedTab) { newTab in
                    Task {
                        await emailService.loadEmailsForFolder(newTab.folder)
                    }
                }

            Spacer()

            unreadFilterButton
        }
        .padding(.horizontal, 20)
        .padding(.top, topPadding)
        .padding(.bottom, 12)
    }
    
    private var searchButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSearchActive {
                    isSearchActive = false
                    searchText = ""
                    emailService.searchResults = []
                } else {
                    isSearchActive = true
                }
            }
        }) {
            Image(systemName: isSearchActive ? "xmark.circle.fill" : "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var folderButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingEmailFolderSidebar.toggle()
            }
        }) {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var unreadFilterButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showUnreadOnly.toggle()
            }
        }) {
            Image(systemName: showUnreadOnly ? "envelope.badge.fill" : "envelope.badge")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(
                    showUnreadOnly ?
                        (colorScheme == .dark ? .white : .black) :
                        Color.gray
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            showUnreadOnly ?
                                (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)) :
                                (colorScheme == .dark ? Color.gray.opacity(0.15) : Color.gray.opacity(0.08))
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var contentSection: some View {
        if isSearchActive && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResultsView
        } else {
            emailListView
        }
    }
    
    private var searchResultsView: some View {
        EmailSearchResultsView(
            searchText: searchText,
            searchResults: emailService.searchResults,
            isLoading: emailService.isSearching,
            onEmailTap: { email in
                selectedSearchEmail = email
            },
            onDeleteEmail: { email in
                Task {
                    do {
                        try await emailService.deleteEmail(email)
                        await emailService.searchEmails(query: searchText)
                    } catch {
                        print("Failed to delete email: \(error.localizedDescription)")
                    }
                }
            },
            onMarkAsUnread: { email in
                emailService.markAsUnread(email)
            }
        )
    }
    
    private var emailListView: some View {
        EmailListByDay(
            daySections: currentDaySections,
            loadingState: currentLoadingState,
            onRefresh: {
                await refreshCurrentFolder()
            },
            onDeleteEmail: { email in
                Task {
                    do {
                        try await emailService.deleteEmail(email)
                    } catch {
                        print("Failed to delete email: \(error.localizedDescription)")
                    }
                }
            },
            onMarkAsUnread: { email in
                emailService.markAsUnread(email)
            }
        )
    }
    
    private var composeButtonOverlay: some View {
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
                                .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                        )
                        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 30)
            }
        }
    }
    
    @ViewBuilder
    private func folderSidebarOverlay(geometry: GeometryProxy) -> some View {
        if showingEmailFolderSidebar {
            ZStack {
                NavigationStack {
                    HStack(spacing: 0) {
                        EmailFolderSidebarView(isPresented: $showingEmailFolderSidebar)
                            .frame(width: geometry.size.width * 0.85)
                            .transition(.move(edge: .leading))
                            .gesture(
                                DragGesture()
                                    .onEnded { value in
                                        if value.translation.width < -100 {
                                            withAnimation {
                                                showingEmailFolderSidebar = false
                                            }
                                        }
                                    }
                            )

                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation {
                                    showingEmailFolderSidebar = false
                                }
                            }
                    }
                }
            }
            .allowsHitTesting(showingEmailFolderSidebar)
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
