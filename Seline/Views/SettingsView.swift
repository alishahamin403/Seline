import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var notificationService = NotificationService.shared
    @Environment(\.colorScheme) var colorScheme

    // Computed property to get current theme state
    private var isDarkMode: Bool {
        themeManager.getCurrentEffectiveColorScheme(systemColorScheme: colorScheme) == .dark
    }

    // Settings states (some are mockup for now)
    @AppStorage("showEmail") private var showEmail = true
    @AppStorage("showNumber") private var showNumber = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(isDarkMode ? .white : .black)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView {
                    VStack(spacing: 32) {
                        // Google Account Info Section
                        googleAccountSection

                        // General Settings Section
                        generalSettingsSection

                        Spacer(minLength: 50)

                        // Sign Out Button at bottom
                        signOutButton

                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .background(isDarkMode ? Color.black : Color.white)
        }
        .navigationBarHidden(true)
        .task {
            await notificationService.checkAuthorizationStatus()
            notificationsEnabled = notificationService.isAuthorized
        }
    }

    // MARK: - Google Account Section
    private var googleAccountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let user = authManager.currentUser {
                HStack(spacing: 16) {
                    // Custom Profile Avatar (always black/white)
                    Circle()
                        .fill(isDarkMode ? Color.white : Color.black)
                        .overlay(
                            Text({
                                if let name = user.profile?.name, let firstChar = name.first {
                                    return String(firstChar).uppercased()
                                } else {
                                    return "U"
                                }
                            }())
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(isDarkMode ? .black : .white)
                        )
                        .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 4) {
                        // User Name
                        Text(user.profile?.name ?? "User")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isDarkMode ? .white : .black)

                        // User Email
                        Text(user.profile?.email ?? "No email")
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? .gray : .gray)
                    }

                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - General Settings Section
    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            Text("General Settings")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isDarkMode ? .white : .black)

            VStack(spacing: 16) {
                // Theme toggle
                SettingsTile(title: "Theme") {
                    HStack(spacing: 8) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Button(action: {
                                themeManager.setTheme(theme)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: theme.icon)
                                        .font(.system(size: 12, weight: .medium))
                                    Text(theme.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(themeManager.selectedTheme == theme ?
                                              (isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.1)) :
                                              Color.clear)
                                )
                                .foregroundColor(themeManager.selectedTheme == theme ?
                                                (isDarkMode ? .white : .black) :
                                                .gray)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // Notification toggle
                SettingsTile(title: "Notification") {
                    Toggle("", isOn: Binding(
                        get: { notificationsEnabled },
                        set: { newValue in
                            if newValue && !notificationService.isAuthorized {
                                Task {
                                    let granted = await notificationService.requestAuthorization()
                                    if granted {
                                        notificationsEnabled = true
                                    }
                                }
                            } else {
                                notificationsEnabled = newValue
                                if !newValue {
                                    // User wants to disable - direct to settings
                                    notificationService.openAppSettings()
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(Color(red: 0.4, green: 0.4, blue: 0.4))
                }
            }
        }
    }

    // MARK: - Sign Out Button
    private var signOutButton: some View {
        Button(action: {
            Task {
                await authManager.signOut()
            }
        }) {
            Text("Sign Out")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isDarkMode ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(isDarkMode ? Color.white : Color.black)
                .cornerRadius(12)
        }
    }

}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(AuthenticationManager.shared)
    }
}