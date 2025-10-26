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
    @State private var showingFeedback = false
    @State private var showClearCacheConfirmation = false
    @State private var cacheCleared = false

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

                        // Feedback Button
                        Button(action: { showingFeedback = true }) {
                            HStack(spacing: 16) {
                                Image(systemName: "bubble.right")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                    .frame(width: 24)

                                Text("Send Feedback")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .white : .black)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.gray.opacity(0.3))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }

                        Divider()
                            .padding(.leading, 50)

                        // Clear Calendar Sync Cache Button
                        Button(action: { showClearCacheConfirmation = true }) {
                            HStack(spacing: 16) {
                                Image(systemName: "trash")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .red.opacity(0.7) : .red.opacity(0.7))
                                    .frame(width: 24)

                                Text("Clear Calendar Sync Cache")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .red.opacity(0.7) : .red.opacity(0.7))

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.gray.opacity(0.3))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }

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
        .sheet(isPresented: $showingFeedback) {
            FeedbackView()
        }
        .confirmationDialog(
            "Clear Calendar Sync Cache?",
            isPresented: $showClearCacheConfirmation,
            actions: {
                Button("Clear Cache", role: .destructive) {
                    clearCalendarSyncCache()
                    cacheCleared = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        cacheCleared = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("This will delete the local cache of synced calendar events. The app will re-fetch from your iPhone calendar on the next launch.\n\nContinue?")
            }
        )
        .overlay(alignment: .bottom) {
            if cacheCleared {
                VStack {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Calendar sync cache cleared!")
                            .foregroundColor(.green)
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                    .padding()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task {
            await notificationService.checkAuthorizationStatus()
            notificationsEnabled = notificationService.isAuthorized
        }
    }

    // MARK: - Clear Calendar Sync Cache
    private func clearCalendarSyncCache() {
        CalendarSyncService.shared.clearSyncTracking()
        print("✅ Calendar sync cache cleared from Settings")
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