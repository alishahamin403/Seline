import SwiftUI

struct EmailSearchResultsView: View {
    let searchText: String
    let searchResults: [Email]
    let isLoading: Bool
    let onEmailTap: (Email) -> Void
    let onDeleteEmail: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isLoading {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Searching...")
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else if searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.gray)
                        Text("No results found")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                        Text("Try different keywords or check your spelling")
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding(.horizontal, 20)
                } else {
                    VStack(spacing: 0) {
                        // Results header
                        HStack {
                            Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        // Search results list
                        ForEach(searchResults) { email in
                            Button(action: {
                                onEmailTap(email)
                            }) {
                                EmailRow(
                                    email: email,
                                    onDelete: onDeleteEmail,
                                    onMarkAsUnread: onMarkAsUnread
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }

                // Bottom padding
                Spacer()
                    .frame(height: 100)
            }
            .padding(.horizontal, 8)
        }
        .refreshable {
            // Refresh search when user pulls down
            Task {
                await EmailService.shared.searchEmails(query: searchText)
            }
        }
    }
}

#Preview {
    EmailSearchResultsView(
        searchText: "test",
        searchResults: Email.sampleEmails,
        isLoading: false,
        onEmailTap: { _ in },
        onDeleteEmail: { _ in },
        onMarkAsUnread: { _ in }
    )
}
