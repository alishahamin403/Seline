import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var searchService = SearchService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: TabSelection = .home
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedNoteToOpen: Note? = nil
    @State private var showingNewNoteSheet = false
    @State private var showingAddEventPopup = false
    @State private var searchText = ""
    @State private var searchSelectedNote: Note? = nil
    @State private var searchSelectedEmail: Email? = nil
    @State private var searchSelectedTask: TaskItem? = nil
    @State private var searchSelectedLocation: SavedPlace? = nil
    @State private var searchSelectedFolder: String? = nil
    @State private var showingEditTask = false
    @State private var notificationEmailId: String? = nil
    @State private var notificationTaskId: String? = nil
    @State private var showingEventConfirmation = false
    @State private var showingNoteConfirmation = false
    @FocusState private var isSearchFocused: Bool
    private var unreadEmailCount: Int {
        emailService.inboxEmails.filter { !$0.isRead }.count
    }

    private var todayTaskCount: Int {
        return taskManager.getTasksForToday().count
    }

    private var pinnedNotesCount: Int {
        return notesManager.pinnedNotes.count
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDateAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatEventDateAndTime(targetDate: Date?, scheduledTime: Date?) -> String {
        guard let targetDate = targetDate else { return "No date set" }
        guard let scheduledTime = scheduledTime else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: targetDate)
        }

        // Combine targetDate (the actual date) with scheduledTime (the time component)
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: scheduledTime)
        if let combinedDateTime = calendar.date(bySettingHour: timeComponents.hour ?? 0,
                                                minute: timeComponents.minute ?? 0,
                                                second: timeComponents.second ?? 0,
                                                of: targetDate) {
            return formatDateAndTime(combinedDateTime)
        }
        return formatDateAndTime(targetDate)
    }

    private var searchResults: [OverlaySearchResult] {
        guard !searchText.isEmpty else { return [] }

        // If there's a pending action (event or note creation), show action UI instead
        if searchService.pendingEventCreation != nil {
            return []
        }
        if searchService.pendingNoteCreation != nil {
            return []
        }

        var results: [OverlaySearchResult] = []
        let lowercasedSearch = searchText.lowercased()

        // Search tasks/events
        let allTasks = taskManager.tasks.values.flatMap { $0 }
        let matchingTasks = allTasks.filter {
            $0.title.lowercased().contains(lowercasedSearch)
        }

        for task in matchingTasks.prefix(5) {
            results.append(OverlaySearchResult(
                type: .event,
                title: task.title,
                subtitle: formatEventDateAndTime(targetDate: task.targetDate, scheduledTime: task.scheduledTime),
                icon: "calendar",
                task: task,
                email: nil,
                note: nil,
                location: nil,
                category: nil
            ))
        }

        // Search emails
        let allEmails = emailService.inboxEmails + emailService.sentEmails
        let matchingEmails = allEmails.filter {
            $0.subject.lowercased().contains(lowercasedSearch) ||
            $0.sender.displayName.lowercased().contains(lowercasedSearch) ||
            $0.snippet.lowercased().contains(lowercasedSearch)
        }

        for email in matchingEmails.prefix(5) {
            results.append(OverlaySearchResult(
                type: .email,
                title: email.subject,
                subtitle: "from \(email.sender.displayName)",
                icon: "envelope",
                task: nil,
                email: email,
                note: nil,
                location: nil,
                category: nil
            ))
        }

        // Search notes
        let matchingNotes = notesManager.notes.filter {
            $0.title.lowercased().contains(lowercasedSearch) ||
            $0.content.lowercased().contains(lowercasedSearch)
        }

        for note in matchingNotes.prefix(5) {
            results.append(OverlaySearchResult(
                type: .note,
                title: note.title,
                subtitle: note.formattedDateModified,
                icon: "note.text",
                task: nil,
                email: nil,
                note: note,
                location: nil,
                category: nil
            ))
        }

        // Search locations
        let locationsManager = LocationsManager.shared
        let matchingLocations = locationsManager.savedPlaces.filter {
            $0.name.lowercased().contains(lowercasedSearch) ||
            $0.address.lowercased().contains(lowercasedSearch) ||
            ($0.customName?.lowercased().contains(lowercasedSearch) ?? false)
        }

        for location in matchingLocations.prefix(5) {
            results.append(OverlaySearchResult(
                type: .location,
                title: location.displayName,
                subtitle: location.address,
                icon: "mappin.circle.fill",
                task: nil,
                email: nil,
                note: nil,
                location: location,
                category: nil
            ))
        }

        return results
    }

    private func handleSearchResultTap(_ result: OverlaySearchResult) {
        HapticManager.shared.selection()

        switch result.type {
        case .note:
            if let note = result.note {
                searchSelectedNote = note
            }
        case .email:
            if let email = result.email {
                searchSelectedEmail = email
            }
        case .event:
            if let task = result.task {
                searchSelectedTask = task
            }
        case .location:
            if let location = result.location {
                GoogleMapsService.shared.openInGoogleMaps(place: location)
            }
            // Dismiss search for locations
            isSearchFocused = false
            searchText = ""
            return
        case .folder:
            if let category = result.category {
                selectedTab = .maps
                searchSelectedFolder = category
            }
        }

        // Dismiss search after setting the state
        isSearchFocused = false
        searchText = ""
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    // Padding to account for fixed header (only on home tab)
                    if selectedTab == .home {
                        Color.clear
                            .frame(height: 48)
                    }

                    // Content based on selected tab - expands to fill available space
                    Group {
                        switch selectedTab {
                        case .home:
                            NavigationView {
                                homeContentWithoutHeader
                            }
                            .navigationViewStyle(StackNavigationViewStyle())
                            .navigationBarHidden(true)
                            .onAppear {
                                Task {
                                    await emailService.loadEmailsForFolder(.inbox)
                                }
                            }
                        case .email:
                            EmailView()
                        case .events:
                            EventsView()
                        case .notes:
                            NotesView()
                        case .maps:
                            MapsViewNew(externalSelectedFolder: $searchSelectedFolder)
                        }
                    }
                    .frame(maxHeight: .infinity)

                    // Fixed Footer - hide when keyboard appears
                    if keyboardHeight == 0 {
                        BottomTabBar(selectedTab: $selectedTab)
                    }

                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(
                    colorScheme == .dark ?
                        Color.black : Color.white
                )

                // Fixed Header with search bar at top (only on home tab)
                if selectedTab == .home {
                    VStack(spacing: 0) {
                        HeaderSection(
                            selectedTab: $selectedTab,
                            searchText: $searchText,
                            isSearchFocused: $isSearchFocused,
                            onSearchSubmit: {
                                // Explicitly trigger search when Enter is pressed
                                Task {
                                    await searchService.performSearch(query: searchText)
                                }
                            }
                        )
                        .padding(.bottom, 8)
                        .background(colorScheme == .dark ? Color.black : Color.white)

                        // Search results or question response dropdown
                        if !searchText.isEmpty {
                            if let response = searchService.questionResponse {
                                // Show question response
                                questionResponseView(response)
                                    .padding(.horizontal, 20)
                                    .transition(.opacity)
                            } else if !searchResults.isEmpty {
                                // Show search results
                                searchResultsDropdown
                                    .padding(.horizontal, 20)
                                    .transition(.opacity)
                            } else if searchService.isLoadingQuestionResponse {
                                // Show loading indicator for question
                                loadingQuestionView
                                    .padding(.horizontal, 20)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .background(colorScheme == .dark ? Color.black : Color.white)
                    .zIndex(100)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(
                colorScheme == .dark ?
                    Color.black : Color.white
            )
            .onAppear {
                // Pre-load location services for Maps tab
                locationService.requestLocationPermission()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                    keyboardHeight = keyboardFrame.cgRectValue.height
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardHeight = 0
            }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToEmail)) { notification in
                handleEmailNotification(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToTask)) { notification in
                handleTaskNotification(notification)
            }
            .sheet(item: $selectedNoteToOpen) { note in
                NoteEditView(note: note, isPresented: Binding<Bool>(
                    get: { selectedNoteToOpen != nil },
                    set: { if !$0 { selectedNoteToOpen = nil } }
                ))
            }
            .sheet(isPresented: $showingNewNoteSheet) {
                NoteEditView(note: nil, isPresented: $showingNewNoteSheet)
            }
            .sheet(isPresented: $authManager.showLocationSetup) {
                LocationSetupView()
            }
            .sheet(item: $searchSelectedNote) { note in
                NoteEditView(note: note, isPresented: Binding<Bool>(
                    get: { searchSelectedNote != nil },
                    set: { if !$0 { searchSelectedNote = nil } }
                ))
            }
            .sheet(item: $searchSelectedEmail) { email in
                EmailDetailView(email: email)
            }
            .sheet(item: $searchSelectedTask) { task in
                if showingEditTask {
                    NavigationView {
                        EditTaskView(
                            task: task,
                            onSave: { updatedTask in
                                taskManager.editTask(updatedTask)
                                searchSelectedTask = nil
                                showingEditTask = false
                            },
                            onCancel: {
                                searchSelectedTask = nil
                                showingEditTask = false
                            },
                            onDelete: { taskToDelete in
                                taskManager.deleteTask(taskToDelete)
                                searchSelectedTask = nil
                                showingEditTask = false
                            },
                            onDeleteRecurringSeries: { taskToDelete in
                                taskManager.deleteRecurringTask(taskToDelete)
                                searchSelectedTask = nil
                                showingEditTask = false
                            }
                        )
                    }
                } else {
                    NavigationView {
                        ViewEventView(
                            task: task,
                            onEdit: {
                                showingEditTask = true
                            },
                            onDelete: { taskToDelete in
                                taskManager.deleteTask(taskToDelete)
                                searchSelectedTask = nil
                            },
                            onDeleteRecurringSeries: { taskToDelete in
                                taskManager.deleteRecurringTask(taskToDelete)
                                searchSelectedTask = nil
                            }
                        )
                    }
                }
            }
            .onChange(of: searchSelectedTask) { newValue in
                // Reset showingEditTask when a new task is selected or when dismissed
                if newValue != nil {
                    showingEditTask = false
                } else {
                    showingEditTask = false
                }
            }
            .onChange(of: searchText) { newValue in
                if newValue.isEmpty {
                    // Clear pending actions when search is cleared
                    searchService.cancelAction()
                }
            }
            .onChange(of: searchService.pendingEventCreation) { newValue in
                showingEventConfirmation = newValue != nil
            }
            .onChange(of: searchService.pendingNoteCreation) { newValue in
                showingNoteConfirmation = newValue != nil
            }
            .overlay {
                if showingAddEventPopup {
                    AddEventPopupView(
                        isPresented: $showingAddEventPopup,
                        onSave: { title, description, date, time, endTime, reminder, recurring, frequency, tagId in
                            // Determine the weekday from the selected date
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

                            // Create the task with recurring parameters
                            taskManager.addTask(
                                title: title,
                                to: weekday,
                                description: description,
                                scheduledTime: time,
                                endTime: endTime,
                                targetDate: date,
                                reminderTime: reminder,
                                isRecurring: recurring,
                                recurrenceFrequency: frequency,
                                tagId: tagId
                            )
                        }
                    )
                    .transition(.opacity)
                }
            }
            .sheet(isPresented: $showingEventConfirmation) {
                if let eventData = searchService.pendingEventCreation {
                    ActionEventConfirmationView(
                        eventData: eventData,
                        isPresented: $showingEventConfirmation,
                        onConfirm: {
                            searchService.confirmEventCreation()
                            searchText = ""
                            isSearchFocused = false
                        },
                        onCancel: {
                            searchService.cancelAction()
                        }
                    )
                }
            }
            .sheet(isPresented: $showingNoteConfirmation) {
                if let noteData = searchService.pendingNoteCreation {
                    ActionNoteConfirmationView(
                        noteData: noteData,
                        isPresented: $showingNoteConfirmation,
                        onConfirm: {
                            searchService.confirmNoteCreation()
                            searchText = ""
                            isSearchFocused = false
                        },
                        onCancel: {
                            searchService.cancelAction()
                        }
                    )
                }
            }
        }
    }

    // MARK: - Detail Content

    // Generate an icon based on sender email or name (same logic as EmailRow)
    private func emailIcon(for email: Email) -> String? {
        let senderEmail = email.sender.email.lowercased()
        let senderName = (email.sender.name ?? "").lowercased()
        let sender = senderEmail + " " + senderName

        // Financial/Investing
        if sender.contains("wealthsimple") || sender.contains("robinhood") ||
           sender.contains("questrade") || sender.contains("tdameritrade") ||
           sender.contains("etrade") || sender.contains("fidelity") {
            return "chart.line.uptrend.xyaxis"
        }

        // Banking
        if sender.contains("bank") || sender.contains("chase") || sender.contains("cibc") ||
           sender.contains("rbc") || sender.contains("td") || sender.contains("bmo") ||
           sender.contains("scotiabank") || sender.contains("wellsfargo") ||
           sender.contains("amex") || sender.contains("americanexpress") ||
           sender.contains("american express") {
            return "dollarsign.circle.fill"
        }

        // Shopping/Retail
        if sender.contains("amazon") || sender.contains("ebay") || sender.contains("walmart") ||
           sender.contains("target") || sender.contains("bestbuy") || sender.contains("shopify") ||
           sender.contains("etsy") || sender.contains("aliexpress") {
            return "bag.fill"
        }

        // Travel/Airlines
        if sender.contains("airline") || sender.contains("flight") || sender.contains("expedia") ||
           sender.contains("airbnb") || sender.contains("booking") || sender.contains("hotels") ||
           sender.contains("delta") || sender.contains("united") || sender.contains("aircanada") {
            return "airplane"
        }

        // Food Delivery
        if sender.contains("uber") && sender.contains("eats") || sender.contains("doordash") ||
           sender.contains("grubhub") || sender.contains("skipthedishes") ||
           sender.contains("postmates") || sender.contains("deliveroo") {
            return "fork.knife"
        }

        // Ride Share/Transportation
        if sender.contains("uber") || sender.contains("lyft") || sender.contains("taxi") {
            return "car.fill"
        }

        // Tech/Development
        if sender.contains("github") || sender.contains("gitlab") || sender.contains("bitbucket") {
            return "chevron.left.forwardslash.chevron.right"
        }

        // Social Media - Camera apps
        if sender.contains("snapchat") || sender.contains("instagram") {
            return "camera.fill"
        }

        // Facebook
        if sender.contains("facebook") || sender.contains("meta") {
            return "person.2.fill"
        }

        // LinkedIn
        if sender.contains("linkedin") {
            return "briefcase.fill"
        }

        // Twitter/X
        if sender.contains("twitter") || sender.contains("x.com") {
            return "bubble.left.and.bubble.right.fill"
        }

        // TikTok
        if sender.contains("tiktok") {
            return "music.note"
        }

        // YouTube
        if sender.contains("youtube") {
            return "play.rectangle.fill"
        }

        // Discord
        if sender.contains("discord") {
            return "message.fill"
        }

        // Reddit
        if sender.contains("reddit") {
            return "text.bubble.fill"
        }

        // Google
        if sender.contains("google") || sender.contains("gmail") && !sender.contains("@gmail.com") {
            return "magnifyingglass"
        }

        // Apple
        if sender.contains("apple") || sender.contains("icloud") && !sender.contains("@icloud.com") {
            return "apple.logo"
        }

        // Microsoft
        if sender.contains("microsoft") || sender.contains("outlook") && !sender.contains("@outlook.com") ||
           sender.contains("office365") || sender.contains("teams") {
            return "square.grid.2x2.fill"
        }

        // Amazon
        if sender.contains("amazon") && !sender.contains("shopping") {
            return "shippingbox.fill"
        }

        // Netflix
        if sender.contains("netflix") {
            return "play.tv.fill"
        }

        // Spotify
        if sender.contains("spotify") {
            return "music.note.list"
        }

        // Slack
        if sender.contains("slack") {
            return "number"
        }

        // Zoom
        if sender.contains("zoom") {
            return "video.fill"
        }

        // Dropbox
        if sender.contains("dropbox") {
            return "folder.fill"
        }

        // PayPal/Venmo
        if sender.contains("paypal") || sender.contains("venmo") {
            return "dollarsign.square.fill"
        }

        // News/Media
        if sender.contains("newsletter") || sender.contains("substack") || sender.contains("medium") ||
           sender.contains("nytimes") || sender.contains("news") {
            return "newspaper.fill"
        }

        // Security/Notifications
        if sender.contains("noreply") || sender.contains("no-reply") ||
           sender.contains("notification") || sender.contains("alert") {
            return "bell.fill"
        }

        // Healthcare
        if sender.contains("health") || sender.contains("medical") || sender.contains("doctor") ||
           sender.contains("clinic") || sender.contains("hospital") {
            return "heart.fill"
        }

        // Calendar/Events
        if sender.contains("calendar") || sender.contains("eventbrite") || sender.contains("meetup") {
            return "calendar"
        }

        // Check if it's a personal email (common personal email domains)
        let personalDomains = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com",
                              "icloud.com", "me.com", "aol.com", "protonmail.com"]
        if personalDomains.contains(where: { senderEmail.contains($0) }) {
            return "person.fill"
        }

        // Default to company/building icon for business emails
        return "building.2.fill"
    }

    private var emailDetailContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let unreadEmails = emailService.inboxEmails.filter { !$0.isRead }.prefix(5)

            if unreadEmails.isEmpty {
                Text("No unread emails")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(Array(unreadEmails.enumerated()), id: \.element.id) { index, email in
                    Button(action: {
                        HapticManager.shared.email()
                        searchSelectedEmail = email
                    }) {
                        HStack(spacing: 8) {
                            // Avatar circle with black/white background and icon
                            Circle()
                                .fill(colorScheme == .dark ?
                                    Color.white :
                                    Color.black)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Group {
                                        if let icon = emailIcon(for: email) {
                                            Image(systemName: icon)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                        } else {
                                            Text(email.sender.shortDisplayName.prefix(1).uppercased())
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(email.subject)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Text("from \(email.sender.displayName)")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if emailService.inboxEmails.filter({ !$0.isRead }).count > 5 {
                    Button(action: {
                        selectedTab = .email
                    }) {
                        Text("... and \(emailService.inboxEmails.filter { !$0.isRead }.count - 5) more")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var eventsDetailContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let todayTasks = taskManager.getTasksForToday()

            if todayTasks.isEmpty {
                Text("No events today")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(todayTasks.prefix(5)) { task in
                    Button(action: {
                        HapticManager.shared.calendar()
                        selectedTab = .events
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundColor(task.isCompleted ?
                                    (colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                )

                            Text(task.title)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .strikethrough(task.isCompleted, color: colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            if let scheduledTime = task.scheduledTime {
                                Text(formatTime(scheduledTime))
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if todayTasks.count > 5 {
                    Button(action: {
                        selectedTab = .events
                    }) {
                        Text("... and \(todayTasks.count - 5) more")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var notesDetailContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let pinnedNotes = notesManager.pinnedNotes

            if pinnedNotes.isEmpty {
                Text("No pinned notes")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(pinnedNotes.prefix(5)) { note in
                    Button(action: {
                        HapticManager.shared.cardTap()
                        selectedNoteToOpen = note
                    }) {
                        HStack(spacing: 6) {
                            Text(note.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            Text(note.formattedDateModified)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if pinnedNotes.count > 5 {
                    Button(action: {
                        selectedTab = .notes
                    }) {
                        Text("... and \(pinnedNotes.count - 5) more")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Notification Handlers

    private func handleEmailNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let emailId = userInfo["emailId"] as? String else {
            // No specific email ID, just navigate to email tab
            selectedTab = .email
            return
        }

        // Find the email and show it
        if let email = emailService.inboxEmails.first(where: { $0.id == emailId }) {
            selectedTab = .email
            // Delay slightly to ensure tab is switched before showing email detail
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                searchSelectedEmail = email
            }
        } else {
            // Email not found, just navigate to email tab
            selectedTab = .email
        }
    }

    private func handleTaskNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let taskId = userInfo["taskId"] as? String else {
            // No specific task ID, just navigate to events tab
            selectedTab = .events
            return
        }

        // Find the task by searching through all weekdays
        var foundTask: TaskItem? = nil
        for (_, tasks) in taskManager.tasks {
            if let task = tasks.first(where: { $0.id == taskId }) {
                foundTask = task
                break
            }
        }

        if let task = foundTask {
            selectedTab = .events
            // Delay slightly to ensure tab is switched before showing task detail
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                searchSelectedTask = task
                showingEditTask = false // Show in read mode
            }
        } else {
            // Task not found, just navigate to events tab
            selectedTab = .events
        }
    }

    // MARK: - Search Bar Components

    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

            TextField("Search or ask for actions...", text: $searchText)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                .focused($isSearchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit {
                    // Process the search query when user taps search button
                    if !searchText.isEmpty {
                        let queryType = QueryRouter.shared.classifyQuery(searchText)
                        switch queryType {
                        case .action(let actionType):
                            switch actionType {
                            case .createEvent:
                                let actionHandler = ActionQueryHandler.shared
                                Task {
                                    searchService.pendingEventCreation = await actionHandler.parseEventCreation(from: searchText)
                                }
                            case .createNote:
                                let actionHandler = ActionQueryHandler.shared
                                searchService.pendingNoteCreation = actionHandler.parseNoteCreation(from: searchText)
                            default:
                                break
                            }
                        default:
                            // For questions and searches, keep the normal behavior
                            break
                        }
                    }
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            colorScheme == .dark ?
                Color(red: 0.15, green: 0.15, blue: 0.15) :
                Color(red: 0.95, green: 0.95, blue: 0.95)
        )
    }

    private var searchResultsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if searchResults.isEmpty {
                        Text("No results found")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(searchResults) { result in
                            searchResultRow(for: result)
                        }
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 300)
        }
        .background(
            colorScheme == .dark ?
                Color(red: 0.15, green: 0.15, blue: 0.15) :
                Color(red: 0.95, green: 0.95, blue: 0.95)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private func searchResultRow(for result: OverlaySearchResult) -> some View {
        Button(action: {
            handleSearchResultTap(result)
        }) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: result.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    .frame(width: 24)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .lineLimit(1)

                    Text(result.subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .lineLimit(1)
                }

                Spacer()

                // Type badge
                Text(result.type.rawValue.capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.black.opacity(0.05)
                    )
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                colorScheme == .dark ?
                    Color.white.opacity(0.03) :
                    Color.black.opacity(0.02)
            )
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var searchBarContainer: some View {
        VStack(spacing: 0) {
            searchBarView

            if !searchText.isEmpty {
                searchResultsDropdown
                    .transition(.opacity)
            }
        }
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(!searchText.isEmpty ? 0.15 : 0.05), radius: !searchText.isEmpty ? 12 : 4, x: 0, y: !searchText.isEmpty ? 6 : 2)
        .padding(.horizontal, 12)
        .zIndex(100)
        .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
    }

    private var mainContentWidgets: some View {
        VStack(spacing: 12) {
            // Weather widget - only fetch when on home tab
            WeatherWidget(isVisible: selectedTab == .home)

            // News carousel
            NewsCarouselView()

            // Events card
            EventsCardWidget(showingAddEventPopup: $showingAddEventPopup)

            // 60/40 split: Unread Emails and Pinned Notes
            emailAndNotesCards
        }
    }

    private var emailAndNotesCards: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                // Unread Emails card (60%)
                EmailCardWidget(selectedTab: $selectedTab, selectedEmail: $searchSelectedEmail)
                    .frame(width: (geometry.size.width - 8) * 0.6)

                // Pinned Notes card (40%)
                NotesCardWidget(selectedNoteToOpen: $selectedNoteToOpen, showingNewNoteSheet: $showingNewNoteSheet)
                    .frame(width: (geometry.size.width - 8) * 0.4)
            }
        }
        .frame(height: 140)
        .padding(.horizontal, 12)
    }

    // MARK: - Home Content
    private var homeContentWithoutHeader: some View {
        VStack(spacing: 0) {
            // Main content - fixed, no scrolling at page level
            ZStack(alignment: .top) {
                mainContentWidgets
                    .opacity(searchText.isEmpty ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)

                // Overlay to dismiss search when tapping outside
                if !searchText.isEmpty {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isSearchFocused = false
                            searchText = ""
                        }
                }
            }

            Spacer()
        }
        .background(
            colorScheme == .dark ?
                Color.black : Color.white
        )
    }

    // MARK: - Question Response View

    private func questionResponseView(_ response: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(response)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            colorScheme == .dark ?
                Color(red: 0.15, green: 0.15, blue: 0.15) :
                Color(red: 0.95, green: 0.95, blue: 0.95)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private var loadingQuestionView: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8, anchor: .center)

                Text("Thinking...")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
        .background(
            colorScheme == .dark ?
                Color(red: 0.15, green: 0.15, blue: 0.15) :
                Color(red: 0.95, green: 0.95, blue: 0.95)
        )
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

}

#Preview {
    MainAppView()
        .environmentObject(AuthenticationManager.shared)
}