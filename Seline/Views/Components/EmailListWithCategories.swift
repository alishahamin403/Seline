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
            VStack(spacing: 12) {
                switch loadingState {
                case .idle:
                    EmptyView()

                case .loading:
                    VStack(spacing: 12) {
                        ForEach(TimePeriod.allCases, id: \.self) { period in
                            CategoryLoadingPlaceholder(timePeriod: period)
                        }
                    }

                case .loaded(_):
                    if sections.isEmpty {
                        EmptyEmailsView()
                    } else {
                        // Only show cards with emails
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
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 80) // Extra padding at bottom for compose button
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

    private var cardBackground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var headerBackground: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.05)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Card header placeholder
            placeholderHeader

            // Email row placeholders
            placeholderRows
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(strokeColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 8, x: 0, y: 2)
    }

    private var placeholderHeader: some View {
        HStack(spacing: 12) {
            placeholderRect(width: 90, height: 15, opacity: 0.3)

            Spacer()

            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                .frame(width: 18, height: 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(headerBackground)
    }

    private var placeholderRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { index in
                EmailRowPlaceholder()
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func placeholderRect(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity))
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

struct EmailRowPlaceholder: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar placeholder
            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                // Sender name placeholder
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                    .frame(width: 140, height: 13)
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                // Subject placeholder
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                    .frame(width: 200, height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            Spacer()

            // Time placeholder
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                .frame(width: 35, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct EmptyEmailsView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Text("No Emails Today")
                .font(FontManager.geist(size: .title2, weight: .semibold))
                .foregroundColor(Color.shadcnForeground(colorScheme))
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
