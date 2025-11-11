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
        HStack(spacing: 8) {
            // Reply Button - Primary
            ActionButtonWithText(
                icon: "arrowshape.turn.up.left",
                text: "Reply",
                action: onReply,
                colorScheme: colorScheme,
                style: .primary
            )

            // Forward Button - Primary
            ActionButtonWithText(
                icon: "arrowshape.turn.up.right",
                text: "Forward",
                action: onForward,
                colorScheme: colorScheme,
                style: .primary
            )

            // Add Event Button (if provided) - Secondary
            if let onAddEvent = onAddEvent {
                ActionButtonWithText(
                    icon: "calendar.badge.plus",
                    text: "Event",
                    action: onAddEvent,
                    colorScheme: colorScheme,
                    style: .secondary
                )
            }

            // Save Button (if provided) - Secondary
            if let onSave = onSave {
                ActionButtonWithText(
                    icon: "folder.badge.plus",
                    text: "Save",
                    action: onSave,
                    colorScheme: colorScheme,
                    style: .secondary
                )
            }

            // Delete Button - Dangerous (Red)
            ActionButtonWithText(
                icon: "trash",
                text: "Delete",
                action: onDelete,
                colorScheme: colorScheme,
                isDangerous: true,
                style: .tertiary
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
    var style: ActionButtonStyle = .secondary

    init(icon: String, text: String, action: @escaping () -> Void, colorScheme: ColorScheme, isDangerous: Bool = false, isHighlighted: Bool = false, style: ActionButtonStyle = .secondary) {
        self.icon = icon
        self.text = text
        self.action = action
        self.colorScheme = colorScheme
        self.isDangerous = isDangerous
        self.isHighlighted = isHighlighted
        self.style = style
    }

    private var backgroundColor: Color {
        if isDangerous {
            return Color.red
        }

        switch style {
        case .primary:
            return Color(red: 0.2, green: 0.5, blue: 1.0) // Blue tint
        case .secondary:
            return Color.clear
        case .tertiary:
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
        }
    }

    private var foregroundColor: Color {
        if isDangerous {
            return .white
        }

        switch style {
        case .primary:
            return .white
        case .secondary:
            return colorScheme == .dark ? Color.white : Color.black
        case .tertiary:
            return colorScheme == .dark ? Color.white : Color.black
        }
    }

    private var borderColor: Color? {
        switch style {
        case .secondary:
            return colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)
        default:
            return nil
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(text)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    borderColor ?? Color.clear,
                    lineWidth: 1.2
                )
        )
        .buttonStyle(PlainButtonStyle())
    }
}

enum ActionButtonStyle {
    case primary    // Filled blue (Reply, Forward)
    case secondary  // Outlined (Save, Event)
    case tertiary   // Light background fallback
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