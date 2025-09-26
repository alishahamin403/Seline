import SwiftUI

struct RootView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainAppView()
            } else {
                AuthenticationView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
        .preferredColorScheme(themeManager.selectedTheme.colorScheme)
    }
}

#Preview {
    RootView()
        .environmentObject(AuthenticationManager.shared)
}