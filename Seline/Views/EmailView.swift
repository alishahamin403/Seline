import SwiftUI

struct EmailView: View, Searchable {
    var onDetailNavigationChanged: ((Bool) -> Void)? = nil

    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: EmailTab = .inbox
    @State private var selectedCategory: EmailCategory? = nil // nil means show all emails
    @State private var showUnreadOnly: Bool = false
    @State private var showingEmailFolderSidebar: Bool = false
    @State private var searchText: String = ""
    @State private var navigationPath = NavigationPath()
    @State private var isSearchActive: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showNewCompose = false
    @StateObject private var hubState = EmailHubState()
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
    @State private var emailSearchDebouncer = DebouncedTaskRunner()

    enum ActiveSheet: Identifiable {
        case viewTask
        case editTask

        var id: Int {
            hashValue
        }
    }

    var currentLoadingState: EmailLoadingState {
        return emailService.getLoadingState(for: selectedTab.folder)
    }

    var currentDaySections: [EmailDaySection] {
        hubState.daySections
    }

    private var pageCardVariant: AppAmbientBackgroundVariant {
        .topLeading
    }

    private var inboxSourceEmails: [Email] {
        emailService.getEmails(for: .inbox)
    }

    private var sentSourceEmails: [Email] {
        emailService.getEmails(for: .sent)
    }

    private var currentPageTitle: String {
        selectedTab.displayName
    }

    private var inboxUnreadCount: Int {
        inboxSourceEmails.filter { !$0.isRead }.count
    }

    private var inboxActionRequiredCount: Int {
        inboxSourceEmails.filter { isActionRequired($0) }.count
    }

    private var inboxTodayCount: Int {
        inboxSourceEmails.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    private var sentTodayCount: Int {
        sentSourceEmails.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    private var sentThisWeekCount: Int {
        sentSourceEmails.filter { Calendar.current.isDate($0.timestamp, equalTo: Date(), toGranularity: .weekOfYear) }.count
    }

    private var sentAwaitingReplyCount: Int {
        sentSourceEmails.filter { isAwaitingReply($0) }.count
    }

    private var todayCalendarEvents: [TaskItem] {
        tasksForCalendarDate(Calendar.current.startOfDay(for: Date()))
    }

    private var syncedCalendarCount: Int {
        taskManager.tasks.values
            .flatMap { $0 }
            .filter { isSyncedCalendarTask($0) }
            .count
    }

    private var quickActionCount: Int {
        [onCalendarAddEnabled, true].filter { $0 }.count
    }

    private var onCalendarAddEnabled: Bool {
        true
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                mainContentView(geometry: geometry)
            }
            .navigationDestination(for: Email.self) { email in
                EmailDetailView(email: email)
            }
        }
        .onAppear {
            onDetailNavigationChanged?(!navigationPath.isEmpty)
            emailService.ensureAutomaticRefreshActive()

            // Register with search service first
            SearchService.shared.registerSearchableProvider(self, for: .email)
            // Also register EmailService to provide saved emails for LLM access
            SearchService.shared.registerSearchableProvider(EmailService.shared, for: .email)
            refreshHubState()

            // Clear any email notifications when user opens email view
            Task {
                emailService.notificationService.clearEmailNotifications()

                // Load emails for current tab - will show cached content immediately
                await emailService.loadEmailsForFolder(selectedTab.folder)
                if selectedTab.folder == .inbox {
                    await emailService.checkForNewEmailsIfNeeded()
                }
                refreshHubState()

                // Update app badge to reflect current unread count
                let unreadCount = emailService.inboxEmails.filter { !$0.isRead }.count
                emailService.notificationService.updateAppBadge(count: unreadCount)
            }

        }
        .onChange(of: selectedCategory) { _ in
            refreshHubState()
        }
        .onChange(of: showUnreadOnly) { _ in
            refreshHubState()
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .events {
                emailSearchDebouncer.cancel()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSearchActive = false
                    searchText = ""
                    isSearchFieldFocused = false
                }
                emailService.searchResults = []
            }

            refreshHubState()

            guard newTab != .events else { return }
            Task {
                await emailService.loadEmailsForFolder(newTab.folder)
                if newTab.folder == .inbox {
                    await emailService.checkForNewEmailsIfNeeded()
                }
            }
        }
        .onChange(of: searchText) { newValue in
            guard isSearchActive, selectedTab != .events else {
                emailSearchDebouncer.cancel()
                return
            }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 || trimmed.isEmpty else {
                emailSearchDebouncer.cancel()
                emailService.searchResults = []
                return
            }
            emailSearchDebouncer.scheduleAsync(delay: 0.22) {
                await emailService.searchEmails(query: trimmed)
            }
        }
        .onChange(of: navigationPath.count) { _ in
            onDetailNavigationChanged?(!navigationPath.isEmpty)
        }
        .onDisappear {
            emailSearchDebouncer.cancel()
            onDetailNavigationChanged?(false)
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
            AppAmbientBackgroundLayer(
                colorScheme: colorScheme,
                variant: pageCardVariant
            )
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
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
                                onSaveRecurring: { updatedTask, scope, occurrenceDate in
                                    taskManager.editTask(
                                        updatedTask,
                                        recurringEditScope: scope,
                                        recurringOccurrenceDate: occurrenceDate
                                    )
                                    selectedTaskForEditing = nil
                                    activeSheet = nil
                                },
                                occurrenceDate: selectedDate,
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
        }
        .padding(.top, topPadding)
        .padding(.horizontal, isSearchHeaderVisible ? 0 : ShadcnSpacing.screenEdgeHorizontal)
        .padding(.bottom, isSearchHeaderVisible ? 0 : 10)
    }

    @ViewBuilder
    private var searchBarSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.emailGlassMutedText(colorScheme))

                TextField("Search emails", text: $searchText)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.emailGlassMutedText(colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 22)

            Button("Cancel") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    clearSearch()
                }
            }
            .font(FontManager.geist(size: 14, weight: .medium))
            .foregroundColor(Color.appTextPrimary(colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: pageCardVariant,
            cornerRadius: 24,
            highlightStrength: 0.75
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder
    private var tabSelectorSection: some View {
        HStack(spacing: 10) {
            folderButton
                .frame(width: 40, height: 36)

            EmailTabView(selectedTab: $selectedTab)
                .frame(maxWidth: .infinity)
            searchButton
                .frame(width: 40, height: 36)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: pageCardVariant,
            cornerRadius: 22,
            highlightStrength: 0.65
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
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var searchButton: some View {
        Button(action: {
            guard selectedTab != .events else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchActive = true
                isSearchFieldFocused = true
            }
        }) {
            ZStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.homeGlassAccent)
            )
            .opacity(selectedTab == .events ? 0 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(selectedTab == .events)
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
            scopeTitle: currentPageTitle,
            searchText: searchText,
            searchResults: emailService.searchResults,
            isLoading: emailService.isSearching,
            onEmailTap: { email in
                openEmailDetail(email)
            },
            onDeleteEmail: { email in
                emailService.deleteEmailImmediately(email)
                Task {
                    await emailService.searchEmails(query: searchText)
                }
            },
            onMarkAsUnread: { email in
                emailService.markAsUnread(email)
            }
        )
    }
    
    private var emailListView: some View {
        let topContent: AnyView? = isSearchActive
            ? nil
            : AnyView(pageTopContent)

        return EmailListByDay(
            daySections: currentDaySections,
            loadingState: currentLoadingState,
            presentationStyle: selectedTab == .sent ? .sent : .inbox,
            topContent: topContent,
            onRefresh: {
                await refreshCurrentFolder()
            },
            onEmailTap: { email in
                openEmailDetail(email)
            },
            onDeleteEmail: { email in
                emailService.deleteEmailImmediately(email)
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

    private func refreshHubState() {
        hubState.updateInputs(
            selectedTab: selectedTab,
            selectedCategory: selectedCategory,
            showUnreadOnly: showUnreadOnly
        )
    }

    private func clearSearch() {
        emailSearchDebouncer.cancel()
        isSearchActive = false
        isSearchFieldFocused = false
        searchText = ""
        emailService.searchResults = []
    }

    private func openEmailDetail(_ email: Email) {
        navigationPath.append(email)
    }
    
    private func interactiveFolderSidebarOverlay(geometry: GeometryProxy) -> some View {
        InteractiveSidebarOverlay(
            isPresented: $showingEmailFolderSidebar,
            canOpen: true,
            sidebarWidth: min(304, geometry.size.width * 0.84),
            colorScheme: colorScheme,
            showsTrailingDivider: false
        ) {
            EmailFolderSidebarView(isPresented: $showingEmailFolderSidebar)
        }
    }

    private func refreshCurrentFolder() async {
        await emailService.loadEmailsForFolder(selectedTab.folder, forceRefresh: true)
        if selectedTab.folder == .inbox {
            await emailService.checkForNewEmailsIfNeeded()
        }
    }

    // MARK: - Events Tab Content

    private var eventsTabContent: some View {
        monthViewContent
    }

    private var tagFilterButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" button
                Button(action: {
                    selectedTagId = nil
                }) {
                    let isSelected = selectedTagId == nil

                    Text("All")
                        .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(filterButtonBackground(isSelected: isSelected))
                        .overlay(filterButtonStroke(isSelected: isSelected))
                }
                .buttonStyle(PlainButtonStyle())

                // Personal button
                Button(action: {
                    selectedTagId = ""
                }) {
                    let isSelected = selectedTagId == ""

                    Text("Personal")
                        .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(filterButtonBackground(isSelected: isSelected))
                        .overlay(filterButtonStroke(isSelected: isSelected))
                }
                .buttonStyle(PlainButtonStyle())

                // Sync button
                Button(action: {
                    selectedTagId = "cal_sync"
                }) {
                    let isSelected = selectedTagId == "cal_sync"

                    Text("Sync")
                        .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                        .foregroundColor(filterButtonTextColor(isSelected: isSelected))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(filterButtonBackground(isSelected: isSelected))
                        .overlay(filterButtonStroke(isSelected: isSelected))
                }
                .buttonStyle(PlainButtonStyle())

                // User-created tags
                ForEach(tagManager.tags, id: \.id) { tag in
                    Button(action: {
                        selectedTagId = tag.id
                    }) {
                        let isSelected = selectedTagId == tag.id

                        Text(tag.name)
                            .font(FontManager.geist(size: 12, systemWeight: isSelected ? .semibold : .regular))
                            .foregroundColor(filterButtonTextColor(isSelected: isSelected))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(filterButtonBackground(isSelected: isSelected))
                            .overlay(filterButtonStroke(isSelected: isSelected))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: pageCardVariant,
            cornerRadius: 22,
            highlightStrength: 0.45
        )
    }

    private func filterButtonTextColor(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? .black : .white
        } else {
            return Color.shadcnForeground(colorScheme)
        }
    }

    private func filterButtonBackground(isSelected: Bool) -> some View {
        Capsule()
            .fill(
                isSelected
                    ? (colorScheme == .dark ? Color.white.opacity(0.92) : Color.appTextPrimary(colorScheme))
                    : Color.appChip(colorScheme)
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
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 14) {
                calendarHeroCard

                tagFilterButtons

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
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .appAmbientCardStyle(
                    colorScheme: colorScheme,
                    variant: pageCardVariant,
                    cornerRadius: 22,
                    highlightStrength: 0.48
                )

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
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .appAmbientCardStyle(
                    colorScheme: colorScheme,
                    variant: pageCardVariant,
                    cornerRadius: 22,
                    highlightStrength: 0.42
                )
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 90)
        }
    }

    @ViewBuilder
    private var pageTopContent: some View {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                if selectedTab == .inbox {
                    inboxHeroCard
                } else if selectedTab == .sent {
                    sentHeroCard
                }

                EmailCategoryFilterView(selectedCategory: $selectedCategory)
            }
        )
    }

    private var inboxHeroCard: some View {
        AnyView(
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inbox")
                            .font(FontManager.geist(size: 31, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text(inboxUnreadCount == 0 ? "You are caught up right now." : "\(inboxUnreadCount) unread across your latest conversations.")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(Color.emailGlassMutedText(colorScheme))
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        pageHeroButton(title: "Search", systemImage: "magnifyingglass") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearchActive = true
                                isSearchFieldFocused = true
                            }
                        }

                        pageHeroIconButton(systemImage: "plus") {
                            showNewCompose = true
                        }
                    }
                }

                HStack(spacing: 10) {
                    summaryMetricTile(title: "Unread", value: "\(inboxUnreadCount)")
                    summaryMetricTile(title: "Action", value: "\(inboxActionRequiredCount)")
                    summaryMetricTile(title: "Today", value: "\(inboxTodayCount)")
                }
            }
            .padding(18)
            .appAmbientCardStyle(
                colorScheme: colorScheme,
                variant: pageCardVariant,
                cornerRadius: 26,
                highlightStrength: 0.95
            )
        )
    }

    private var sentHeroCard: some View {
        AnyView(
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sent")
                            .font(FontManager.geist(size: 31, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text(sentTodayCount == 0 ? "No sends today yet." : "\(sentTodayCount) messages sent today.")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(Color.emailGlassMutedText(colorScheme))
                    }

                    Spacer(minLength: 0)

                    pageHeroButton(title: "Search", systemImage: "magnifyingglass") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearchActive = true
                            isSearchFieldFocused = true
                        }
                    }
                }

                HStack(spacing: 10) {
                    summaryMetricTile(title: "Today", value: "\(sentTodayCount)")
                    summaryMetricTile(title: "This Week", value: "\(sentThisWeekCount)")
                    summaryMetricTile(title: "Waiting", value: "\(sentAwaitingReplyCount)")
                }
            }
            .padding(18)
            .appAmbientCardStyle(
                colorScheme: colorScheme,
                variant: pageCardVariant,
                cornerRadius: 26,
                highlightStrength: 0.95
            )
        )
    }

    private var calendarHeroCard: some View {
        AnyView(
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Calendar")
                            .font(FontManager.geist(size: 31, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text(formattedCalendarHeroDate(selectedDate))
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(Color.emailGlassMutedText(colorScheme))
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 8) {
                        pageHeroButton(title: "Add", systemImage: "plus") {
                            addEventDate = selectedDate
                            showAddEventPopup = true
                        }

                        pageHeroButton(title: "Import", systemImage: "camera") {
                            showPhotoImportDialog = true
                        }
                    }
                }

                HStack(spacing: 10) {
                    summaryMetricTile(title: "Today", value: "\(todayCalendarEvents.count)")
                    summaryMetricTile(title: "Synced", value: "\(syncedCalendarCount)")
                    summaryMetricTile(title: "Quick", value: "\(quickActionCount)")
                }
            }
            .padding(18)
            .appAmbientCardStyle(
                colorScheme: colorScheme,
                variant: pageCardVariant,
                cornerRadius: 26,
                highlightStrength: 0.95
            )
        )
    }

    private func summaryMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(Color.emailGlassMutedText(colorScheme))

            Text(value)
                .font(FontManager.geist(size: 22, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
    }

    private func compactHeroButton(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(FontManager.geist(size: 12, weight: .semibold))
        .foregroundColor(.black)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(
            Capsule()
                .fill(Color.homeGlassAccent)
        )
    }

    private func pageHeroButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            compactHeroButton(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func pageHeroIconButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.homeGlassAccent)
                )
        }
        .buttonStyle(.plain)
    }

    private func formattedCalendarHeroDate(_ date: Date) -> String {
        FormatterCache.weekdayMonthDay.string(from: date)
    }

    private func tasksForCalendarDate(_ date: Date) -> [TaskItem] {
        let baseTasks = taskManager.getAllTasks(for: date)
        return filterTasksForSelectedTag(baseTasks)
    }

    private func filterTasksForSelectedTag(_ tasks: [TaskItem]) -> [TaskItem] {
        guard let selectedTagId else {
            return tasks
        }

        if selectedTagId.isEmpty {
            return tasks.filter { $0.tagId == nil && !isSyncedCalendarTask($0) }
        }

        if selectedTagId == "cal_sync" {
            return tasks.filter { isSyncedCalendarTask($0) }
        }

        return tasks.filter { $0.tagId == selectedTagId }
    }

    private func isActionRequired(_ email: Email) -> Bool {
        let signal = [
            email.subject,
            email.snippet,
            email.aiSummary ?? "",
            email.sender.displayName,
            email.sender.email
        ]
        .joined(separator: " ")
        .lowercased()
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let noActionPhrases = [
            "no action required",
            "no response required",
            "for your information",
            "fyi",
            "informational only"
        ]
        let directRequestPhrases = [
            "action required",
            "requires your action",
            "please reply",
            "reply needed",
            "reply required",
            "respond by",
            "response required",
            "please confirm",
            "verify your",
            "review and sign",
            "approval required",
            "please approve",
            "rsvp",
            "confirm attendance",
            "submit",
            "upload"
        ]
        let deadlineTaskPhrases = [
            "payment due",
            "invoice due",
            "past due",
            "overdue",
            "due today",
            "due tomorrow",
            "deadline",
            "expires on",
            "payment failed",
            "card declined"
        ]
        let criticalAlertPhrases = [
            "security alert",
            "fraud alert",
            "suspicious activity",
            "password reset",
            "verify your account",
            "low balance",
            "account locked"
        ]
        let announcementPhrases = [
            "newsletter",
            "announcement",
            "new feature",
            "release notes",
            "product update",
            "developer news",
            "what's new",
            "tips",
            "learn more",
            "read more",
            "webinar"
        ]
        let broadcastSenderHints = [
            "noreply",
            "no-reply",
            "donotreply",
            "newsletter",
            "updates@",
            "news@",
            "notifications@"
        ]

        if containsAny(in: signal, phrases: noActionPhrases) {
            return false
        }

        if containsAny(in: signal, phrases: criticalAlertPhrases) {
            return true
        }

        let hasDirectRequest = containsAny(in: signal, phrases: directRequestPhrases)
        let hasDeadlineTask = containsAny(in: signal, phrases: deadlineTaskPhrases)
        let senderEmail = email.sender.email.lowercased()
        let subjectSnippet = "\(email.subject) \(email.snippet)".lowercased()
        let isLikelyBroadcastSender = containsAny(in: senderEmail, phrases: broadcastSenderHints)
        let isAnnouncement = containsAny(in: signal, phrases: announcementPhrases)
            || containsAny(in: subjectSnippet, phrases: announcementPhrases)
            || email.category == .promotions
            || email.category == .social

        if isAnnouncement && !hasDirectRequest && !hasDeadlineTask {
            return false
        }

        if isLikelyBroadcastSender && !hasDeadlineTask {
            return false
        }

        if hasDeadlineTask {
            return true
        }

        return hasDirectRequest && !isAnnouncement
    }

    private func isAwaitingReply(_ email: Email) -> Bool {
        let sentThreadId = email.gmailThreadId ?? email.threadId
        guard let sentThreadId else { return false }

        let laterInboxReply = inboxSourceEmails.contains { inboxEmail in
            let inboxThreadId = inboxEmail.gmailThreadId ?? inboxEmail.threadId
            return inboxThreadId == sentThreadId && inboxEmail.timestamp > email.timestamp
        }

        return !laterInboxReply
    }

    private func isSyncedCalendarTask(_ task: TaskItem) -> Bool {
        task.id.hasPrefix("cal_")
            || task.isFromCalendar
            || task.calendarEventId != nil
            || task.tagId == "cal_sync"
    }

    private func containsAny(in text: String, phrases: [String]) -> Bool {
        phrases.contains(where: { text.contains($0) })
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
