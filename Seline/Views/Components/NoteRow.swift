import SwiftUI

struct NoteRow: View {
    let note: Note
    let onPinToggle: (Note) -> Void
    let onTap: (Note) -> Void
    let onDelete: ((Note) -> Void)?
    let onSetReminder: ((Note) -> Void)?
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showDeleteConfirmation = false
    
    init(note: Note, onPinToggle: @escaping (Note) -> Void, onTap: @escaping (Note) -> Void, onDelete: ((Note) -> Void)? = nil, onSetReminder: ((Note) -> Void)? = nil) {
        self.note = note
        self.onPinToggle = onPinToggle
        self.onTap = onTap
        self.onDelete = onDelete
        self.onSetReminder = onSetReminder
    }

    var body: some View {
        rowContent
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if onDelete != nil {
                    Button(role: .destructive) {
                        HapticManager.shared.delete()
                        if note.isLocked {
                            showDeleteConfirmation = true
                        } else {
                            onDelete?(note)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash.fill")
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    HapticManager.shared.selection()
                    onPinToggle(note)
                } label: {
                    Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash.fill" : "pin.fill")
                }
                .tint(note.isPinned ? .gray : .primary)
            }
            .allowsParentScrolling()
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if note.isLocked {
                        Image(systemName: "lock.fill")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(iconMutedColor)
                    }

                    if !note.imageUrls.isEmpty {
                        Image(systemName: "paperclip")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(iconMutedColor)
                    }

                    if note.reminderDate != nil {
                        Image(systemName: note.isReminderDue ? "bell.badge.fill" : "bell.fill")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(note.isReminderDue ? .primary : iconMutedColor)
                    }

                    Text(note.title.isEmpty ? "Untitled" : note.title)
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(note.formattedDateModified)
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(secondaryTextColor)

                    if let folderId = note.folderId {
                        Text("•")
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(secondaryTextColor)

                        Text(notesManager.getFolderName(for: folderId))
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                    }

                    if let reminderDate = note.reminderDate {
                        Text("•")
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(note.isReminderDue ? .primary : secondaryTextColor)

                        Text(formatReminderDate(reminderDate))
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(note.isReminderDue ? .primary : secondaryTextColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
            .scrollSafeTapAction(minimumDragDistance: 3) {
                onTap(note)
            }
            .allowsParentScrolling()

            Button {
                onPinToggle(note)
            } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(note.isPinned ? pinActiveColor : pinInactiveColor)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .allowsParentScrolling()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rowBackgroundColor)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .allowsParentScrolling()
        .contextMenu {
            Button {
                HapticManager.shared.selection()
                onPinToggle(note)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }

            Button {
                HapticManager.shared.selection()
                onSetReminder?(note)
            } label: {
                if note.reminderDate != nil {
                    Label("Edit Reminder", systemImage: "bell.badge")
                } else {
                    Label("Set Reminder", systemImage: "bell")
                }
            }

            if onDelete != nil {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete Note", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete?(note)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(note.title)\"?")
        }
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.emailLightTextPrimary
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.68) : Color.emailLightTextSecondary
    }

    private var iconMutedColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.emailLightTextSecondary
    }

    private var pinActiveColor: Color {
        colorScheme == .dark ? Color.white : Color.emailLightTextPrimary
    }

    private var pinInactiveColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.emailLightTextSecondary
    }

    private var rowBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.emailLightSurface
    }

    private func formatReminderDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDate(date, inSameDayAs: now) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Today \(formatter.string(from: date))"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  calendar.isDate(date, inSameDayAs: tomorrow) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return "Tomorrow \(formatter.string(from: date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    let sampleNote1 = Note(title: "Waqar is a psycho", content: "This is a sample note")
    let sampleNote2 = Note(title: "Test", content: "Another note")
    var pinnedNote = Note(title: "Pinned Note", content: "This note is pinned")
    pinnedNote.isPinned = true

    return VStack(spacing: 0) {
        NoteRow(
            note: sampleNote1,
            onPinToggle: { _ in },
            onTap: { _ in },
            onDelete: { _ in }
        )

        NoteRow(
            note: pinnedNote,
            onPinToggle: { _ in },
            onTap: { _ in },
            onDelete: { _ in }
        )

        NoteRow(
            note: sampleNote2,
            onPinToggle: { _ in },
            onTap: { _ in },
            onDelete: { _ in }
        )
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
