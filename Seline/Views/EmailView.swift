import SwiftUI

struct PlanView: View, Searchable {
    var isVisible: Bool = true
    @Binding var selectedTab: EmailTab
    var onDetailNavigationChanged: ((Bool) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    private struct ContextChipItem: Hashable {
        let title: String
        let filter: EmailHubState.ContextFilter
    }

    @ObservedObject private var emailService = EmailService.shared
    @ObservedObject private var taskManager = TaskManager.shared
    @ObservedObject private var tagManager = TagManager.shared
    private let pageRefreshCoordinator = PageRefreshCoordinator.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    @State private var selectedCategory: EmailCategory? = nil // nil means show all emails
    @State private var selectedContextChipFilter: EmailHubState.ContextFilter? = nil
    @State private var searchText: String = ""
    @State private var navigationPath = NavigationPath()
    @State private var isSearchActive: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showNewCompose = false
    @StateObject private var hubState = EmailHubState()
    // Calendar tab state
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
    @State private var avatarPrefetchTask: Task<Void, Never>?
    @State private var lastFolderLoadAt: [EmailFolder: Date] = [:]
    @State private var lastMailboxTab: EmailTab = .inbox

    private let folderRefreshInterval: TimeInterval = 30

    enum ActiveSheet: Identifiable {
        case viewTask
        case editTask

        var id: Int {
            hashValue
        }
    }

    private var pageCardVariant: AppAmbientBackgroundVariant {
        .topLeading
    }

    private var isOverlayPresentation: Bool {
        onClose != nil
    }

    private var currentPageTitle: String {
        selectedTab.displayName
    }

    private var activeMailboxTab: EmailTab {
        selectedTab == .calendar ? lastMailboxTab : selectedTab
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentSearchPlaceholder: String {
        selectedTab == .calendar ? "Search calendar" : "Search messages"
    }

    private var inboxUnreadCount: Int {
        hubState.inboxUnreadCount
    }

    private var inboxActionRequiredCount: Int {
        hubState.inboxActionRequiredCount
    }

    private var todayInboxCount: Int {
        hubState.todayInboxCount
    }

    private var inboxTodaySummary: String {
        hubState.inboxTodaySummary
    }

    private var sentTodayCount: Int {
        hubState.sentTodayCount
    }

    private var sentThisWeekCount: Int {
        hubState.sentThisWeekCount
    }

    private var sentAwaitingReplyCount: Int {
        hubState.sentAwaitingReplyCount
    }

    private var displayedDaySections: [EmailDaySection] {
        hubState.displayedDaySections
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
            if selectedTab != .calendar {
                lastMailboxTab = selectedTab
            }
            if isOverlayPresentation {
                clearSearch()
                selectedContextChipFilter = nil
                if selectedTab != .inbox {
                    selectedCategory = nil
                }
            }

            // Register with search service first
            SearchService.shared.registerSearchableProvider(self)
            refreshHubState()
            handleVisibilityChange(isVisible, reason: "appear")
        }
        .onChange(of: selectedCategory) { _ in
            refreshHubState()
        }
        .onChange(of: selectedContextChipFilter) { _ in
            refreshHubState()
        }
        .onChange(of: isVisible) { newValue in
            handleVisibilityChange(newValue, reason: "visibility")
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            handleVisibilityChange(isVisible, reason: "scene_active")
        }
        .onChange(of: selectedTab) { newTab in
            emailSearchDebouncer.cancel()
            if isOverlayPresentation {
                selectedContextChipFilter = nil
                if newTab != .inbox {
                    selectedCategory = nil
                }
            } else {
                selectedContextChipFilter = defaultContextFilter(for: newTab, current: selectedContextChipFilter)
            }
            if newTab == .calendar {
                avatarPrefetchTask?.cancel()
                clearSearch()
                emailService.searchResults = []
                return
            }

            lastMailboxTab = newTab

            if isSearchActive {
                let trimmed = trimmedSearchText
                if trimmed.count >= 2 {
                    Task {
                        await emailService.searchEmails(query: trimmed)
                    }
                } else {
                    emailService.searchResults = []
                }
            }

            refreshHubState()

            guard isVisible else { return }
            Task {
                await prepareCurrentFolderForDisplay(folder: newTab.folder, reason: "tab:\(newTab.displayName)")
                pageRefreshCoordinator.markValidated(.plan)
            }
        }
        .onChange(of: emailService.inboxEmails.count) { _ in
            guard !isVisible else { return }
            pageRefreshCoordinator.markDirty([.plan, .home], reason: .emailDataChanged)
        }
        .onChange(of: emailService.sentEmails.count) { _ in
            guard !isVisible else { return }
            pageRefreshCoordinator.markDirty(.plan, reason: .emailDataChanged)
        }
        .onChange(of: searchText) { newValue in
            guard isSearchActive else {
                emailSearchDebouncer.cancel()
                return
            }
            guard selectedTab != .calendar else {
                emailSearchDebouncer.cancel()
                emailService.searchResults = []
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
            avatarPrefetchTask?.cancel()
            onDetailNavigationChanged?(false)
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
        .background(
            AppAmbientBackgroundLayer(
                colorScheme: colorScheme,
                variant: pageCardVariant
            )
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .bottomTrailing) {
            if shouldShowOverlayFloatingComposeButton {
                overlayFloatingComposeButton
                    .padding(.trailing, 16)
                    .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 22 : 16)
            }
        }
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
        let isSearchHeaderVisible = isSearchActive && !isOverlayPresentation

        VStack(spacing: 10) {
            if isOverlayPresentation, let onClose {
                overlayHeaderSection(action: onClose)
            } else if isSearchHeaderVisible {
                searchBarSection
            } else {
                tabSelectorSection
            }
        }
        .padding(.top, topPadding)
        .padding(.horizontal, isSearchHeaderVisible ? 0 : ShadcnSpacing.screenEdgeHorizontal)
        .padding(.bottom, isSearchHeaderVisible ? 0 : 10)
    }

    private func overlayDismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.appChip(colorScheme))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func overlayHeaderSection(action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            overlayDismissButton(action: action)
                .fixedSize()

            headerCenterContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var headerCenterContent: some View {
        switch selectedTab {
        case .inbox:
            inboxHeaderCategoryStrip
        case .calendar:
            calendarHeaderFilterStrip
        case .sent:
            mailHeaderTitle("Sent")
        }
    }

    private func mailHeaderTitle(_ title: String) -> some View {
        Text(title)
            .font(FontManager.geist(size: 17, weight: .semibold))
            .foregroundColor(Color.appTextPrimary(colorScheme))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    private var inboxHeaderCategoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                EmailCategoryChip(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    colorScheme: colorScheme
                ) {
                    HapticManager.shared.selection()
                    selectedCategory = nil
                }

                ForEach(EmailCategory.allCases, id: \.self) { category in
                    EmailCategoryChip(
                        title: category.displayName,
                        isSelected: selectedCategory == category,
                        colorScheme: colorScheme
                    ) {
                        HapticManager.shared.selection()
                        if selectedCategory == category {
                            selectedCategory = nil
                        } else {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .hideScrollContentInsetIfAvailable()
    }

    @ViewBuilder
    private var searchBarSection: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.emailGlassMutedText(colorScheme))

                TextField(currentSearchPlaceholder, text: $searchText)
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
            headerLeadingActionButton
                .frame(width: 42, height: 42)
            headerCenterContent
                .frame(maxWidth: .infinity, alignment: .leading)
            headerPrimaryActionButton
                .frame(width: 42, height: 42)
            if selectedTab != .calendar {
                searchButton
                    .frame(width: 42, height: 42)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var headerLeadingActionButton: some View {
        Button(action: leadingHeaderAction) {
            Image(systemName: selectedTab == .calendar ? "camera" : "arrow.clockwise")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .background(
                    Circle()
                        .fill(Color.appChip(colorScheme))
                )
        }
        .buttonStyle(.plain)
    }
    
    private var searchButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchActive = true
                isSearchFieldFocused = true
            }
        }) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .background(
                    Circle()
                        .fill(Color.appChip(colorScheme))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var headerPrimaryActionButton: some View {
        Button(action: primaryHeaderAction) {
            Image(systemName: selectedTab == .calendar ? "plus" : "square.and.pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color.homeGlassAccent)
                )
        }
        .buttonStyle(.plain)
    }

    private func primaryHeaderAction() {
        if selectedTab == .calendar {
            addEventDate = selectedDate
            showAddEventPopup = true
        } else {
            showNewCompose = true
        }
    }

    private func leadingHeaderAction() {
        if selectedTab == .calendar {
            showPhotoImportDialog = true
        } else {
            Task {
                await refreshCurrentFolder()
            }
        }
    }
    
    @ViewBuilder
    private var contentSection: some View {
        ZStack {
            if selectedTab == .calendar {
                calendarTabContent
            } else {
                emailListView(for: activeMailboxTab)
            }

            if isSearchActive && !trimmedSearchText.isEmpty {
                if selectedTab == .calendar {
                    eventSearchResultsView
                } else {
                    searchResultsView
                }
            }
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

    private var filteredCalendarSearchResults: [TaskItem] {
        let query = trimmedSearchText.lowercased()
        guard !query.isEmpty else { return [] }

        var seenTaskIds: Set<String> = []

        return filterTasksForSelectedTag(taskManager.tasks.values.flatMap { $0 })
            .filter { task in
                guard !task.isDeleted else { return false }
                guard seenTaskIds.insert(task.id).inserted else { return false }

                let tagName = tagManager.tags.first(where: { $0.id == task.tagId })?.name ?? ""
                let searchableText = [
                    task.title,
                    task.description ?? "",
                    task.location ?? "",
                    tagName,
                    task.calendarTitle ?? "",
                    task.emailSubject ?? ""
                ]
                .joined(separator: " ")
                .lowercased()

                return searchableText.contains(query)
            }
            .sorted {
                let lhsDate = eventSearchReferenceDate(for: $0)
                let rhsDate = eventSearchReferenceDate(for: $1)
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    private var eventSearchResultsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if filteredCalendarSearchResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(Color.emailGlassMutedText(colorScheme))

                        Text("No events match \"\(trimmedSearchText)\"")
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 42)
                } else {
                    ForEach(filteredCalendarSearchResults) { task in
                        Button {
                            selectedDate = eventSearchReferenceDate(for: task)
                            selectedTaskForViewing = task
                            activeSheet = .viewTask
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(task.title)
                                        .font(FontManager.geist(size: 15, weight: .semibold))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .multilineTextAlignment(.leading)

                                    Text(eventSearchSubtitle(for: task))
                                        .font(FontManager.geist(size: 12, weight: .regular))
                                        .foregroundColor(Color.emailGlassMutedText(colorScheme))
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 8)

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color.appTextSecondary(colorScheme))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(18)
            .searchResultsCardStyle(colorScheme: colorScheme, cornerRadius: 24)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 90)
        }
        .selinePrimaryPageScroll()
    }
    
    private func mailboxLoadingState(for tab: EmailTab) -> EmailLoadingState {
        emailService.getLoadingState(for: tab.folder)
    }

    private func emailListView(for tab: EmailTab) -> some View {
        let topContent: AnyView? = (isSearchActive || isOverlayPresentation)
            ? nil
            : AnyView(pageTopContent)

        return EmailListByDay(
            daySections: displayedDaySections,
            loadingState: mailboxLoadingState(for: tab),
            presentationStyle: tab == .sent ? .sent : .inbox,
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
            hasMoreEmails: emailService.hasMoreEmails[tab.folder] ?? false,
            onLoadMore: {
                await emailService.loadMoreEmails(for: tab.folder)
            }
        )
    }

    private func refreshHubState() {
        hubState.updateInputs(
            selectedTab: selectedTab,
            selectedCategory: selectedCategory,
            selectedContextFilter: selectedContextChipFilter
        )
    }

    private func clearSearch() {
        emailSearchDebouncer.cancel()
        isSearchActive = false
        isSearchFieldFocused = false
        searchText = ""
        emailService.searchResults = []
    }

    private func scheduleAvatarPrefetch(for emails: [Email]) {
        guard isVisible else { return }
        avatarPrefetchTask?.cancel()

        let senderEmails = Array(
            Set(
                emails
                    .map { $0.sender.email.lowercased() }
                    .filter { !$0.isEmpty }
            )
        )
        .prefix(18)

        guard !senderEmails.isEmpty else { return }

        avatarPrefetchTask = Task(priority: .utility) {
            for senderEmail in senderEmails {
                guard !Task.isCancelled else { return }

                let cacheKey = CacheManager.CacheKey.emailProfilePicture(senderEmail)
                if let _: String = CacheManager.shared.get(forKey: cacheKey) {
                    continue
                }

                _ = try? await GmailAPIClient.shared.fetchProfilePicture(for: senderEmail)
            }
        }
    }

    private func openEmailDetail(_ email: Email) {
        navigationPath.append(email)
    }
    
    private func refreshCurrentFolder() async {
        await prepareCurrentFolderForDisplay(
            folder: selectedTab.folder,
            forceRefresh: true,
            reason: "pull_to_refresh"
        )
        pageRefreshCoordinator.markValidated(.plan)
    }

    private func prepareCurrentFolderForDisplay(
        folder: EmailFolder,
        forceRefresh: Bool = false,
        reason: String
    ) async {
        let currentEmails = emailService.getEmails(for: folder)
        let currentLoadingState = emailService.getLoadingState(for: folder)
        let secondsSinceLastLoad = lastFolderLoadAt[folder].map { Date().timeIntervalSince($0) } ?? .infinity

        let shouldLoadFolder: Bool
        switch currentLoadingState {
        case .idle, .error:
            shouldLoadFolder = true
        case .loading:
            shouldLoadFolder = false
        case .loaded:
            shouldLoadFolder = forceRefresh || currentEmails.isEmpty || secondsSinceLastLoad >= folderRefreshInterval
        }

        if shouldLoadFolder {
            await emailService.loadEmailsForFolder(folder, forceRefresh: forceRefresh)
            lastFolderLoadAt[folder] = Date()
        }

        if isVisible {
            scheduleAvatarPrefetch(for: emailService.getEmails(for: folder))
        }
    }

    @MainActor
    private func handleVisibilityChange(_ visible: Bool, reason: String) {
        guard visible else {
            emailSearchDebouncer.cancel()
            avatarPrefetchTask?.cancel()
            return
        }

        pageRefreshCoordinator.pageBecameVisible(.plan)

        Task {
            emailService.notificationService.clearEmailNotifications()

            if selectedTab == .calendar {
                refreshHubState()
            } else if pageRefreshCoordinator.shouldRevalidate(
                .plan,
                maxAge: pageRefreshCoordinator.defaultMaxAge(for: .plan)
            ) {
                await prepareCurrentFolderForDisplay(folder: selectedTab.folder, reason: reason)
                pageRefreshCoordinator.markValidated(.plan)
            } else {
                scheduleAvatarPrefetch(for: emailService.getEmails(for: selectedTab.folder))
            }

            refreshHubState()

            let unreadCount = emailService.inboxEmails.filter { !$0.isRead }.count
            emailService.notificationService.updateAppBadge(count: unreadCount)
        }
    }

    // MARK: - Calendar Tab Content

    private var calendarTabContent: some View {
        monthViewContent
    }

    private var calendarHeaderFilterStrip: some View {
        calendarFilterButtonsContent(horizontalPadding: 0, verticalPadding: 2)
            .hideScrollContentInsetIfAvailable()
    }

    private func calendarFilterButtonsContent(horizontalPadding: CGFloat, verticalPadding: CGFloat) -> some View {
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
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
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
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 14) {
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
        .selinePrimaryPageScroll()
    }

    @ViewBuilder
    private var pageTopContent: some View {
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                if selectedTab == .inbox {
                    inboxContextStrip
                } else if selectedTab == .sent {
                    sentContextStrip
                }
            }
        )
    }

    private var shouldShowOverlayFloatingComposeButton: Bool {
        isOverlayPresentation &&
        navigationPath.isEmpty &&
        !isSearchActive
    }

    private var overlayFloatingComposeButton: some View {
        Button(action: primaryHeaderAction) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.black)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.homeGlassAccent)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedTab == .calendar ? "Add event" : "Compose email")
    }

    private var inboxContextStrip: some View {
        pageContextStrip(
            title: "Focus",
            summary: inboxTodaySummary,
            chips: [
                ContextChipItem(title: "Today \(todayInboxCount)", filter: .inboxToday),
                ContextChipItem(title: "Action \(inboxActionRequiredCount)", filter: .inboxAction),
                ContextChipItem(title: "Unread \(inboxUnreadCount)", filter: .inboxUnread)
            ]
        )
    }

    private var sentContextStrip: some View {
        pageContextStrip(
            title: "Momentum",
            summary: sentAwaitingReplyCount == 0
                ? "Recent sends are moving cleanly, so the outbox reads more like a record than a backlog."
                : "A few sent threads now look like they are waiting on someone else, so this view is best for follow-up checks.",
            chips: [
                ContextChipItem(title: "Today \(sentTodayCount)", filter: .sentToday),
                ContextChipItem(title: "Week \(sentThisWeekCount)", filter: .sentWeek),
                ContextChipItem(title: "Waiting \(sentAwaitingReplyCount)", filter: .sentWaiting)
            ]
        )
    }

    private func pageContextStrip(title: String, summary: String, chips: [ContextChipItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(Color.emailGlassMutedText(colorScheme))

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        contextChip(chip)
                    }
                }
            }

            Text(summary)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topLeading,
            cornerRadius: 22,
            highlightStrength: 0.34
        )
    }

    private func contextChip(_ chip: ContextChipItem) -> some View {
        let isSelected = selectedContextChipFilter == chip.filter

        return Button(action: {
            HapticManager.shared.selection()
            if selectedContextChipFilter == chip.filter {
                selectedContextChipFilter = nil
            } else {
                selectedContextChipFilter = chip.filter
            }
        }) {
            Text(chip.title)
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(
                    isSelected
                        ? (colorScheme == .dark ? Color.black : Color.white)
                        : Color.appTextPrimary(colorScheme)
                )
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? (colorScheme == .dark ? Color.white.opacity(0.92) : Color.appTextPrimary(colorScheme))
                                : Color.appChip(colorScheme)
                        )
                )
                .overlay(
                    Capsule()
                        .stroke(Color.appBorder(colorScheme), lineWidth: isSelected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func defaultContextFilter(
        for tab: EmailTab,
        current: EmailHubState.ContextFilter?
    ) -> EmailHubState.ContextFilter? {
        guard let current else { return nil }

        switch (tab, current) {
        case (.inbox, .inboxToday), (.inbox, .inboxAction), (.inbox, .inboxUnread):
            return current
        case (.sent, .sentToday), (.sent, .sentWeek), (.sent, .sentWaiting):
            return current
        default:
            return nil
        }
    }

    private func eventSearchReferenceDate(for task: TaskItem) -> Date {
        if let targetDate = task.targetDate {
            return Calendar.current.startOfDay(for: targetDate)
        }
        return task.weekday.dateForCurrentWeek()
    }

    private func eventSearchSubtitle(for task: TaskItem) -> String {
        let dateText = FormatterCache.weekdayShortMonthDay.string(from: eventSearchReferenceDate(for: task))
        let timeText = task.scheduledTime.map { FormatterCache.shortTime.string(from: $0) } ?? "All day"

        if let location = task.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            return "\(dateText) · \(timeText) · \(location)"
        }

        if let description = task.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            return "\(dateText) · \(timeText) · \(description)"
        }

        return "\(dateText) · \(timeText)"
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

    private func isSyncedCalendarTask(_ task: TaskItem) -> Bool {
        task.id.hasPrefix("cal_")
            || task.isFromCalendar
            || task.calendarEventId != nil
            || task.tagId == "cal_sync"
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
            type: .plan,
            identifier: "email-main",
            metadata: ["category": "communication"]
        ))

        // Add time period content
        items.append(SearchableItem(
            title: "Morning Emails",
            content: "View emails from morning hours (6:00 AM - 11:59 AM). Stay on top of morning communications and start your day organized.",
            type: .plan,
            identifier: "email-morning",
            metadata: ["timePeriod": "morning", "priority": "high"]
        ))

        items.append(SearchableItem(
            title: "Afternoon Emails",
            content: "View emails from afternoon hours (12:00 PM - 4:59 PM). Manage your midday communications and follow up on important messages.",
            type: .plan,
            identifier: "email-afternoon",
            metadata: ["timePeriod": "afternoon", "priority": "medium"]
        ))

        items.append(SearchableItem(
            title: "Night Emails",
            content: "View emails from evening and night hours (5:00 PM - 5:59 AM). Catch up on end-of-day communications.",
            type: .plan,
            identifier: "email-night",
            metadata: ["timePeriod": "night", "priority": "low"]
        ))

        // Add search functionality
        items.append(SearchableItem(
            title: "Search Emails",
            content: "Search through your emails to find specific messages, senders, or content. Quick and powerful email search.",
            type: .plan,
            identifier: "email-search",
            metadata: ["feature": "search", "scope": "emails"]
        ))

        // Add dynamic content from actual emails
        for email in emailService.inboxEmails + emailService.sentEmails {
            items.append(SearchableItem(
                title: email.subject,
                content: "\(email.sender.displayName): \(email.snippet)",
                type: .plan,
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
    PlanView(selectedTab: .constant(.inbox))
        .environmentObject(AuthenticationManager.shared)
}
