import SwiftUI

struct EmailActionButtons: View {
    let email: Email
    let onReply: () -> Void
    let onForward: () -> Void
    let onDelete: () -> Void
    let onMarkAsUnread: () -> Void
    let onAddEvent: (() -> Void)?
    @Environment(\.colorScheme) var colorScheme

    init(email: Email, onReply: @escaping () -> Void, onForward: @escaping () -> Void, onDelete: @escaping () -> Void, onMarkAsUnread: @escaping () -> Void, onAddEvent: (() -> Void)? = nil) {
        self.email = email
        self.onReply = onReply
        self.onForward = onForward
        self.onDelete = onDelete
        self.onMarkAsUnread = onMarkAsUnread
        self.onAddEvent = onAddEvent
    }

    var body: some View {
        HStack(spacing: 10) {
            // Reply Button
            ActionButtonWithText(
                icon: "arrowshape.turn.up.left",
                text: "Reply",
                action: onReply,
                colorScheme: colorScheme
            )

            // Forward Button
            ActionButtonWithText(
                icon: "arrowshape.turn.up.right",
                text: "Forward",
                action: onForward,
                colorScheme: colorScheme
            )

            // Add Event Button (if provided)
            if let onAddEvent = onAddEvent {
                ActionButtonWithText(
                    icon: "calendar.badge.plus",
                    text: "Event",
                    action: onAddEvent,
                    colorScheme: colorScheme,
                    isHighlighted: true
                )
            }

            // Delete Button
            ActionButtonWithText(
                icon: "trash",
                text: "Delete",
                action: onDelete,
                colorScheme: colorScheme,
                isDangerous: true
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
    }
}

struct ActionButtonWithText: View {
    let icon: String
    let text: String
    let action: () -> Void
    let colorScheme: ColorScheme
    let isDangerous: Bool
    let isHighlighted: Bool

    init(icon: String, text: String, action: @escaping () -> Void, colorScheme: ColorScheme, isDangerous: Bool = false, isHighlighted: Bool = false) {
        self.icon = icon
        self.text = text
        self.action = action
        self.colorScheme = colorScheme
        self.isDangerous = isDangerous
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor((isDangerous || isHighlighted) ? .white : (colorScheme == .dark ? .white : .black))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isDangerous ? Color.red :
                    isHighlighted ? (colorScheme == .dark ? Color(red: 0.25, green: 0.40, blue: 0.55) : Color.black) :
                    (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                )
        )
        .buttonStyle(PlainButtonStyle())
    }
}

struct MinimalisticActionButton: View {
    let icon: String
    let action: () -> Void
    let colorScheme: ColorScheme
    let isDangerous: Bool

    init(icon: String, action: @escaping () -> Void, colorScheme: ColorScheme, isDangerous: Bool = false) {
        self.icon = icon
        self.action = action
        self.colorScheme = colorScheme
        self.isDangerous = isDangerous
    }

    private var iconColor: Color {
        if isDangerous {
            return Color.red
        }
        return colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7)
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.05)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnRadius.sm)
                        .fill(backgroundColor)
                )
        }
        .buttonStyle(PlainButtonStyle())
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