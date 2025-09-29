import SwiftUI

struct EmailRow: View {
    let email: Email
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
                // Sender avatar placeholder
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(email.sender.shortDisplayName.prefix(1).uppercased())
                            .font(FontManager.geist(size: .body, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    )

                // Email content
                VStack(alignment: .leading, spacing: 4) {
                    // Top row: sender name, subject preview, time
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            // Sender name
                            Text(email.sender.shortDisplayName)
                                .font(FontManager.geist(size: .body, weight: email.isRead ? .medium : .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .lineLimit(1)

                            // Subject
                            Text(email.subject)
                                .font(FontManager.geist(size: .small, weight: email.isRead ? .regular : .medium))
                                .foregroundColor(
                                    email.isRead ?
                                    (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)) :
                                    (colorScheme == .dark ? Color.white : Color.black)
                                )
                                .lineLimit(1)
                        }

                        Spacer()

                        // Time and indicators
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(email.formattedTime)
                                .font(FontManager.geist(size: .caption, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                            HStack(spacing: 4) {
                                if email.isImportant {
                                    Image(systemName: "exclamationmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.orange)
                                }

                                if email.hasAttachments {
                                    Image(systemName: "paperclip")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                }

                                if !email.isRead {
                                    Circle()
                                        .fill(colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40))
                                        .frame(width: 10, height: 10)
                                }
                            }
                        }
                    }

                }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 12)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 0) {
        ForEach(Email.sampleEmails.prefix(3)) { email in
            EmailRow(email: email)
        }
    }
    .background(Color.shadcnBackground(.light))
}