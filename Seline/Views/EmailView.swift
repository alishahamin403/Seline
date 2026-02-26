import SwiftUI

struct EmailView: View, Searchable {
    var onDetailNavigationChanged: ((Bool) -> Void)? = nil

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
    @State private var navigationPath = NavigationPath()
    @State private var isSearchActive: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showNewCompose = false
    @State private var cachedDaySections: [EmailDaySection] = []

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
        cachedDaySections
    }

    private var viewBackgroundColor: Color {
        Color.appBackground(colorScheme)
    }

    private var headerSurfaceColor: Color {
        Color.appBackground(colorScheme)
    }

    private var headerContainerColor: Color {
        Color.appSurface(colorScheme)
    }

    private var headerContainerStrokeColor: Color {
        Color.appBorder(colorScheme)
    }

    private var headerControlFillColor: Color {
        Color.appChip(colorScheme)
    }

    private var headerControlIconColor: Color {
        Color.appTextPrimary(colorScheme)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                mainContentView(geometry: geometry)
            }
            .navigationDestination(for: Email.self) { email in
                EmailDetailView(email: email)
                    .edgeSwipeBackEnabled()
            }
        }
        .onAppear {
            onDetailNavigationChanged?(!navigationPath.isEmpty)
            emailService.ensureAutomaticRefreshActive()

            // Register with search service first
            SearchService.shared.registerSearchableProvider(self, for: .email)
            // Also register EmailService to provide saved emails for LLM access
            SearchService.shared.registerSearchableProvider(EmailService.shared, for: .email)
            rebuildDaySections()

            // Clear any email notifications when user opens email view
            Task {
                emailService.notificationService.clearEmailNotifications()

                // Load emails for current tab - will show cached content immediately
                await emailService.loadEmailsForFolder(selectedTab.folder)
                rebuildDaySections()

                // Update app badge to reflect current unread count
                let unreadCount = emailService.inboxEmails.filter { !$0.isRead }.count
                emailService.notificationService.updateAppBadge(count: unreadCount)
            }

        }
        .onChange(of: selectedCategory) { _ in
            rebuildDaySections()
        }
        .onChange(of: showUnreadOnly) { _ in
            rebuildDaySections()
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .events {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchActive = false
                    searchText = ""
                    isSearchFieldFocused = false
                }
                emailService.searchResults = []
            }

            rebuildDaySections()

            guard newTab != .events else { return }
            Task {
                await emailService.loadEmailsForFolder(newTab.folder)
            }
        }
        .onChange(of: searchText) { newValue in
            guard isSearchActive, selectedTab != .events else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 || trimmed.isEmpty else { return }
            Task { @MainActor in
                await emailService.searchEmails(query: trimmed)
            }
        }
        .onReceive(emailService.$inboxEmails) { _ in
            if selectedTab.folder == .inbox {
                rebuildDaySections()
            }
        }
        .onReceive(emailService.$sentEmails) { _ in
            if selectedTab.folder == .sent {
                rebuildDaySections()
            }
        }
        .onChange(of: navigationPath.count) { _ in
            onDetailNavigationChanged?(!navigationPath.isEmpty)
        }
        .onDisappear {
            onDetailNavigationChanged?(false)
        }
        .swipeDownToRevealSearch(
            enabled: selectedTab != .events && !isSearchActive,
            topRegion: UIScreen.main.bounds.height * 0.22,
            minimumDistance: 70
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchActive = true
                isSearchFieldFocused = true
            }
        }
        .swipeUpToDismissSearch(
            enabled: selectedTab != .events
                && isSearchActive
                && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            topRegion: UIScreen.main.bounds.height * 0.28,
            minimumDistance: 54
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                clearSearch()
            }
        }
    }

    // MARK: - View Components
    
    @ViewBuilder
    private func mainContentView(geometry: GeometryProxy) -> some View {
        let topPadding = CGFloat(-4)
        
        VStack(spacing: 0) {
            headerSection(topPadding: topPadding)
            contentSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Animation.smoothTabTransition, value: selectedTab)
        .background(
            viewBackgroundColor
                .ignoresSafeArea()
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(composeButtonOverlay)
        .overlay(interactiveFolderSidebarOverlay(geometry: geometry))
        .sheet(isPresented: $showNewCompose) {
            NewComposeView()
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
        let isSearchHeaderVisible = isSearchActive && selectedTab != .events

        VStack(spacing: 10) {
            if isSearchHeaderVisible {
                searchBarSection
            } else {
                tabSelectorSection
            }

            // Category filter slider - show only for inbox/sent list views when search is hidden
            if selectedTab != .events && !isSearchActive {
                EmailCategoryFilterView(selectedCategory: $selectedCategory)
            }
        }
        .padding(.top, topPadding)
        .padding(.horizontal, isSearchHeaderVisible ? 0 : ShadcnSpacing.screenEdgeHorizontal)
        .padding(.bottom, isSearchHeaderVisible ? 0 : 10)
        .background(
            headerSurfaceColor
        )
    }

    @ViewBuilder
    private var searchBarSection: some View {
        UnifiedSearchBar(
            searchText: $searchText,
            isFocused: $isSearchFieldFocused,
            placeholder: "Search emails",
            onCancel: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    clearSearch()
                }
            },
            colorScheme: colorScheme
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var tabSelectorSection: some View {
        HStack(spacing: 10) {
            folderButton
                .frame(width: 40, height: 36)

            EmailTabView(selectedTab: $selectedTab)
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(width: 40, height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(headerContainerColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(headerContainerStrokeColor, lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity)
    }
    
    private var folderButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingEmailFolderSidebar.toggle()
            }
        }) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(headerControlIconColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(headerControlFillColor)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private var contentSection: some View {
        if isSearchActive && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedTab != .events {
            searchResultsView
        } else if selectedTab == .events {
            eventsTabContent
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
                openEmailDetail(email)
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
            onEmailTap: { email in
                openEmailDetail(email)
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
            },
            hasMoreEmails: emailService.hasMoreEmails[selectedTab.folder] ?? false,
            onLoadMore: {
                await emailService.loadMoreEmails(for: selectedTab.folder)
            }
        )
    }

    private func rebuildDaySections() {
        if let selectedCategory {
            cachedDaySections = emailService.getDayCategorizedEmails(
                for: selectedTab.folder,
                category: selectedCategory,
                unreadOnly: showUnreadOnly
            )
        } else {
            cachedDaySections = emailService.getDayCategorizedEmails(
                for: selectedTab.folder,
                unreadOnly: showUnreadOnly
            )
        }
    }

    private func clearSearch() {
        isSearchActive = false
        isSearchFieldFocused = false
        searchText = ""
        emailService.searchResults = []
    }

    private func openEmailDetail(_ email: Email) {
        navigationPath.append(email)
    }
    
    private var composeButtonOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()

                if selectedTab != .events {
                    // Email tabs: Compose button
                    Button(action: {
                        showNewCompose = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color.black.opacity(colorScheme == .dark ? 0.9 : 0.85))
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.wsLightSurface : Color.white)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.appBorder(colorScheme), lineWidth: 0.8)
                            )
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 8, x: 0, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 30)
                }
            }
        }
    }
    
    private func interactiveFolderSidebarOverlay(geometry: GeometryProxy) -> some View {
        InteractiveSidebarOverlay(
            isPresented: $showingEmailFolderSidebar,
            canOpen: true,
            sidebarWidth: min(300, geometry.size.width * 0.82),
            colorScheme: colorScheme
        ) {
            NavigationStack {
                EmailFolderSidebarView(isPresented: $showingEmailFolderSidebar)
            }
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
            viewBackgroundColor
        )
    }

    private var tagFilterButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" button
                Button(action: {
                    selectedTagId = nil
                }) {
                    let isSelected = selectedTagId == nil
                    let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .all, colorScheme: colorScheme)

                    Text("All")
                        .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                        .overlay(filterButtonStroke(isSelected: isSelected))
                }
                .buttonStyle(PlainButtonStyle())

                // Personal button
                Button(action: {
                    selectedTagId = ""
                }) {
                    let isSelected = selectedTagId == ""
                    let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personal, colorScheme: colorScheme)

                    Text("Personal")
                        .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                        .overlay(filterButtonStroke(isSelected: isSelected))
                }
                .buttonStyle(PlainButtonStyle())

                // Sync button
                Button(action: {
                    selectedTagId = "cal_sync"
                }) {
                    let isSelected = selectedTagId == "cal_sync"
                    let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .personalSync, colorScheme: colorScheme)

                    Text("Sync")
                        .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                        .overlay(filterButtonStroke(isSelected: isSelected))
                }
                .buttonStyle(PlainButtonStyle())

                // User-created tags
                ForEach(tagManager.tags, id: \.id) { tag in
                    Button(action: {
                        selectedTagId = tag.id
                    }) {
                        let isSelected = selectedTagId == tag.id
                        let accentColor = TimelineEventColorManager.filterButtonAccentColor(buttonStyle: .tag(tag.id), colorScheme: colorScheme, tagColorIndex: tag.colorIndex)

                        Text(tag.name)
                            .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                            .foregroundColor(filterButtonTextColor(isSelected: isSelected, accentColor: accentColor))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(filterButtonBackground(isSelected: isSelected, accentColor: accentColor))
                            .overlay(filterButtonStroke(isSelected: isSelected))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
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
                Color.appChip(colorScheme)
            )
    }

    private func filterButtonStroke(isSelected: Bool) -> some View {
        Capsule()
            .stroke(
                Color.appBorder(colorScheme),
                lineWidth: isSelected ? 0 : 1
            )
    }

    private var monthViewContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
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
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.appSurface(colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                            )
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
                        },
                        onCameraAction: {
                            showPhotoImportDialog = true
                        }
                    )
                    .id("agendaView")
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.appSurface(colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .padding(.bottom, 90)
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
