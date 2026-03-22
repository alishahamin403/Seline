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

    private var resolvedColorScheme: ColorScheme {
        themeManager.getCurrentEffectiveColorScheme() ?? systemColorScheme
    }

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if #available(iOS 18.0, *) {
                    MainAppView()
                } else {
                    UnsupportedIOSView(colorScheme: resolvedColorScheme) {
                        Task {
                            await authManager.signOut()
                        }
                    }
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

private struct UnsupportedIOSView: View {
    let colorScheme: ColorScheme
    let onSignOut: () -> Void

    var body: some View {
        ZStack {
            AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .centerRight)

            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    Image(systemName: "iphone.slash")
                        .font(FontManager.geist(size: 40, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))

                    Text("Update Required")
                        .font(FontManager.geist(size: 22, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    Text("Seline currently needs iOS 18.0 or newer on this device. Sign in on a supported iPhone to continue using the app.")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }

                Button(action: onSignOut) {
                    Text("Sign Out")
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.homeGlassAccent)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .appAmbientCardStyle(
                colorScheme: colorScheme,
                variant: .centerRight,
                cornerRadius: 28,
                highlightStrength: 0.68
            )
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AuthenticationManager.shared)
}
