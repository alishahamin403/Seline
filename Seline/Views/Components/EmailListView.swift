import SwiftUI

struct EmailListView: View {
    let emails: [Email]
    let loadingState: EmailLoadingState
    let onRefresh: () async -> Void
    let onDeleteEmail: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedEmail: Email?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                switch loadingState {
                case .idle:
                    EmptyEmailState(
                        icon: "envelope",
                        title: "No emails loaded",
                        subtitle: "Pull down to refresh"
                    )

                case .loading:
                    LoadingEmailState()

                case .loaded(let loadedEmails):
                    if loadedEmails.isEmpty {
                        EmptyEmailState(
                            icon: "checkmark.circle",
                            title: "All caught up!",
                            subtitle: "No new emails today"
                        )
                    } else {
                        ForEach(loadedEmails) { email in
                            Button(action: {
                                selectedEmail = email
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

                case .error(let errorMessage):
                    ErrorEmailState(message: errorMessage)
                }

                // Bottom padding for tab bar
                Spacer()
                    .frame(height: 100)
            }
            .padding(.horizontal, 20)
        }
        .hideScrollContentInsetIfAvailable()
        .refreshable {
            await onRefresh()
        }
        .animation(.easeInOut(duration: 0.3), value: loadingState)
        .sheet(item: $selectedEmail) { email in
            EmailDetailView(email: email)
        }
    .presentationBg()
    }
}

struct LoadingEmailState: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.gray)

            Text("Loading emails...")
                .font(FontManager.geist(size: .body, weight: .medium))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

struct ErrorEmailState: View {
    let message: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(FontManager.geist(size: .title3, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Text(message)
                    .font(FontManager.geist(size: .body, weight: .regular))
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Loading state
        EmailListView(
            emails: [],
            loadingState: .loading,
            onRefresh: {},
            onDeleteEmail: { _ in },
            onMarkAsUnread: { _ in }
        )
        .frame(height: 200)

        Divider()

        // Loaded state with emails
        EmailListView(
            emails: Email.sampleEmails,
            loadingState: .loaded(Email.sampleEmails),
            onRefresh: {},
            onDeleteEmail: { _ in },
            onMarkAsUnread: { _ in }
        )
        .frame(height: 300)
    }
    .background(Color.shadcnBackground(.light))
}
