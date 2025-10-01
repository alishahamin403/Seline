import SwiftUI

struct EmailListWithCategories: View {
    let sections: [EmailSection]
    let loadingState: EmailLoadingState
    let onRefresh: () async -> Void
    let onDeleteEmail: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void

    @State private var expandedSections: Set<String> = Set(TimePeriod.allCases.map { $0.rawValue })
    @State private var selectedEmail: Email?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                switch loadingState {
                case .idle:
                    EmptyView()

                case .loading:
                    VStack(spacing: 16) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            CategoryLoadingPlaceholder(timePeriod: period)
                        }
                    }

                case .loaded(_):
                    if sections.isEmpty {
                        EmptyEmailsView()
                    } else {
                        ForEach(sections) { section in
                            EmailCategorySection(
                                section: section,
                                isExpanded: Binding(
                                    get: { expandedSections.contains(section.timePeriod.rawValue) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedSections.insert(section.timePeriod.rawValue)
                                        } else {
                                            expandedSections.remove(section.timePeriod.rawValue)
                                        }
                                    }
                                ),
                                onEmailTap: { email in
                                    selectedEmail = email
                                },
                                onDeleteEmail: onDeleteEmail,
                                onMarkAsUnread: onMarkAsUnread
                            )
                        }
                    }

                case .error(let message):
                    ErrorView(message: message, onRetry: {
                        Task {
                            await onRefresh()
                        }
                    })
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 2)
        }
        .hideScrollContentInsetIfAvailable()
        .refreshable {
            await onRefresh()
        }
        .sheet(item: $selectedEmail) { email in
            EmailDetailView(email: email)
        }
    }
}

struct CategoryLoadingPlaceholder: View {
    let timePeriod: TimePeriod
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header placeholder
            HStack {
                Image(systemName: timePeriod.icon)
                    .font(FontManager.geist(size: .body, weight: .medium))
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme).opacity(0.5))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                        .frame(width: 80, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 2))

                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                        .frame(width: 120, height: 10)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(FontManager.geist(size: .caption, weight: .medium))
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme).opacity(0.3))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(Color.shadcnMuted(colorScheme).opacity(0.2))

            // Email row placeholders
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { _ in
                    EmailRowPlaceholder()
                    Divider()
                        .background(Color.shadcnBorder(colorScheme))
                        .padding(.leading, 20)
                }
            }
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: ShadcnRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnRadius.md)
                .stroke(Color.shadcnBorder(colorScheme).opacity(0.5), lineWidth: 1)
        )
    }
}

struct EmailRowPlaceholder: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 6) {
                // Subject placeholder
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                    .frame(width: 200, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                // Snippet placeholder
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                    .frame(width: 280, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                // Sender placeholder
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                    .frame(width: 120, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            Spacer()

            // Time placeholder
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                .frame(width: 40, height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

struct EmptyEmailsView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))

            VStack(spacing: 8) {
                Text("No emails found")
                    .font(FontManager.geist(size: .title3, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Text("There are no emails in this folder for today.")
                    .font(FontManager.geist(size: .body, weight: .regular))
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 40)
    }
}

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Color.red)

            VStack(spacing: 8) {
                Text("Failed to load emails")
                    .font(FontManager.geist(size: .title3, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Text(message)
                    .font(FontManager.geist(size: .body, weight: .regular))
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    .multilineTextAlignment(.center)
            }

            Button(action: onRetry) {
                Text("Try Again")
                    .font(FontManager.geist(size: .body, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: ShadcnRadius.md))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.top, 40)
    }
}

#Preview {
    let sampleSections = [
        EmailSection(timePeriod: .morning, emails: Array(Email.sampleEmails.prefix(2))),
        EmailSection(timePeriod: .afternoon, emails: [Email.sampleEmails[2]]),
        EmailSection(timePeriod: .night, emails: [Email.sampleEmails[3]])
    ]

    return VStack {
        EmailListWithCategories(
            sections: sampleSections,
            loadingState: .loaded(Email.sampleEmails),
            onRefresh: {},
            onDeleteEmail: { _ in },
            onMarkAsUnread: { _ in }
        )
    }
    .background(Color.shadcnBackground(.light))
}
