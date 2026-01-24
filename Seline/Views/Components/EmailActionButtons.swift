import SwiftUI

struct EmailActionButtons: View {
    let email: Email
    let onReply: () -> Void
    let onForward: () -> Void
    let onDelete: () -> Void
    let onMarkAsUnread: () -> Void
    let onAddEvent: (() -> Void)?
    let onSave: (() -> Void)?
    @Environment(\.colorScheme) var colorScheme

    init(email: Email, onReply: @escaping () -> Void, onForward: @escaping () -> Void, onDelete: @escaping () -> Void, onMarkAsUnread: @escaping () -> Void, onAddEvent: (() -> Void)? = nil, onSave: (() -> Void)? = nil) {
        self.email = email
        self.onReply = onReply
        self.onForward = onForward
        self.onDelete = onDelete
        self.onMarkAsUnread = onMarkAsUnread
        self.onAddEvent = onAddEvent
        self.onSave = onSave
    }

    var body: some View {
        HStack(spacing: 10) {
            Spacer()

            // Reply Button - Icon Only
            Button(action: onReply) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(red: 0.2, green: 0.5, blue: 1.0)))
            }

            // Forward Button - Icon Only
            Button(action: onForward) {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(red: 0.2, green: 0.5, blue: 1.0)))
            }

            // Event Button - Icon Only
            if let onAddEvent = onAddEvent {
                Button(action: onAddEvent) {
                    Image(systemName: "calendar.badge.plus")
                        .font(FontManager.geist(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)))
                }
            }

            // Save Button - Icon Only
            if let onSave = onSave {
                Button(action: onSave) {
                    Image(systemName: "folder.badge.plus")
                        .font(FontManager.geist(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)))
                }
            }

            // Delete Button - Icon Only (Red)
            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.red))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}


#Preview {
    VStack(spacing: 20) {
        EmailActionButtons(
            email: Email.sampleEmails.first!,
            onReply: { print("Reply tapped") },
            onForward: { print("Forward tapped") },
            onDelete: { print("Delete tapped") },
            onMarkAsUnread: { print("Mark as unread tapped") },
            onAddEvent: { print("Add Event tapped") }
        )

        EmailActionButtons(
            email: Email.sampleEmails.first!,
            onReply: { print("Reply tapped") },
            onForward: { print("Forward tapped") },
            onDelete: { print("Delete tapped") },
            onMarkAsUnread: { print("Mark as unread tapped") },
            onAddEvent: { print("Add Event tapped") }
        )
        .preferredColorScheme(.dark)
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}