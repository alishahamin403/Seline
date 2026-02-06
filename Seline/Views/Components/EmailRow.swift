import SwiftUI

struct EmailRow: View {
    let email: Email
    let onDelete: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    let onArchive: ((Email) -> Void)?
    @Environment(\.colorScheme) var colorScheme

    init(
        email: Email,
        onDelete: @escaping (Email) -> Void,
        onMarkAsUnread: @escaping (Email) -> Void,
        onArchive: ((Email) -> Void)? = nil
    ) {
        self.email = email
        self.onDelete = onDelete
        self.onMarkAsUnread = onMarkAsUnread
        self.onArchive = onArchive
    }

    // Avatar background color - Google brand colors
    private var avatarColor: Color {
        let colors: [Color] = [
            Color(red: 0.2588, green: 0.5216, blue: 0.9569),  // Google Blue #4285F4
            Color(red: 0.9176, green: 0.2627, blue: 0.2078),  // Google Red #EA4335
            Color(red: 0.9843, green: 0.7373, blue: 0.0157),  // Google Yellow #FBBC04
            Color(red: 0.2039, green: 0.6588, blue: 0.3255),  // Google Green #34A853
        ]

        // Generate deterministic color based on sender email using stable hash
        let hash = HashUtils.deterministicHash(email.sender.email)
        let colorIndex = abs(hash) % colors.count
        return colors[colorIndex]
    }

    var body: some View {
        rowContent
            .swipeActions(
                left: SwipeAction(
                    type: .delete,
                    icon: "trash.fill",
                    color: .red,
                    haptic: { HapticManager.shared.delete() },
                    action: {
                        onDelete(email)
                    }
                ),
                right: email.isRead ?
                    SwipeAction(
                        type: .markUnread,
                        icon: "envelope.badge",
                        color: .blue,
                        haptic: { HapticManager.shared.email() },
                        action: {
                            onMarkAsUnread(email)
                        }
                    ) :
                    (onArchive != nil ?
                        SwipeAction(
                            type: .archive,
                            icon: "archivebox.fill",
                            color: .gray,
                            haptic: { HapticManager.shared.email() },
                            action: {
                                onArchive?(email)
                            }
                        ) : nil)
            )
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
                // Sender avatar - colored circle with initials
                fallbackAvatarView

                // Email content
                VStack(alignment: .leading, spacing: 3) {
                    // Top row: sender name, subject preview, time
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            // Sender name
                            Text(email.sender.shortDisplayName)
                                .font(FontManager.geist(size: 13, systemWeight: email.isRead ? .medium : .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .lineLimit(1)

                            // Subject
                            Text(email.subject)
                                .font(FontManager.geist(size: 12, systemWeight: email.isRead ? .regular : .medium))
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
                                .font(FontManager.geist(size: 10, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                            HStack(spacing: 3) {
                                if email.isImportant {
                                    Image(systemName: "exclamationmark")
                                        .font(FontManager.geist(size: 8, weight: .bold))
                                        .foregroundColor(.orange)
                                }

                                if email.hasAttachments {
                                    Image(systemName: "paperclip")
                                        .font(FontManager.geist(size: 8, weight: .medium))
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
    }

    // MARK: - Private Methods

    private var fallbackAvatarView: some View {
        // Generate initials from sender name (e.g., "Wealthsimple" -> "WS", "John Doe" -> "JD")
        let initials = generateInitials(from: email.sender.shortDisplayName)
        
        return Circle()
            .fill(avatarColor)
            .frame(width: 32, height: 32)
            .overlay(
                Text(initials)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
    
    /// Generate initials from a name (e.g., "Wealthsimple" -> "WS", "John Doe" -> "JD")
    private func generateInitials(from name: String) -> String {
        let words = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        if words.count >= 2 {
            // Multiple words: take first letter of first two words
            let first = String(words[0].prefix(1).uppercased())
            let second = String(words[1].prefix(1).uppercased())
            return first + second
        } else if words.count == 1 {
            // Single word: take first two letters if long enough, otherwise just first
            let word = words[0]
            if word.count >= 2 {
                return String(word.prefix(2).uppercased())
            } else {
                return String(word.prefix(1).uppercased())
            }
        } else {
            // Fallback: use first character of email
            return String(email.sender.email.prefix(1).uppercased())
        }
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