import SwiftUI

struct FloatingAIBar: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var profilePictureUrl: String? = nil
    var onTap: (() -> Void)? = nil
    var onProfileTap: (() -> Void)? = nil
    
    // Time-based greeting text
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "How can I help you this morning?"
        case 12..<17: return "How can I help you this afternoon?"
        case 17..<21: return "How can I help you this evening?"
        default: return "How can I help you tonight?"
        }
    }
    
    // Orange accent color that adapts to color scheme
    private var accentColor: Color {
        if colorScheme == .dark {
            // Slightly brighter orange for dark mode visibility
            return Color.claudeAccent.opacity(0.9)
        } else {
            // Slightly more muted for light mode elegance
            return Color.claudeAccent.opacity(0.75)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Search bar button
            Button(action: {
                HapticManager.shared.selection()
                onTap?()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(accentColor)
                    
                    Text(greetingText)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    // Glassmorphism effect
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    // Subtle orange gradient border
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.4),
                                    accentColor.opacity(0.2),
                                    accentColor.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .overlay(
                    // Subtle inner glow
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    accentColor.opacity(0.15),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Profile icon
            Button(action: {
                HapticManager.shared.selection()
                onProfileTap?()
            }) {
                Group {
                    if let profilePictureUrl = profilePictureUrl, let url = URL(string: profilePictureUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure(_), .empty:
                                // Fallback to initials or default icon
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 36, weight: .medium))
                            @unknown default:
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 36, weight: .medium))
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        // Show initials or default icon
                        if let user = authManager.currentUser,
                           let name = user.profile?.name,
                           let firstChar = name.first {
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text(String(firstChar).uppercased())
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                                )
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .task {
                await fetchUserProfilePicture()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8) // Match widget spacing (8px) for consistent separation
        .padding(.bottom, 20)
        .shadow(
            color: accentColor.opacity(colorScheme == .dark ? 0.25 : 0.15),
            radius: 12,
            x: 0,
            y: 4
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1),
            radius: 8,
            x: 0,
            y: 2
        )
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
}

