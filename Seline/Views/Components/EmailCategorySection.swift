import SwiftUI

struct EmailCategorySection: View {
    let section: EmailSection
    @Binding var isExpanded: Bool
    let onEmailTap: (Email) -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    // Time period icon
                    Image(systemName: section.timePeriod.icon)
                        .font(FontManager.geist(size: .body, weight: .medium))
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                        .frame(width: 20)

                    // Title only
                    Text(section.title)
                        .font(FontManager.geist(size: .body, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()

                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(FontManager.geist(size: .caption, weight: .medium))
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                }
                .padding(.horizontal, 0)
                .padding(.vertical, 12)
            }
            .buttonStyle(PlainButtonStyle())

            // Email list
            if isExpanded {
                LazyVStack(spacing: 0) {
                    ForEach(section.emails) { email in
                        Button(action: {
                            onEmailTap(email)
                        }) {
                            EmailRow(email: email)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
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
            }
        )

        EmailCategorySection(
            section: EmailSection(timePeriod: .afternoon, emails: [sampleEmails[0]]),
            isExpanded: .constant(false),
            onEmailTap: { email in
                print("Tapped email: \(email.subject)")
            }
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}