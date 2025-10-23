import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var notificationService = NotificationService.shared
    @Environment(\.colorScheme) var colorScheme

    // Computed property to get current theme state
    private var isDarkMode: Bool {
        themeManager.getCurrentEffectiveColorScheme() == .dark
    }

    // Settings states
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // User Profile Header Section
                    profileHeaderSection
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .background(isDarkMode ? Color(UIColor.systemGray6).opacity(0.3) : Color(UIColor.systemGray6).opacity(0.5))

                    // Settings Menu Items
                    VStack(spacing: 0) {
                        // Notifications Toggle
                        HStack(spacing: 16) {
                            Image(systemName: "bell")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .frame(width: 24)

                            Text("Notifications")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white : .black)

                            Spacer()

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
                                            notificationService.openAppSettings()
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(isDarkMode ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                        Divider()
                            .padding(.leading, 50)

                        // Appearance Menu
                        HStack(spacing: 16) {
                            Image(systemName: "eye")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .frame(width: 24)

                            Text("Appearance")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white : .black)

                            Spacer()

                            Menu {
                                ForEach(AppTheme.allCases, id: \.self) { theme in
                                    Button {
                                        themeManager.setTheme(theme)
                                    } label: {
                                        HStack {
                                            Image(systemName: theme.icon)
                                            Text(theme.displayName)
                                            if themeManager.selectedTheme == theme {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: themeManager.selectedTheme.icon)
                                        .font(.system(size: 14))
                                    Text(themeManager.selectedTheme.displayName)
                                        .font(.system(size: 14))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.gray.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                        Divider()
                            .padding(.leading, 50)

                        settingsMenuItemLogout
                    }
                    .padding(.vertical, 12)

                    Spacer(minLength: 50)
                }
            }
        }
        .background(isDarkMode ? Color.gmailDarkBackground : Color.white)
        .task {
            await notificationService.checkAuthorizationStatus()
            notificationsEnabled = notificationService.isAuthorized
        }
    }

    // MARK: - Profile Header Section
    private var profileHeaderSection: some View {
        HStack(spacing: 16) {
            // User Avatar with initials
            Circle()
                .fill(isDarkMode ? Color.white : Color.black)
                .overlay(
                    Text({
                        if let name = authManager.currentUser?.profile?.name, let firstChar = name.first {
                            return String(firstChar).uppercased()
                        } else {
                            return "U"
                        }
                    }())
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isDarkMode ? .black : .white)
                )
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                // User Name
                Text(authManager.currentUser?.profile?.name ?? "User")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isDarkMode ? .white : .black)

                // User Email
                Text(authManager.currentUser?.profile?.email ?? "No email")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
    }

    // MARK: - Logout Menu Item
    private var settingsMenuItemLogout: some View {
        Button(action: {
            Task {
                await authManager.signOut()
            }
        }) {
            HStack(spacing: 16) {
                Image(systemName: "arrow.uturn.left")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.red)
                    .frame(width: 24)

                Text("Logout")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.red)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.red.opacity(0.3))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(AuthenticationManager.shared)
    }
}