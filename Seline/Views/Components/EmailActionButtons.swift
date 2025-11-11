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
    @State private var showActionMenu = false

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
        HStack(spacing: 12) {
            Spacer()

            // Reply Button - Pill Icon Button
            Button(action: onReply) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(Color(red: 0.2, green: 0.5, blue: 1.0))
                    )
            }

            // Forward Button - Pill Icon Button
            Button(action: onForward) {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(Color(red: 0.2, green: 0.5, blue: 1.0))
                    )
            }

            // More Actions Menu Button - Pill Icon Button
            Button(action: { showActionMenu = true }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(Color(red: 0.2, green: 0.5, blue: 1.0))
                    )
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.clear)
        .sheet(isPresented: $showActionMenu) {
            ActionMenuSheet(
                showActionMenu: $showActionMenu,
                onForward: onForward,
                onAddEvent: onAddEvent,
                onSave: onSave,
                onDelete: onDelete
            )
        }
    }
}

struct ActionMenuSheet: View {
    @Binding var showActionMenu: Bool
    let onForward: () -> Void
    let onAddEvent: (() -> Void)?
    let onSave: (() -> Void)?
    let onDelete: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
                    .frame(width: 40, height: 4)

                Text("Actions")
                    .font(.system(size: 18, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
            .background(Color.clear)

            Divider()
                .padding(.horizontal, 16)

            // Menu Items
            ScrollView {
                VStack(spacing: 2) {
                    // Forward
                    ActionMenuItem(
                        icon: "arrowshape.turn.up.right",
                        title: "Forward",
                        subtitle: "Send to another recipient",
                        isDangerous: false,
                        action: {
                            showActionMenu = false
                            onForward()
                        }
                    )

                    // Add Event (if available)
                    if let onAddEvent = onAddEvent {
                        ActionMenuItem(
                            icon: "calendar.badge.plus",
                            title: "Add Event",
                            subtitle: "Create calendar event",
                            isDangerous: false,
                            action: {
                                showActionMenu = false
                                onAddEvent()
                            }
                        )
                    }

                    // Save (if available)
                    if let onSave = onSave {
                        ActionMenuItem(
                            icon: "folder.badge.plus",
                            title: "Save",
                            subtitle: "Save to folder",
                            isDangerous: false,
                            action: {
                                showActionMenu = false
                                onSave()
                            }
                        )
                    }

                    Divider()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                    // Delete
                    ActionMenuItem(
                        icon: "trash",
                        title: "Delete",
                        subtitle: "Remove email",
                        isDangerous: true,
                        action: {
                            showActionMenu = false
                            onDelete()
                        }
                    )
                }
            }

            Spacer()

            // Close Button
            Button(action: { showActionMenu = false }) {
                Text("Close")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.2, green: 0.5, blue: 1.0))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct ActionMenuItem: View {
    let icon: String
    let title: String
    let subtitle: String
    let isDangerous: Bool
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isDangerous ? .red : Color(red: 0.2, green: 0.5, blue: 1.0))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isDangerous ? .red : (colorScheme == .dark ? .white : .black))

                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .contentShape(Rectangle())
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