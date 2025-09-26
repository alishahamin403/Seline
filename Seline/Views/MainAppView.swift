import SwiftUI

struct MainAppView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedTab: TabSelection = .home
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Content based on selected tab
                    Group {
                        switch selectedTab {
                        case .home:
                            homeContent
                        case .email:
                            EmailPlaceholderView()
                        case .events:
                            EventsPlaceholderView()
                        case .notes:
                            NotesPlaceholderView()
                        case .maps:
                            MapsPlaceholderView()
                        }
                    }

                    // Fixed Footer
                    BottomTabBar(selectedTab: $selectedTab)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(
                    colorScheme == .dark ?
                        Color.black : Color.white
                )
                .ignoresSafeArea(.keyboard, edges: .bottom)
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
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Home Content
    private var homeContent: some View {
        VStack(spacing: 0) {
            // Fixed Header
            HeaderSection(selectedTab: $selectedTab)

            // Content with keyboard-aware layout
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    // Search bar - always stays at top
                    SearchBarComponent(selectedTab: $selectedTab)

                    // Show other content only when keyboard is not active
                    if keyboardHeight == 0 {
                        // Weather widget
                        WeatherWidget()

                        // Extra spacing to push content lower
                        Spacer()
                            .frame(height: 30)

                        // Sun/Moon time tracker
                        SunMoonTimeTracker()
                            .padding(.vertical, 12)

                        // 4 Metric tiles horizontally
                        HStack(spacing: 12) {
                            MetricTile(
                                icon: "envelope",
                                title: "Emails",
                                subtitle: "",
                                value: "12"
                            )

                            MetricTile(
                                icon: "calendar",
                                title: "Events",
                                subtitle: "",
                                value: "3"
                            )

                            MetricTile(
                                icon: "map",
                                title: "Maps",
                                subtitle: "",
                                value: "5"
                            )

                            MetricTile(
                                icon: "note.text",
                                title: "Notes",
                                subtitle: "",
                                value: "8"
                            )
                        }
                        .padding(.horizontal, 20)

                        // Smaller spacing before tips card
                        Spacer()
                            .frame(height: 20)

                        // Tips card
                        TipsCard()
                    }

                    Spacer()
                        .frame(height: keyboardHeight > 0 ? 50 : 100)
                }
                .padding(.top, 10)
                .animation(.easeInOut(duration: 0.3), value: keyboardHeight)
            }
            .background(
                colorScheme == .dark ?
                    Color.black : Color.white
            )
        }
    }

}

#Preview {
    MainAppView()
        .environmentObject(AuthenticationManager.shared)
}