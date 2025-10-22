import SwiftUI

struct EmailCardWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var emailService = EmailService.shared
    @Binding var selectedTab: TabSelection
    @Binding var selectedEmail: Email?

    private var unreadEmails: [Email] {
        Array(emailService.inboxEmails.filter { !$0.isRead }.prefix(5))
    }

    // Generate an icon based on sender email or name (same logic as MainAppView)
    private func emailIcon(for email: Email) -> String? {
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
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Text("Unread Emails")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Emails list
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if unreadEmails.isEmpty {
                        Text("No unread emails")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(unreadEmails) { email in
                            Button(action: {
                                HapticManager.shared.email()
                                selectedEmail = email
                            }) {
                                HStack(spacing: 8) {
                                    // Avatar circle with icon
                                    Circle()
                                        .fill(
                                            colorScheme == .dark ?
                                                Color(red: 0.40, green: 0.65, blue: 0.80) :
                                                Color(red: 0.20, green: 0.34, blue: 0.40)
                                        )
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Group {
                                                if let icon = emailIcon(for: email) {
                                                    Image(systemName: icon)
                                                        .font(.system(size: 9, weight: .semibold))
                                                        .foregroundColor(.white)
                                                } else {
                                                    Text(email.sender.shortDisplayName.prefix(1).uppercased())
                                                        .font(.system(size: 9, weight: .semibold))
                                                        .foregroundColor(.white)
                                                }
                                            }
                                        )

                                    // Only sender name
                                    Text(email.sender.displayName)
                                        .font(.shadcnTextXs)
                                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        .cornerRadius(12)
    }
}

#Preview {
    EmailCardWidget(selectedTab: .constant(.home), selectedEmail: .constant(nil))
        .background(Color.shadcnBackground(.light))
}
