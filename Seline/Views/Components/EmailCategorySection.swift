import SwiftUI

struct EmailCategorySection: View {
    let section: EmailSection
    @Binding var isExpanded: Bool
    let onEmailTap: (Email) -> Void
    let onDeleteEmail: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header - matching home page style with count badge
            Button(action: {
                if section.emailCount > 0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack {
                    Text(section.title.uppercased())
                        .font(.system(size: 23, weight: .regular))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()

                    // Count badge - matching home page style
                    if section.emailCount > 0 {
                        Text("\(section.emailCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .white)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color(red: 0.20, green: 0.34, blue: 0.40))
                            )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.vertical, 12)
            .disabled(section.emailCount == 0)

            // Email list
            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(section.emails) { email in
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
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }

            // Separator line - always show (whether expanded or collapsed)
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                .frame(height: 1)
                .padding(.top, isExpanded ? 8 : 0)
        }
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