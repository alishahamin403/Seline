import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: TabSelection = .home
    @State private var keyboardHeight: CGFloat = 0

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
                        MapsPlaceholderView()
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
        }
    }

    // MARK: - Detail Content

    private var emailDetailContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            let unreadEmails = emailService.inboxEmails.filter { !$0.isRead }.prefix(5)

            if unreadEmails.isEmpty {
                Text("No unread emails")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(Array(unreadEmails.enumerated()), id: \.element.id) { index, email in
                    Button(action: {
                        selectedTab = .email
                        // Optional: Add slight delay to show tab switch
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // This will trigger navigation to email detail view
                            // The email view will handle showing the specific email
                        }
                    }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(email.subject)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Text("from \(email.sender.displayName)")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)
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
                            .font(.system(size: 14, weight: .regular))
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
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(todayTasks.prefix(5)) { task in
                    Button(action: {
                        selectedTab = .events
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundColor(task.isCompleted ?
                                    (colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                )

                            Text(task.title)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .strikethrough(task.isCompleted, color: colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            if let scheduledTime = task.scheduledTime {
                                Text(formatTime(scheduledTime))
                                    .font(.system(size: 13, weight: .regular))
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
                            .font(.system(size: 14, weight: .regular))
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
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            } else {
                ForEach(pinnedNotes.prefix(5)) { note in
                    Button(action: {
                        selectedTab = .notes
                    }) {
                        HStack(spacing: 6) {
                            Text(note.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            Text(note.formattedDateModified)
                                .font(.system(size: 12, weight: .regular))
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
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Home Content
    private var homeContent: some View {
        VStack(spacing: 0) {
            // Fixed Header
            HeaderSection(selectedTab: $selectedTab)

            // Content with keyboard-aware layout
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {

                    // 5 sections in vertical layout with separator lines
                    VStack(spacing: 0) {
                        HomeSectionButton(title: "EMAIL", unreadCount: unreadEmailCount) {
                            AnyView(emailDetailContent)
                        }

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 1)
                            .padding(.vertical, 16)
                            .padding(.horizontal, -20) // Extend to screen edges

                        HomeSectionButton(title: "EVENTS", unreadCount: todayTaskCount) {
                            AnyView(eventsDetailContent)
                        }

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 1)
                            .padding(.vertical, 16)
                            .padding(.horizontal, -20) // Extend to screen edges

                        HomeSectionButton(title: "NOTES", unreadCount: pinnedNotesCount) {
                            AnyView(notesDetailContent)
                        }

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 1)
                            .padding(.vertical, 16)
                            .padding(.horizontal, -20) // Extend to screen edges

                        HomeSectionButton(title: "LOCATIONS")

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 1)
                            .padding(.vertical, 16)
                            .padding(.horizontal, -20) // Extend to screen edges

                        FunFactSection()
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                        .frame(height: 100)
                }
                .animation(.easeInOut(duration: 0.3), value: keyboardHeight)
            }
            .background(
                colorScheme == .dark ?
                    Color.gmailDarkBackground : Color.white
            )
        }
    }

}

#Preview {
    MainAppView()
        .environmentObject(AuthenticationManager.shared)
}