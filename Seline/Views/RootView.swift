import SwiftUI

private struct GlobalScrollEnvironmentModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
        } else {
            content
        }
    }
}

struct RootView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var systemColorScheme

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
        .modifier(GlobalScrollEnvironmentModifier())
        .preferredColorScheme(themeManager.getPreferredColorScheme())
        .task {
            // When in auto mode, sync with actual system color scheme
            if themeManager.selectedTheme == .auto {
                themeManager.systemColorScheme = systemColorScheme
            }

            await MainActor.run {
                ScrollExperienceConfigurator.applyToVisibleScrollViews()
            }
        }
        .onChange(of: systemColorScheme) { newScheme in
            // Keep ThemeManager in sync when system appearance changes (only in auto mode)
            if themeManager.selectedTheme == .auto {
                themeManager.systemColorScheme = newScheme
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AuthenticationManager.shared)
}
