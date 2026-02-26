import SwiftUI

struct EmailRow: View {
    let email: Email
    let onDelete: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    let onArchive: ((Email) -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @State private var profilePictureUrl: String?

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

    private var summarySignalText: String {
        [
            email.subject,
            email.snippet,
            email.aiSummary ?? "",
            email.sender.displayName,
            email.sender.email
        ]
        .joined(separator: " ")
        .lowercased()
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private var isActionRequired: Bool {
        let signal = summarySignalText

        let noActionPhrases = [
            "no action required",
            "no response required",
            "for your information",
            "fyi",
            "informational only"
        ]

        let directRequestPhrases = [
            "action required",
            "requires your action",
            "please reply",
            "reply needed",
            "reply required",
            "respond by",
            "response required",
            "please confirm",
            "verify your",
            "review and sign",
            "sign and return",
            "approval required",
            "please approve",
            "rsvp",
            "confirm attendance",
            "complete your",
            "submit",
            "update your",
            "upload",
            "accept or decline"
        ]

        let deadlineTaskPhrases = [
            "payment due",
            "invoice due",
            "past due",
            "overdue",
            "due today",
            "due tomorrow",
            "due by",
            "deadline",
            "expires on",
            "payment failed",
            "card declined"
        ]

        let criticalAlertPhrases = [
            "security alert",
            "fraud alert",
            "suspicious activity",
            "password reset",
            "verify your account",
            "low balance",
            "account locked"
        ]

        let announcementPhrases = [
            "newsletter",
            "announcement",
            "new feature",
            "new features",
            "release notes",
            "changelog",
            "product update",
            "developer news",
            "what's new",
            "introducing",
            "now available",
            "tips",
            "learn more",
            "read more",
            "webinar",
            "community update"
        ]

        let broadcastSenderHints = [
            "noreply",
            "no-reply",
            "donotreply",
            "newsletter",
            "updates@",
            "news@",
            "notifications@"
        ]

        if containsAny(in: signal, phrases: noActionPhrases) {
            return false
        }

        let hasCriticalAlert = containsAny(in: signal, phrases: criticalAlertPhrases)
        if hasCriticalAlert {
            return true
        }

        let hasDirectRequest = containsAny(in: signal, phrases: directRequestPhrases)
        let hasDeadlineTask = containsAny(in: signal, phrases: deadlineTaskPhrases)

        let senderEmail = email.sender.email.lowercased()
        let subjectSnippet = "\(email.subject) \(email.snippet)".lowercased()
        let isLikelyBroadcastSender = containsAny(in: senderEmail, phrases: broadcastSenderHints)
        let isAnnouncement = containsAny(in: signal, phrases: announcementPhrases)
            || containsAny(in: subjectSnippet, phrases: announcementPhrases)
            || email.category == .promotions
            || email.category == .social

        if isAnnouncement && !hasDirectRequest && !hasDeadlineTask {
            return false
        }

        if isLikelyBroadcastSender && !hasDeadlineTask && !hasCriticalAlert {
            return false
        }

        if hasDeadlineTask {
            return true
        }

        return hasDirectRequest && !isAnnouncement
    }

    private func containsAny(in text: String, phrases: [String]) -> Bool {
        phrases.contains(where: { text.contains($0) })
    }

    private var emailStatusChip: (text: String, fill: Color, textColor: Color) {
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
            .task(id: email.sender.email) {
                await fetchProfilePictureIfNeeded()
            }
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
                            // Sender name
                            Text(email.sender.shortDisplayName)
                                .font(FontManager.geist(size: 13, systemWeight: email.isRead ? .medium : .semibold))
                                .foregroundColor(Color.appTextPrimary(colorScheme))
                                .lineLimit(1)

                            // Subject
                            Text(email.subject)
                                .font(FontManager.geist(size: 12, systemWeight: email.isRead ? .regular : .medium))
                                .foregroundColor(
                                    email.isRead ?
                                    Color.appTextSecondary(colorScheme) :
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
                                .foregroundColor(Color.appTextSecondary(colorScheme))

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
            .font(FontManager.geist(size: 10, weight: .semibold))
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
        if let profilePictureUrl, !profilePictureUrl.isEmpty {
            return profilePictureUrl
        }
        return nil
    }

    private func fetchProfilePictureIfNeeded() async {
        if let senderAvatar = email.sender.avatarUrl, !senderAvatar.isEmpty {
            await MainActor.run {
                profilePictureUrl = senderAvatar
            }
            return
        }

        let cacheKey = CacheManager.CacheKey.emailProfilePicture(email.sender.email)
        if let cachedURL: String = CacheManager.shared.get(forKey: cacheKey), !cachedURL.isEmpty {
            await MainActor.run {
                profilePictureUrl = cachedURL
            }
            return
        }

        do {
            if let fetchedURL = try await GmailAPIClient.shared.fetchProfilePicture(for: email.sender.email),
               !fetchedURL.isEmpty {
                await MainActor.run {
                    profilePictureUrl = fetchedURL
                }
            }
        } catch {
            // Keep initials fallback if photo fetch fails.
        }
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
