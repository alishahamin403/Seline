import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var notificationService = NotificationService.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var profileImage: UIImage? = nil

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
                        settingsMenuItem(icon: "bell", label: "Notifications", action: {})
                        Divider()
                            .padding(.leading, 50)

                        settingsMenuItem(icon: "eye", label: "Appearance", action: {
                            showAppearanceMenu()
                        })
                        Divider()
                            .padding(.leading, 50)

                        settingsMenuItem(icon: "lock", label: "Privacy & Security", action: {})
                        Divider()
                            .padding(.leading, 50)

                        settingsMenuItem(icon: "headphones", label: "Help and Support", action: {})
                        Divider()
                            .padding(.leading, 50)

                        settingsMenuItem(icon: "info.circle", label: "About", action: {})
                        Divider()
                            .padding(.leading, 50)

                        settingsMenuItemLogout()
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
            // Load Google profile image
            if let photoURL = authManager.currentUser?.profile?.profilePictureURL {
                loadProfileImage(from: photoURL)
            }
        }
    }

    // MARK: - Profile Header Section
    private var profileHeaderSection: some View {
        HStack(spacing: 16) {
            // Google Profile Avatar
            if let profileImage = profileImage {
                Image(uiImage: profileImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                // Fallback to initials if image can't load
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
            }

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

    // MARK: - Settings Menu Item
    private func settingsMenuItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(isDarkMode ? .white.opacity(0.7) : .black.opacity(0.7))
                    .frame(width: 24)

                Text(label)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(isDarkMode ? .white : .black)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
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

    // MARK: - Helper Functions
    private func loadProfileImage(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let uiImage = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.profileImage = uiImage
                }
            }
        }.resume()
    }

    private func showAppearanceMenu() {
        // This will open appearance settings
    }

}

#Preview {
    NavigationView {
        SettingsView()
            .environmentObject(AuthenticationManager.shared)
    }
}