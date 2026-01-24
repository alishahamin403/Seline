import SwiftUI

struct EmailView: View, Searchable {
    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @StateObject private var locationsManager = LocationsManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: EmailTab = .inbox
    @State private var selectedCategory: EmailCategory? = nil // nil means show all emails
    @State private var showUnreadOnly: Bool = false
    @State private var lastRefreshTime: Date? = nil
    @State private var showingEmailFolderSidebar: Bool = false
    @State private var searchText: String = ""
    @State private var selectedSearchEmail: Email? = nil
    @State private var isSearchActive: Bool = false

    // Events tab state
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedTagId: String? = nil
    @State private var showPhotoImportDialog = false
    @State private var showCameraActionSheet = false
    @State private var cameraSourceType: UIImagePickerController.SourceType = .camera
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var showAddEventPopup = false
    @State private var addEventDate: Date = Date()
    @State private var selectedTaskForViewing: TaskItem?
    @State private var selectedTaskForEditing: TaskItem?
    @State private var activeSheet: ActiveSheet?

    enum ActiveSheet: Identifiable {
        case viewTask
        case editTask

        var id: Int {
            hashValue
        }
    }

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
        .confirmationDialog("Import Schedule", isPresented: $showPhotoImportDialog) {
            Button("Take Photo") {
                cameraSourceType = .camera
                showImagePicker = true
            }
            Button("Choose from Library") {
                cameraSourceType = .photoLibrary
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Select a source to import your schedule")
        }
        .sheet(isPresented: $showImagePicker) {
            CameraAndLibraryPicker(image: $selectedImage, sourceType: cameraSourceType)
                .onDisappear {
                    if selectedImage != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showCameraActionSheet = true
                        }
                    }
                }
        }
        .sheet(isPresented: $showCameraActionSheet) {
            CameraActionSheetProcessing(
                selectedImage: $selectedImage,
                isPresented: $showCameraActionSheet
            )
            .presentationBg()
        }
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .viewTask:
                    if let task = selectedTaskForViewing {
                        NavigationView {
                            ViewEventView(
                                task: task,
                                onEdit: {
                                    selectedTaskForEditing = task
                                    activeSheet = nil
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                        activeSheet = .editTask
                                    }
                                },
                                onDelete: { taskToDelete in
                                    taskManager.deleteTask(taskToDelete)
                                    selectedTaskForViewing = nil
                                    activeSheet = nil
                                },
                                onDeleteRecurringSeries: { taskToDelete in
                                    taskManager.deleteRecurringTask(taskToDelete)
                                    selectedTaskForViewing = nil
                                    activeSheet = nil
                                }
                            )
                        }
                    }
                case .editTask:
                    if let task = selectedTaskForEditing {
                        NavigationView {
                            EditTaskView(
                                task: task,
                                onSave: { updatedTask in
                                    taskManager.editTask(updatedTask)
                                    selectedTaskForEditing = nil
                                    activeSheet = nil
                                },
                                onCancel: {
                                    selectedTaskForEditing = nil
                                    activeSheet = nil
                                },
                                onDelete: { taskToDelete in
                                    taskManager.deleteTask(taskToDelete)
                                    selectedTaskForEditing = nil
                                    activeSheet = nil
                                },
                                onDeleteRecurringSeries: { taskToDelete in
                                    taskManager.deleteRecurringTask(taskToDelete)
                                    selectedTaskForEditing = nil
                                    activeSheet = nil
                                }
                            )
                        }
                    }
                }
            }
            .presentationBg()
        }
        .sheet(isPresented: $showAddEventPopup) {
            AddEventPopupView(
                isPresented: $showAddEventPopup,
                onSave: { title, description, date, time, endTime, reminder, recurring, frequency, customDays, tagId, location in
                    addEventToCalendar(title: title, description: description, date: date, time: time, endTime: endTime, reminder: reminder, recurring: recurring, frequency: frequency, tagId: tagId, location: location)
                },
                initialDate: addEventDate,
                initialTime: nil
            )
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

            // Category filter slider - hide in events tab
            if selectedTab != .events {
                EmailCategoryFilterView(selectedCategory: $selectedCategory)
                    .onChange(of: selectedCategory) { _ in
                        // Category change doesn't require reloading data, just filtering
                    }
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
        if selectedTab == .events {
            eventsTabContent
        } else if isSearchActive && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

                if selectedTab == .events {
                    // Events tab: Camera and + buttons stacked vertically
                    VStack(spacing: 12) {
                        Button(action: {
                            showPhotoImportDialog = true
                        }) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(Color(red: 0.2, green: 0.2, blue: 0.2)))
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            addEventDate = selectedDate
                            showAddEventPopup = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Circle().fill(Color(red: 0.2, green: 0.2, blue: 0.2)))
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 30)
                } else {
                    // Email tabs: Compose button
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

    // MARK: - Events Tab Content

    private var eventsTabContent: some View {
        VStack(spacing: 0) {
            // Tag filter buttons
            tagFilterButtons

            // Month view content
            monthViewContent
        }
        .background(
            colorScheme == .dark ? Color.black : Color.white
        )
    }

    private var tagFilterButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTagId = nil
                    }
                }) {
                    let isSelected = selectedTagId == nil
                    let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .all, colorScheme: colorScheme)

                    Text("All")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                }
                .buttonStyle(PlainButtonStyle())

                // Personal button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTagId = ""
                    }
                }) {
                    let isSelected = selectedTagId == ""
                    let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personal, colorScheme: colorScheme)

                    Text("Personal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                }
                .buttonStyle(PlainButtonStyle())

                // Sync button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTagId = "cal_sync"
                    }
                }) {
                    let isSelected = selectedTagId == "cal_sync"
                    let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personalSync, colorScheme: colorScheme)

                    Text("Sync")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                }
                .buttonStyle(PlainButtonStyle())

                // User-created tags
                ForEach(tagManager.tags, id: \.id) { tag in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTagId = tag.id
                        }
                    }) {
                        let isSelected = selectedTagId == tag.id
                        let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .tag(tag.id), colorScheme: colorScheme, tagColorIndex: tag.colorIndex)

                        Text(tag.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func filterButtonTextColor(isSelected: Bool, accentColor: Color) -> Color {
        if isSelected {
            return Color.white
        } else {
            return Color.shadcnForeground(colorScheme)
        }
    }

    private func filterButtonBackground(isSelected: Bool, accentColor: Color) -> some View {
        Capsule()
            .fill(isSelected ?
                accentColor :
                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )
    }

    private var monthViewContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    // Calendar month grid
                    CalendarMonthView(
                        selectedDate: $selectedDate,
                        selectedTagId: selectedTagId,
                        onTapEvent: { task in
                            selectedTaskForViewing = task
                            activeSheet = .viewTask
                        },
                        onAddEvent: { date in
                            addEventDate = date
                            showAddEventPopup = true
                        }
                    )

                    // Agenda view for selected date
                    CalendarAgendaView(
                        selectedDate: selectedDate,
                        selectedTagId: selectedTagId,
                        onTapEvent: { task in
                            selectedTaskForViewing = task
                            activeSheet = .viewTask
                        },
                        onToggleCompletion: { task in
                            taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                        },
                        onAddEvent: { date in
                            addEventDate = date
                            showAddEventPopup = true
                        }
                    )
                    .id("agendaView")
                }
            }
            .onChange(of: selectedDate) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("agendaView", anchor: .top)
                }
            }
        }
    }

    private func addEventToCalendar(title: String, description: String?, date: Date, time: Date?, endTime: Date?, reminder: ReminderTime?, recurring: Bool, frequency: RecurrenceFrequency?, tagId: String?, location: String?) {
        let calendar = Calendar.current
        let weekdayIndex = calendar.component(.weekday, from: date)
        let weekday: WeekDay
        switch weekdayIndex {
        case 1: weekday = .sunday
        case 2: weekday = .monday
        case 3: weekday = .tuesday
        case 4: weekday = .wednesday
        case 5: weekday = .thursday
        case 6: weekday = .friday
        case 7: weekday = .saturday
        default: weekday = .monday
        }

        taskManager.addTask(
            title: title,
            to: weekday,
            description: description,
            scheduledTime: time,
            endTime: endTime,
            targetDate: date,
            reminderTime: reminder,
            location: location,
            isRecurring: recurring,
            recurrenceFrequency: frequency,
            tagId: tagId
        )
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
