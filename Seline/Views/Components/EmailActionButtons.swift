import SwiftUI

struct EmailActionButtons: View {
    let onReply: () -> Void
    let onForward: () -> Void
    let onDelete: () -> Void
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

            // Delete Button
            ActionButton(
                icon: "trash",
                label: "Delete",
                colorScheme: colorScheme,
                action: onDelete
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                .fill(colorScheme == .dark
                    ? Color.clear // No background in dark mode
                    : Color.white // Clean white for light mode
                )
        )
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
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.md)
                    .fill(
                        colorScheme == .dark
                            ? Color(red: 0.15, green: 0.15, blue: 0.16) // Keep dark mode as is
                            : Color(red: 0.98, green: 0.98, blue: 0.98) // Very light gray for individual buttons in light mode
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: ShadcnRadius.md)
                            .stroke(
                                colorScheme == .dark
                                    ? Color.clear
                                    : Color.gray.opacity(0.1),
                                lineWidth: 0.5
                            )
                    )
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
            onDelete: { print("Delete tapped") }
        )

        EmailActionButtons(
            onReply: { print("Reply tapped") },
            onForward: { print("Forward tapped") },
            onDelete: { print("Delete tapped") }
        )
        .preferredColorScheme(.dark)
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}