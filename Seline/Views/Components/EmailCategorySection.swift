import SwiftUI

struct EmailCategorySection: View {
    let section: EmailSection
    @Binding var isExpanded: Bool
    let onEmailTap: (Email) -> Void
    let onDeleteEmail: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    @Environment(\.colorScheme) var colorScheme

    // Computed properties for colors
    private var iconColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)
    }

    private var badgeColor: Color {
        Color(red: 0.29, green: 0.29, blue: 0.29)
    }

    private var headerBackground: Color {
        Color.clear
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.05)
    }

    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }

    private var emptyTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header with title and count
            cardHeader

            // Email list - collapsible
            if isExpanded {
                if section.emailCount > 0 {
                    emailList
                } else {
                    emptyState
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: shadowColor, radius: 8, x: 0, y: 2)
    }

    private var cardHeader: some View {
        HStack(spacing: 12) {
            Text(section.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.shadcnForeground(colorScheme))

            Spacer()

            // Count badge - clickable to expand/collapse
            if section.emailCount > 0 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    countBadge
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(headerBackground)
    }

    private var countBadge: some View {
        Text("\(section.emailCount)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .frame(minWidth: 24, minHeight: 24)
            .padding(.horizontal, 6)
            .background(Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)))
    }

    private var emailList: some View {
        VStack(spacing: 0) {
            ForEach(Array(section.emails.enumerated()), id: \.element.id) { index, email in
                emailRowButton(email: email)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func emailRowButton(email: Email) -> some View {
        Button(action: {
            HapticManager.shared.email()
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

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("No emails")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(emptyTextColor)
            Spacer()
        }
        .padding(.vertical, 20)
    }
}

#Preview {
    let sampleEmails = Email.sampleEmails
    let section = EmailSection(
        timePeriod: .morning,
        emails: Array(sampleEmails.prefix(3))
    )

    return VStack {
        EmailCategorySection(
            section: section,
            isExpanded: .constant(true),
            onEmailTap: { email in
                print("Tapped email: \(email.subject)")
            },
            onDeleteEmail: { email in
                print("Delete email: \(email.subject)")
            },
            onMarkAsUnread: { email in
                print("Mark as unread: \(email.subject)")
            }
        )

        EmailCategorySection(
            section: EmailSection(timePeriod: .afternoon, emails: [sampleEmails[0]]),
            isExpanded: .constant(false),
            onEmailTap: { email in
                print("Tapped email: \(email.subject)")
            },
            onDeleteEmail: { email in
                print("Delete email: \(email.subject)")
            },
            onMarkAsUnread: { email in
                print("Mark as unread: \(email.subject)")
            }
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}