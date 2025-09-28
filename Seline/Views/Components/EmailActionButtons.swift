import SwiftUI

struct EmailActionButtons: View {
    let onReply: () -> Void
    let onForward: () -> Void
    let onDelete: () -> Void
    let onOpenInGmail: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            // Reply Button
            ActionButton(
                icon: "arrowshape.turn.up.left",
                label: "Reply",
                colorScheme: colorScheme,
                action: onReply
            )

            // Forward Button
            ActionButton(
                icon: "arrowshape.turn.up.right",
                label: "Forward",
                colorScheme: colorScheme,
                action: onForward
            )

            // Open in Gmail Button
            ActionButton(
                icon: "envelope.fill",
                label: "Gmail",
                colorScheme: colorScheme,
                action: onOpenInGmail
            )

            // Delete Button
            ActionButton(
                icon: "trash",
                label: "Delete",
                colorScheme: colorScheme,
                action: onDelete
            )
        }
        .padding(.horizontal, 20)
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                // Label
                Text(label)
                    .font(FontManager.geist(size: .small, weight: .medium))
                    .foregroundColor(Color.shadcnForeground(colorScheme))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                    .fill(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.16) : Color.white)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 20) {
        EmailActionButtons(
            onReply: { print("Reply tapped") },
            onForward: { print("Forward tapped") },
            onDelete: { print("Delete tapped") },
            onOpenInGmail: { print("Open in Gmail tapped") }
        )

        EmailActionButtons(
            onReply: { print("Reply tapped") },
            onForward: { print("Forward tapped") },
            onDelete: { print("Delete tapped") },
            onOpenInGmail: { print("Open in Gmail tapped") }
        )
        .preferredColorScheme(.dark)
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}