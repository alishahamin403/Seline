import SwiftUI

struct EmailSearchResultsView: View {
    let scopeTitle: String
    let searchText: String
    let searchResults: [Email]
    let isLoading: Bool
    let onEmailTap: (Email) -> Void
    let onDeleteEmail: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    @Environment(\.colorScheme) var colorScheme

    private var presentationStyle: EmailMailboxPresentationStyle {
        scopeTitle == "Sent" ? .sent : .inbox
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Searching...")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(Color.emailGlassMutedText(colorScheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .appAmbientCardStyle(
                        colorScheme: colorScheme,
                        variant: .topLeading,
                        cornerRadius: 24,
                        highlightStrength: 0.28
                    )
                } else if searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(FontManager.geist(size: 42, weight: .regular))
                            .foregroundColor(Color.emailGlassMutedText(colorScheme))
                        Text("No matching emails")
                            .font(FontManager.geist(size: 18, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                        Text("Try different keywords in \(scopeTitle.lowercased()) or check your spelling.")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(Color.emailGlassMutedText(colorScheme))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                    .padding(.horizontal, 20)
                    .appAmbientCardStyle(
                        colorScheme: colorScheme,
                        variant: .topLeading,
                        cornerRadius: 24,
                        highlightStrength: 0.28
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Search Results")
                                .font(FontManager.geist(size: 18, weight: .semibold))
                                .foregroundColor(Color.appTextPrimary(colorScheme))
                            Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s") in \(scopeTitle.lowercased())")
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(Color.emailGlassMutedText(colorScheme))
                        }

                        VStack(spacing: 8) {
                            ForEach(searchResults) { email in
                                Button(action: {
                                    onEmailTap(email)
                                }) {
                                    EmailRow(
                                        email: email,
                                        onDelete: onDeleteEmail,
                                        onMarkAsUnread: onMarkAsUnread,
                                        presentationStyle: presentationStyle
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(18)
                    .appAmbientCardStyle(
                        colorScheme: colorScheme,
                        variant: .topLeading,
                        cornerRadius: 24,
                        highlightStrength: 0.34
                    )
                }

                Spacer()
                    .frame(height: 100)
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
        }
    }
}

#Preview {
    EmailSearchResultsView(
        scopeTitle: "Inbox",
        searchText: "test",
        searchResults: Email.sampleEmails,
        isLoading: false,
        onEmailTap: { _ in },
        onDeleteEmail: { _ in },
        onMarkAsUnread: { _ in }
    )
}
