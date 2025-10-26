import SwiftUI

struct RootView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject var themeManager = ThemeManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if #available(iOS 18.0, *) {
                    MainAppView()
                } else {
                    // Fallback for older iOS versions
                    Text("iOS 18.0 or newer is required")
                }
            } else {
                AuthenticationView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
        .preferredColorScheme(themeManager.effectiveColorScheme)
    }
}

#Preview {
    RootView()
        .environmentObject(AuthenticationManager.shared)
}