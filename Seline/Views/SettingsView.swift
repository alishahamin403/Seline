import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject var themeManager = ThemeManager.shared
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var geofenceManager = GeofenceManager.shared
    @StateObject private var elevenLabsService = ElevenLabsTTSService.shared

    // Computed property to get current theme state
    private var isDarkMode: Bool {
        themeManager.effectiveColorScheme == .dark
    }

    // Settings states
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("locationTrackingEnabled") private var locationTrackingEnabled = true
    @State private var showingFeedback = false
    @State private var showingLocationInfo = false
    @State private var profilePictureUrl: String? = nil
    @State private var showingCalendarSelection = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // User Profile Header Section
                    profileHeaderSection
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .background(isDarkMode ? Color.gmailDarkBackground : Color.white)
                        .task {
                            await fetchUserProfilePicture()
                        }

                    // Settings Menu Items
                    VStack(spacing: 0) {
                        // Notifications Toggle
                        HStack(spacing: 16) {
                            Image(systemName: "bell")
                                .font(FontManager.geist(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .frame(width: 24)

                            Text("Notifications")
                                .font(FontManager.geist(size: 16, weight: .regular))
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
                                .font(FontManager.geist(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .frame(width: 24)

                            Text("Appearance")
                                .font(FontManager.geist(size: 16, weight: .regular))
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
                                        .font(FontManager.geist(size: 14, weight: .regular))
                                    Text(themeManager.selectedTheme.displayName)
                                        .font(FontManager.geist(size: 14, weight: .regular))
                                    Image(systemName: "chevron.right")
                                        .font(FontManager.geist(size: 14, weight: .semibold))
                                }
                                .foregroundColor(.gray.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                        Divider()
                            .padding(.leading, 50)

                        // Location Tracking Toggle
                        HStack(spacing: 16) {
                            Image(systemName: "location.fill")
                                .font(FontManager.geist(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .frame(width: 24)

                            Text("Location Tracking")
                                .font(FontManager.geist(size: 16, weight: .regular))
                                .foregroundColor(isDarkMode ? .white : .black)

                            Spacer()

                            Toggle("", isOn: $locationTrackingEnabled)
                                .labelsHidden()
                                .tint(isDarkMode ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)

                        Divider()
                            .padding(.leading, 50)

                        // Calendar Sync Selection
                        Button(action: { showingCalendarSelection = true }) {
                            HStack(spacing: 16) {
                                Image(systemName: "calendar.badge.checkmark")
                                    .font(FontManager.geist(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                    .frame(width: 24)

                                Text("Select Calendars to Sync")
                                    .font(FontManager.geist(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .white : .black)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(FontManager.geist(size: 14, weight: .semibold))
                                    .foregroundColor(.gray.opacity(0.3))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }

                        Divider()
                            .padding(.leading, 50)

                        // Feedback Button
                        Button(action: { showingFeedback = true }) {
                            HStack(spacing: 16) {
                                Image(systemName: "bubble.right")
                                    .font(FontManager.geist(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                    .frame(width: 24)

                                Text("Send Feedback")
                                    .font(FontManager.geist(size: 16, weight: .regular))
                                    .foregroundColor(isDarkMode ? .white : .black)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(FontManager.geist(size: 14, weight: .semibold))
                                    .foregroundColor(.gray.opacity(0.3))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                        }


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
        .sheet(isPresented: $showingCalendarSelection) {
            CalendarSelectionView()
                .presentationBg()
        }
        .sheet(isPresented: $showingLocationInfo) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Location Tracking")
                        .font(FontManager.geist(size: 18, weight: .semibold))
                        .foregroundColor(isDarkMode ? .white : .black)

                    Spacer()

                    Button(action: { showingLocationInfo = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 20, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }
                .padding(20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // How it Works
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "location.fill")
                                    .font(FontManager.geist(size: 16, weight: .semibold))
                                    .foregroundColor(.blue)

                                Text("How It Works")
                                    .font(FontManager.geist(size: 16, weight: .semibold))
                                    .foregroundColor(isDarkMode ? .white : .black)
                            }

                            Text("When enabled, Seline uses geofencing to automatically detect when you arrive and leave saved locations. This works in the background even when the app is closed.")
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .lineSpacing(2)
                        }

                        Divider()

                        // Battery Usage
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "battery.100")
                                    .font(FontManager.geist(size: 16, weight: .semibold))
                                    .foregroundColor(.green)

                                Text("Battery Usage")
                                    .font(FontManager.geist(size: 16, weight: .semibold))
                                    .foregroundColor(isDarkMode ? .white : .black)
                            }

                            Text("Geofencing is battery-efficient and only triggers when you cross location boundaries. Typical battery impact is minimal (1-2% per day).")
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                                .lineSpacing(2)
                        }

                        Divider()

                        // Privacy
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .font(FontManager.geist(size: 16, weight: .semibold))
                                    .foregroundColor(.orange)

                                Text("Privacy")
                                    .font(FontManager.geist(size: 16, weight: .semibold))
                                    .foregroundColor(isDarkMode ? .white : .black)
                            }

                            Text("Your location data stays private and is only stored on your device and in your secure Supabase database. We never share or sell your location data.")
                                .font(FontManager.geist(size: 14, weight: .regular))
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
        .task {
            await notificationService.checkAuthorizationStatus()
            notificationsEnabled = notificationService.isAuthorized
        }
        .onChange(of: locationTrackingEnabled) { isEnabled in
            if isEnabled {
                // Enable geofencing and background tracking
                geofenceManager.updateBackgroundLocationTracking(enabled: true)
                geofenceManager.setupGeofences(for: LocationsManager.shared.savedPlaces)
            } else {
                // Disable geofencing
                geofenceManager.stopMonitoring()
            }
        }
    }

    // MARK: - Profile Header Section
    private var profileHeaderSection: some View {
        HStack(spacing: 16) {
            // User Avatar with profile picture or initials
            Group {
                if let profilePictureUrl = profilePictureUrl, let url = URL(string: profilePictureUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure(_), .empty:
                            // Fallback to initials
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
                                        .font(FontManager.geist(size: 20, weight: .semibold))
                                        .foregroundColor(isDarkMode ? .black : .white)
                                )
                        @unknown default:
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
                                        .font(FontManager.geist(size: 20, weight: .semibold))
                                        .foregroundColor(isDarkMode ? .black : .white)
                                )
                        }
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
                } else {
                    // Show initials or default icon
                    if let user = authManager.currentUser,
                       let name = user.profile?.name,
                       let firstChar = name.first {
                        Circle()
                            .fill(isDarkMode ? Color.white : Color.black)
                            .overlay(
                                Text(String(firstChar).uppercased())
                                    .font(FontManager.geist(size: 20, weight: .semibold))
                                    .foregroundColor(isDarkMode ? .black : .white)
                            )
                            .frame(width: 60, height: 60)
                    } else {
                        Circle()
                            .fill(isDarkMode ? Color.white : Color.black)
                            .overlay(
                                Text("U")
                                    .font(FontManager.geist(size: 20, weight: .semibold))
                                    .foregroundColor(isDarkMode ? .black : .white)
                            )
                            .frame(width: 60, height: 60)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                // User Name
                Text(authManager.currentUser?.profile?.name ?? "User")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(isDarkMode ? .white : .black)

                // User Email
                Text(authManager.currentUser?.profile?.email ?? "No email")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(.gray)
            }

            Spacer()
        }
    }
    
    // MARK: - Private Methods
    
    private func fetchUserProfilePicture() async {
        do {
            if let picUrl = try await GmailAPIClient.shared.fetchCurrentUserProfilePicture() {
                await MainActor.run {
                    self.profilePictureUrl = picUrl
                }
            }
        } catch {
            // Silently fail - will show initials fallback
            print("Failed to fetch current user profile picture: \(error)")
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
                    .font(FontManager.geist(size: 16, weight: .regular))
                    .foregroundColor(.red)
                    .frame(width: 24)

                Text("Logout")
                    .font(FontManager.geist(size: 16, weight: .regular))
                    .foregroundColor(.red)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 14, weight: .semibold))
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