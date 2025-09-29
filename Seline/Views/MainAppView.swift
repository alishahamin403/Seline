import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var emailService = EmailService.shared
    @StateObject private var taskManager = TaskManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: TabSelection = .home
    @State private var keyboardHeight: CGFloat = 0

    private var unreadEmailCount: Int {
        emailService.inboxEmails.filter { !$0.isRead }.count
    }

    private var todayTaskCount: Int {
        // Get today's weekday
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: Date())

        // Convert to WeekDay enum (1 = Sunday, 2 = Monday, etc.)
        let weekDay: WeekDay
        switch todayWeekday {
        case 1: weekDay = .sunday
        case 2: weekDay = .monday
        case 3: weekDay = .tuesday
        case 4: weekDay = .wednesday
        case 5: weekDay = .thursday
        case 6: weekDay = .friday
        case 7: weekDay = .saturday
        default: weekDay = .monday
        }

        return taskManager.getTasks(for: weekDay).count
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
                        NotesPlaceholderView()
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

    // MARK: - Home Content
    private var homeContent: some View {
        VStack(spacing: 0) {
            // Fixed Header
            HeaderSection(selectedTab: $selectedTab)

            // Content with keyboard-aware layout
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Sun/Moon time tracker - moved as high as possible
                    SunMoonTimeTracker()
                        .padding(.horizontal, 0) // Remove horizontal padding to span full width
                        .padding(.top, -20) // Negative padding to move closer to header

                    // Minimal spacing after tracker to move sections higher
                    Spacer()
                        .frame(height: 8)

                    // 5 sections in vertical layout with separator lines
                    VStack(spacing: 0) {
                        HomeSectionButton(title: "EMAIL", unreadCount: unreadEmailCount)

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 2)
                            .padding(.vertical, 16)
                            .padding(.horizontal, -20) // Extend to screen edges

                        HomeSectionButton(title: "EVENTS", unreadCount: todayTaskCount)

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 2)
                            .padding(.vertical, 16)
                            .padding(.horizontal, -20) // Extend to screen edges

                        HomeSectionButton(title: "NOTES")

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 2)
                            .padding(.vertical, 16)
                            .padding(.horizontal, -20) // Extend to screen edges

                        HomeSectionButton(title: "MAPS")

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                            .frame(height: 2)
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