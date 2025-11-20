import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject var themeManager = ThemeManager.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var geofenceManager = GeofenceManager.shared

    // Computed property to get current theme state
    private var isDarkMode: Bool {
        themeManager.effectiveColorScheme == .dark
    }

    // Settings states
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("locationTrackingMode") private var locationTrackingMode = "active" // "active" or "background"
    @State private var showingFeedback = false
    @State private var showingLocationInfo = false
    @State private var cacheSize: Double = 0
    @State private var isShowingClearCacheAlert = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // User Profile Header Section
                    profileHeaderSection
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .background(isDarkMode ? Color.gmailDarkBackground : Color.white)

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

                        // Location Tracking Mode
                        HStack(spacing: 16) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Text("Location Tracking")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(isDarkMode ? .white : .black)

                                    Button(action: { showingLocationInfo = true }) {
                                        Image(systemName: "info.circle")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                    }
                                }

                                HStack(spacing: 24) {
                                    HStack(spacing: 8) {
                                        Image(systemName: locationTrackingMode == "active" ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 14))
                                            .foregroundColor(locationTrackingMode == "active" ? (isDarkMode ? Color.white : Color.black) : .gray)

                                        Text("Active")
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(isDarkMode ? .white : .black)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        locationTrackingMode = "active"
                                    }

                                    HStack(spacing: 8) {
                                        Image(systemName: locationTrackingMode == "background" ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 14))
                                            .foregroundColor(locationTrackingMode == "background" ? (isDarkMode ? Color.white : Color.black) : .gray)

                                        Text("Background")
                                            .font(.system(size: 14, weight: .regular))
                                            .foregroundColor(isDarkMode ? .white : .black)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        locationTrackingMode = "background"
                                    }

                                    Spacer()
                                }
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

                        // Cache Management
                        HStack(spacing: 16) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cache Storage")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .white : .black)

                                Text(String(format: "%.2f MB", cacheSize))
                                    .font(.system(size: 13))
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Button(action: { isShowingClearCacheAlert = true }) {
                                Text("Clear")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
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
        .sheet(isPresented: $showingFeedback) {
            FeedbackView()
                .presentationBg()
        }
        .sheet(isPresented: $showingLocationInfo) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Location Tracking")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isDarkMode ? .white : .black)

                    Spacer()

                    Button(action: { showingLocationInfo = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.gray)
                    }
                }
                .padding(20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Active Mode
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "iphone")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.blue)

                                Text("Active Mode")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(isDarkMode ? .white : .black)
                            }

                            Text("App must be open for tracking. Minimal battery drain (1-3% per hour). Best for when you actively use the app.")
                                .font(.system(size: 14))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .lineSpacing(2)
                        }

                        Divider()

                        // Background Mode
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.orange)

                                Text("Background Mode")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(isDarkMode ? .white : .black)
                            }

                            Text("App can track in background. Higher battery drain (5-15% per hour). Best for comprehensive location tracking throughout the day.")
                                .font(.system(size: 14))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .lineSpacing(2)
                        }

                        Divider()

                        // Tip
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.yellow)

                                Text("Tip")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(isDarkMode ? .white : .black)
                            }

                            Text("Keep the app running to ensure accurate tracking. Closing the app will stop background tracking.")
                                .font(.system(size: 14))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .lineSpacing(2)
                        }
                    }
                    .padding(20)
                }
            }
            .background(isDarkMode ? Color.gmailDarkBackground : Color.white)
            .presentationBg()
        }
        .alert("Clear Cache?", isPresented: $isShowingClearCacheAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                ImageCacheManager.shared.clearAllCaches()
                cacheSize = 0
            }
        } message: {
            Text("This will delete all cached images and tasks. This action cannot be undone.")
        }
        .task {
            await notificationService.checkAuthorizationStatus()
            notificationsEnabled = notificationService.isAuthorized
            updateCacheSize()
        }
        .onChange(of: locationTrackingMode) { newMode in
            geofenceManager.updateBackgroundLocationTracking(enabled: newMode == "background")
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

    // MARK: - Helper Methods
    private func updateCacheSize() {
        cacheSize = ImageCacheManager.shared.getTotalCacheSize()
    }

}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(AuthenticationManager.shared)
    }
}