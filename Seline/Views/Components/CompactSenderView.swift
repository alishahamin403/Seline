import SwiftUI

struct CompactSenderView: View {
    let email: Email
    @State private var isExpanded = false
    @State private var profilePictureUrl: String?
    @Environment(\.colorScheme) var colorScheme

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
        VStack(spacing: 0) {
            // Compact header - always visible
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Sender avatar - show profile picture if available
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
                                // Fallback to initials while loading
                                Circle()
                                    .fill(avatarColor)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text(email.sender.shortDisplayName.prefix(1).uppercased())
                                            .font(FontManager.geist(size: .small, weight: .semibold))
                                            .foregroundColor(.white)
                                    )
                            }
                        }
                    } else {
                        // Default avatar with initials
                        Circle()
                            .fill(avatarColor)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Text(email.sender.shortDisplayName.prefix(1).uppercased())
                                    .font(FontManager.geist(size: .small, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }

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
        .task {
            // Fetch the Google profile picture when view appears
            await fetchProfilePicture()
        }
    }

    // MARK: - Private Methods

    private func fetchProfilePicture() async {
        do {
            if let picUrl = try await GmailAPIClient.shared.fetchProfilePicture(for: email.sender.email) {
                await MainActor.run {
                    self.profilePictureUrl = picUrl
                }
            }
        } catch {
            // Silently fail - will show initials fallback
            print("Failed to fetch profile picture for \(email.sender.email): \(error)")
        }
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