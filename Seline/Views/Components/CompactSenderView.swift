import SwiftUI

struct CompactSenderView: View {
    let email: Email
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme

    // Avatar background color
    private var avatarColor: Color {
        if colorScheme == .dark {
            return Color(white: 0.25)
        } else {
            return Color(white: 0.93)
        }
    }

    // Icon color inside avatar
    private var iconColor: Color {
        if colorScheme == .dark {
            return Color.white
        } else {
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
        VStack(spacing: 0) {
            // Compact header - always visible
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Sender avatar with matching icon logic
                    Circle()
                        .fill(avatarColor)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Group {
                                if let icon = emailIcon {
                                    Image(systemName: icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(iconColor)
                                } else {
                                    Text(email.sender.shortDisplayName.prefix(1).uppercased())
                                        .font(FontManager.geist(size: .small, weight: .semibold))
                                        .foregroundColor(iconColor)
                                }
                            }
                        )

                    // Sender info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(email.sender.shortDisplayName)
                            .font(FontManager.geist(size: .body, weight: .medium))
                            .foregroundColor(Color.shadcnForeground(colorScheme))

                        HStack(spacing: 8) {
                            Text("to me")
                                .font(FontManager.geist(size: .small, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            Text("•")
                                .font(FontManager.geist(size: .small, weight: .regular))
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                            Text(email.formattedTime)
                                .font(FontManager.geist(size: .small, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                        }
                    }

                    Spacer()

                    // Expand/collapse indicator
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.3), value: isExpanded)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())

            // Expanded details - show when tapped
            if isExpanded {
                VStack(spacing: 16) {
                    // Full sender/recipient details
                    VStack(spacing: 12) {
                        // From
                        SenderDetailRow(
                            label: "From",
                            addresses: [email.sender],
                            colorScheme: colorScheme
                        )

                        // To
                        SenderDetailRow(
                            label: "To",
                            addresses: email.recipients,
                            colorScheme: colorScheme
                        )

                        // CC (if applicable)
                        if !email.ccRecipients.isEmpty {
                            SenderDetailRow(
                                label: "CC",
                                addresses: email.ccRecipients,
                                colorScheme: colorScheme
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
        .shadow(
            color: colorScheme == .dark ? .clear : .gray.opacity(0.15),
            radius: colorScheme == .dark ? 0 : 12,
            x: 0,
            y: colorScheme == .dark ? 0 : 4
        )
        .shadow(
            color: colorScheme == .dark ? .clear : .gray.opacity(0.08),
            radius: colorScheme == .dark ? 0 : 6,
            x: 0,
            y: colorScheme == .dark ? 0 : 2
        )
    }
}

struct SenderDetailRow: View {
    let label: String
    let addresses: [EmailAddress]
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Label
            Text(label)
                .font(FontManager.geist(size: .small, weight: .medium))
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .frame(width: 40, alignment: .leading)

            // Addresses
            VStack(alignment: .leading, spacing: 4) {
                ForEach(addresses, id: \.email) { address in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(address.displayName)
                            .font(FontManager.geist(size: .body, weight: .medium))
                            .foregroundColor(Color.shadcnForeground(colorScheme))

                        Text(address.email)
                            .font(FontManager.geist(size: .small, weight: .regular))
                            .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    }
                }
            }

            Spacer()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CompactSenderView(email: Email.sampleEmails[0])

        CompactSenderView(email: Email.sampleEmails[1])
            .preferredColorScheme(.dark)
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}