import SwiftUI

enum EmailMailboxPresentationStyle {
    case inbox
    case sent
}

struct EmailRow: View {
    let email: Email
    let onDelete: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    let onArchive: ((Email) -> Void)?
    let presentationStyle: EmailMailboxPresentationStyle
    @Environment(\.colorScheme) var colorScheme

    init(
        email: Email,
        onDelete: @escaping (Email) -> Void,
        onMarkAsUnread: @escaping (Email) -> Void,
        onArchive: ((Email) -> Void)? = nil,
        presentationStyle: EmailMailboxPresentationStyle = .inbox
    ) {
        self.email = email
        self.onDelete = onDelete
        self.onMarkAsUnread = onMarkAsUnread
        self.onArchive = onArchive
        self.presentationStyle = presentationStyle
    }

    // Avatar background color - Google brand colors
    private var avatarColor: Color {
        let colors: [Color] = [
            Color(red: 0.45, green: 0.52, blue: 0.60),
            Color(red: 0.55, green: 0.55, blue: 0.55),
            Color(red: 0.40, green: 0.55, blue: 0.55),
            Color(red: 0.55, green: 0.50, blue: 0.45),
        ]

        // Generate deterministic color based on sender email using stable hash
        let hash = HashUtils.deterministicHash(email.sender.email)
        let colorIndex = abs(hash) % colors.count
        return colors[colorIndex]
    }

    private var isActionRequired: Bool {
        email.requiresAction
    }

    private var emailStatusChip: (text: String, fill: Color, textColor: Color) {
        if presentationStyle == .sent {
            return (
                text: "Sent",
                fill: colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                textColor: Color.emailGlassMutedText(colorScheme)
            )
        }

        if isActionRequired {
            return (
                text: "Action",
                fill: colorScheme == .dark ? Color.orange.opacity(0.2) : Color.orange.opacity(0.12),
                textColor: colorScheme == .dark ? Color.orange.opacity(0.95) : Color.orange.opacity(0.9)
            )
        }

        return (
            text: "FYI",
            fill: colorScheme == .dark ? Color.blue.opacity(0.18) : Color.blue.opacity(0.1),
            textColor: colorScheme == .dark ? Color.blue.opacity(0.9) : Color.blue.opacity(0.8)
        )
    }

    private var primaryNameText: String {
        switch presentationStyle {
        case .inbox:
            return email.sender.shortDisplayName
        case .sent:
            if let firstRecipient = email.recipients.first?.shortDisplayName, !firstRecipient.isEmpty {
                return "To: \(firstRecipient)"
            }
            return "Sent"
        }
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
                // Sender avatar - prefer real photo/logo when available
                avatarView

                // Email content
                VStack(alignment: .leading, spacing: 3) {
                    // Top row: sender name, subject preview, time
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(primaryNameText)
                                .font(FontManager.geist(size: 13, systemWeight: email.isRead ? .medium : .semibold))
                                .foregroundColor(Color.appTextPrimary(colorScheme))
                                .lineLimit(1)

                            Text(email.subject)
                                .font(FontManager.geist(size: 12, systemWeight: email.isRead ? .regular : .medium))
                                .foregroundColor(
                                    email.isRead ?
                                    Color.emailGlassMutedText(colorScheme) :
                                    Color.appTextPrimary(colorScheme)
                                )
                                .lineLimit(1)

                            statusChip(
                                text: emailStatusChip.text,
                                fill: emailStatusChip.fill,
                                textColor: emailStatusChip.textColor
                            )
                        }

                        Spacer()

                        // Time and indicators
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(email.formattedTime)
                                .font(FontManager.geist(size: 10, weight: .regular))
                                .foregroundColor(Color.emailGlassMutedText(colorScheme))

                            HStack(spacing: 3) {
                                if email.isImportant {
                                    Image(systemName: "exclamationmark")
                                        .font(FontManager.geist(size: 8, weight: .bold))
                                        .foregroundColor(.primary)
                                }

                                if email.hasAttachments {
                                    Image(systemName: "paperclip")
                                        .font(FontManager.geist(size: 8, weight: .medium))
                                        .foregroundColor(Color.appTextSecondary(colorScheme))
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
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.emailGlassInnerTint(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.emailGlassInnerBorder(colorScheme), lineWidth: 1)
        )
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

    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL = resolvedAvatarURL,
           URL(string: avatarURL) != nil {
            CachedAsyncImage(
                url: avatarURL,
                content: { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                },
                placeholder: {
                    fallbackAvatarView
                }
            )
        } else {
            fallbackAvatarView
        }
    }

    // MARK: - Private Methods

    private func statusChip(text: String, fill: Color, textColor: Color) -> some View {
        Text(text)
            .font(FontManager.geist(size: 9, weight: .semibold))
            .foregroundColor(textColor)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(fill)
            )
    }

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

    private var resolvedAvatarURL: String? {
        if let senderAvatar = email.sender.avatarUrl, !senderAvatar.isEmpty {
            return senderAvatar
        }
        let cacheKey = CacheManager.CacheKey.emailProfilePicture(email.sender.email)
        if let cachedURL: String = CacheManager.shared.get(forKey: cacheKey), !cachedURL.isEmpty {
            return cachedURL
        }
        return nil
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
