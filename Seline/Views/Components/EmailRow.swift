import SwiftUI

struct EmailRow: View {
    let email: Email
    let onDelete: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    @Environment(\.colorScheme) var colorScheme

    // Avatar background color
    private var avatarColor: Color {
        if colorScheme == .dark {
            // Dark mode: light gray circle
            return Color(white: 0.25)
        } else {
            // Light mode: slightly darker than white background
            return Color(white: 0.93)
        }
    }

    // Icon color inside avatar
    private var iconColor: Color {
        if colorScheme == .dark {
            // Dark mode: white icon
            return Color.white
        } else {
            // Light mode: dark gray icon
            return Color(white: 0.3)
        }
    }

    // Generate an icon based on sender email or name
    private var emailIcon: String? {
        let senderEmail = email.sender.email.lowercased()
        let senderName = (email.sender.name ?? "").lowercased()
        let sender = senderEmail + " " + senderName

        // Financial/Investing
        if sender.contains("wealthsimple") || sender.contains("robinhood") ||
           sender.contains("questrade") || sender.contains("tdameritrade") ||
           sender.contains("etrade") || sender.contains("fidelity") {
            return "chart.line.uptrend.xyaxis"
        }

        // Banking
        if sender.contains("bank") || sender.contains("chase") || sender.contains("cibc") ||
           sender.contains("rbc") || sender.contains("td") || sender.contains("bmo") ||
           sender.contains("scotiabank") || sender.contains("wellsfargo") ||
           sender.contains("amex") || sender.contains("americanexpress") ||
           sender.contains("american express") {
            return "dollarsign.circle.fill"
        }

        // Shopping/Retail
        if sender.contains("amazon") || sender.contains("ebay") || sender.contains("walmart") ||
           sender.contains("target") || sender.contains("bestbuy") || sender.contains("shopify") ||
           sender.contains("etsy") || sender.contains("aliexpress") {
            return "bag.fill"
        }

        // Travel/Airlines
        if sender.contains("airline") || sender.contains("flight") || sender.contains("expedia") ||
           sender.contains("airbnb") || sender.contains("booking") || sender.contains("hotels") ||
           sender.contains("delta") || sender.contains("united") || sender.contains("aircanada") {
            return "airplane"
        }

        // Food Delivery
        if sender.contains("uber") && sender.contains("eats") || sender.contains("doordash") ||
           sender.contains("grubhub") || sender.contains("skipthedishes") ||
           sender.contains("postmates") || sender.contains("deliveroo") {
            return "fork.knife"
        }

        // Ride Share/Transportation
        if sender.contains("uber") || sender.contains("lyft") || sender.contains("taxi") {
            return "car.fill"
        }

        // Tech/Development
        if sender.contains("github") || sender.contains("gitlab") || sender.contains("bitbucket") {
            return "chevron.left.forwardslash.chevron.right"
        }

        // Social Media - Camera apps
        if sender.contains("snapchat") || sender.contains("instagram") {
            return "camera.fill"
        }

        // Facebook
        if sender.contains("facebook") || sender.contains("meta") {
            return "person.2.fill"
        }

        // LinkedIn
        if sender.contains("linkedin") {
            return "briefcase.fill"
        }

        // Twitter/X
        if sender.contains("twitter") || sender.contains("x.com") {
            return "bubble.left.and.bubble.right.fill"
        }

        // TikTok
        if sender.contains("tiktok") {
            return "music.note"
        }

        // YouTube
        if sender.contains("youtube") {
            return "play.rectangle.fill"
        }

        // Discord
        if sender.contains("discord") {
            return "message.fill"
        }

        // Reddit
        if sender.contains("reddit") {
            return "text.bubble.fill"
        }

        // Google
        if sender.contains("google") || sender.contains("gmail") && !sender.contains("@gmail.com") {
            return "magnifyingglass"
        }

        // Apple
        if sender.contains("apple") || sender.contains("icloud") && !sender.contains("@icloud.com") {
            return "apple.logo"
        }

        // Microsoft
        if sender.contains("microsoft") || sender.contains("outlook") && !sender.contains("@outlook.com") ||
           sender.contains("office365") || sender.contains("teams") {
            return "square.grid.2x2.fill"
        }

        // Amazon
        if sender.contains("amazon") && !sender.contains("shopping") {
            return "shippingbox.fill"
        }

        // Netflix
        if sender.contains("netflix") {
            return "play.tv.fill"
        }

        // Spotify
        if sender.contains("spotify") {
            return "music.note.list"
        }

        // Slack
        if sender.contains("slack") {
            return "number"
        }

        // Zoom
        if sender.contains("zoom") {
            return "video.fill"
        }

        // Dropbox
        if sender.contains("dropbox") {
            return "folder.fill"
        }

        // PayPal/Venmo
        if sender.contains("paypal") || sender.contains("venmo") {
            return "dollarsign.square.fill"
        }

        // News/Media
        if sender.contains("newsletter") || sender.contains("substack") || sender.contains("medium") ||
           sender.contains("nytimes") || sender.contains("news") {
            return "newspaper.fill"
        }

        // Security/Notifications
        if sender.contains("noreply") || sender.contains("no-reply") ||
           sender.contains("notification") || sender.contains("alert") {
            return "bell.fill"
        }

        // Healthcare
        if sender.contains("health") || sender.contains("medical") || sender.contains("doctor") ||
           sender.contains("clinic") || sender.contains("hospital") {
            return "heart.fill"
        }

        // Calendar/Events
        if sender.contains("calendar") || sender.contains("eventbrite") || sender.contains("meetup") {
            return "calendar"
        }

        // Check if it's a personal email (common personal email domains)
        let personalDomains = ["gmail.com", "yahoo.com", "hotmail.com", "outlook.com",
                              "icloud.com", "me.com", "aol.com", "protonmail.com"]
        if personalDomains.contains(where: { senderEmail.contains($0) }) {
            return "person.fill"
        }

        // Default to company/building icon for business emails
        return "building.2.fill"
    }

    var body: some View {
        HStack(spacing: 12) {
                // Sender avatar with email-based color and AI-based icon
                Circle()
                    .fill(avatarColor)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Group {
                            if let icon = emailIcon {
                                Image(systemName: icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(iconColor)
                            } else {
                                Text(email.sender.shortDisplayName.prefix(1).uppercased())
                                    .font(FontManager.geist(size: .body, weight: .semibold))
                                    .foregroundColor(iconColor)
                            }
                        }
                    )

                // Email content
                VStack(alignment: .leading, spacing: 4) {
                    // Top row: sender name, subject preview, time
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            // Sender name
                            Text(email.sender.shortDisplayName)
                                .font(FontManager.geist(size: .body, weight: email.isRead ? .medium : .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .lineLimit(1)

                            // Subject
                            Text(email.subject)
                                .font(FontManager.geist(size: .small, weight: email.isRead ? .regular : .medium))
                                .foregroundColor(
                                    email.isRead ?
                                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)) :
                                    (colorScheme == .dark ? Color.white : Color.black)
                                )
                                .lineLimit(1)
                        }

                        Spacer()

                        // Time and indicators
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(email.formattedTime)
                                .font(FontManager.geist(size: .caption, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                            HStack(spacing: 4) {
                                if email.isImportant {
                                    Image(systemName: "exclamationmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.orange)
                                }

                                if email.hasAttachments {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                }

                                if !email.isRead {
                                    Circle()
                                        .fill(colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40))
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                    }

                }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 12)
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