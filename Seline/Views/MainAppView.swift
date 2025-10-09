import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: TabSelection = .home
    @State private var keyboardHeight: CGFloat = 0
    @State private var selectedNoteToOpen: Note? = nil
    @State private var showingNewNoteSheet = false
    @State private var showingAddEventPopup = false
    @State private var showingSearch = false
    @State private var searchBarOffset: CGFloat = -100
    @State private var searchSelectedNote: Note? = nil
    @State private var searchSelectedEmail: Email? = nil
    @State private var searchSelectedTask: TaskItem? = nil
    @State private var showingEditTask = false
    @State private var notificationEmailId: String? = nil
    @State private var notificationTaskId: String? = nil

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

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case .home:
                        NavigationView {
                            homeContent
                        }
                        .navigationViewStyle(StackNavigationViewStyle())
                        .navigationBarHidden(true)
                    case .email:
                        EmailView()
                    case .events:
                        EventsView()
                    case .notes:
                        NotesView()
                    case .maps:
                        MapsViewNew()
                    }
                }

                // Fixed Footer - hide when keyboard appears
                if keyboardHeight == 0 {
                    BottomTabBar(selectedTab: $selectedTab)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(
                colorScheme == .dark ?
                    Color.gmailDarkBackground : Color.white
            )
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
            .overlay {
                if showingAddEventPopup {
                    AddEventPopupView(
                        isPresented: $showingAddEventPopup,
                        onSave: { title, description, date, time, reminder, recurring, frequency in
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
                                targetDate: date,
                                reminderTime: reminder,
                                isRecurring: recurring,
                                recurrenceFrequency: frequency
                            )
                        }
                    )
                    .transition(.opacity)
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
                        selectedTab = .email
                        // Optional: Add slight delay to show tab switch
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // This will trigger navigation to email detail view
                            // The email view will handle showing the specific email
                        }
                    }) {
                        HStack(spacing: 8) {
                            // Avatar circle with blue background and icon
                            Circle()
                                .fill(colorScheme == .dark ?
                                    Color(red: 0.40, green: 0.65, blue: 0.80) :
                                    Color(red: 0.20, green: 0.34, blue: 0.40))
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

    // MARK: - Home Content
    private var homeContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Fixed Header
                HeaderSection(selectedTab: $selectedTab)
                    .padding(.bottom, 16)

                // Fixed content (non-scrollable)
                VStack(spacing: 12) {
                    // Weather widget - only fetch when on home tab
                    WeatherWidget(isVisible: selectedTab == .home)

                    // News carousel
                    NewsCarouselView()

                    // Events card
                    EventsCardWidget(showingAddEventPopup: $showingAddEventPopup)

                    // 60/40 split: Unread Emails and Pinned Notes
                    GeometryReader { geometry in
                        HStack(spacing: 8) {
                            // Unread Emails card (60%)
                            EmailCardWidget(selectedTab: $selectedTab)
                                .frame(width: (geometry.size.width - 8) * 0.6)

                            // Pinned Notes card (40%)
                            NotesCardWidget(selectedNoteToOpen: $selectedNoteToOpen, showingNewNoteSheet: $showingNewNoteSheet)
                                .frame(width: (geometry.size.width - 8) * 0.4)
                        }
                    }
                    .frame(height: 200)
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: .infinity, alignment: .top)

                Spacer()
            }
            .background(
                colorScheme == .dark ?
                    Color.gmailDarkBackground : Color.white
            )
            .gesture(
                DragGesture(minimumDistance: 30, coordinateSpace: .local)
                    .onChanged { value in
                        // Track the drag to animate search bar
                        if value.translation.height > 0 && value.translation.height < 200 {
                            searchBarOffset = -100 + value.translation.height
                        }
                    }
                    .onEnded { value in
                        // Swipe down to search
                        if value.translation.height > 100 && value.translation.height > abs(value.translation.width) {
                            HapticManager.shared.selection()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                showingSearch = true
                                searchBarOffset = 0
                            }
                        } else {
                            // Reset if not enough swipe
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                searchBarOffset = -100
                            }
                        }
                    }
            )
            .overlay(alignment: .top) {
                if showingSearch || searchBarOffset > -100 {
                    ZStack {
                        // Semi-transparent background
                        if showingSearch {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        showingSearch = false
                                        searchBarOffset = -100
                                    }
                                }
                        }

                        // Search bar at top
                        VStack(spacing: 0) {
                            SearchOverlayBar(
                                isPresented: $showingSearch,
                                selectedTab: $selectedTab,
                                selectedNote: $searchSelectedNote,
                                selectedEmail: $searchSelectedEmail,
                                selectedTask: $searchSelectedTask,
                                onDismiss: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                        showingSearch = false
                                        searchBarOffset = -100
                                    }
                                }
                            )
                            .offset(y: showingSearch ? 0 : searchBarOffset)

                            Spacer()
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

}

#Preview {
    MainAppView()
        .environmentObject(AuthenticationManager.shared)
}