import SwiftUI

struct EmailRow: View {
    let email: Email
    let onDelete: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var profilePictureUrl: String?
    @State private var isLoadingProfilePicture = false

    // Avatar background color - Google brand colors
    private var avatarColor: Color {
        let colors: [Color] = [
            Color(red: 0.2588, green: 0.5216, blue: 0.9569),  // Google Blue #4285F4
            Color(red: 0.9176, green: 0.2627, blue: 0.2078),  // Google Red #EA4335
            Color(red: 0.9843, green: 0.7373, blue: 0.0157),  // Google Yellow #FBBC04
            Color(red: 0.2039, green: 0.6588, blue: 0.3255),  // Google Green #34A853
        ]

        // Generate deterministic color based on sender email using stable hash
        let hash = deterministicHash(email.sender.email)
        let colorIndex = abs(hash) % colors.count
        return colors[colorIndex]
    }

    private func deterministicHash(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash)
    }

    var body: some View {
        HStack(spacing: 10) {
                // Sender avatar - show Google profile picture if available
                if let profilePictureUrl = profilePictureUrl, !profilePictureUrl.isEmpty {
                    // Display actual Google profile picture
                    AsyncImage(url: URL(string: profilePictureUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        @unknown default:
                            // Fallback to colored initials while loading
                            Circle()
                                .fill(avatarColor)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(email.sender.shortDisplayName.prefix(1).uppercased())
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                } else {
                    // Default colored avatar with initials
                    Circle()
                        .fill(avatarColor)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(email.sender.shortDisplayName.prefix(1).uppercased())
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }

                // Email content
                VStack(alignment: .leading, spacing: 3) {
                    // Top row: sender name, subject preview, time
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            // Sender name
                            Text(email.sender.shortDisplayName)
                                .font(.system(size: 13, weight: email.isRead ? .medium : .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .lineLimit(1)

                            // Subject
                            Text(email.subject)
                                .font(.system(size: 12, weight: email.isRead ? .regular : .medium))
                                .foregroundColor(
                                    email.isRead ?
                                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)) :
                                    (colorScheme == .dark ? Color.white : Color.black)
                                )
                                .lineLimit(1)
                        }

                        Spacer()

                        // Time and indicators
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(email.formattedTime)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                            HStack(spacing: 3) {
                                if email.isImportant {
                                    Image(systemName: "exclamationmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.orange)
                                }

                                if email.hasAttachments {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                }

                                if !email.isRead {
                                    Circle()
                                        .fill(avatarColor)
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                    }

                }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            // Mark as Unread option (only show if email is read)
            if email.isRead {
                Button {
                    onMarkAsUnread(email)
                } label: {
                    Label("Mark as Unread", systemImage: "envelope.badge")
                }
            }

            // Delete option
            Button(role: .destructive) {
                onDelete(email)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .task {
            // Fetch the Google profile picture when view appears
            await fetchProfilePicture()
        }
    }

    // MARK: - Private Methods

    private func fetchProfilePicture() async {
        guard !isLoadingProfilePicture else { return }

        isLoadingProfilePicture = true

        do {
            if let picUrl = try await GmailAPIClient.shared.fetchProfilePicture(for: email.sender.email) {
                await MainActor.run {
                    self.profilePictureUrl = picUrl
                }
            }
        } catch {
            // Silently fail - will show colored avatar fallback
            print("Failed to fetch profile picture for \(email.sender.email): \(error)")
        }

        isLoadingProfilePicture = false
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(Email.sampleEmails.prefix(3)) { email in
            EmailRow(
                email: email,
                onDelete: { email in
                    print("Delete email: \(email.subject)")
                },
                onMarkAsUnread: { email in
                    print("Mark as unread: \(email.subject)")
                }
            )
        }
    }
    .background(Color.shadcnBackground(.light))
}