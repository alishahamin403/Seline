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
            .swipeActions(
                left: SwipeAction(
                    type: .delete,
                    icon: "trash.fill",
                    color: .red,
                    haptic: { HapticManager.shared.delete() },
                    action: {
                        // For locked notes, show confirmation (already handled by showDeleteConfirmation)
                        if note.isLocked {
                            showDeleteConfirmation = true
                        } else {
                            onDelete?(note)
                        }
                    }
                ),
                right: SwipeAction(
                    type: .pin,
                    icon: note.isPinned ? "pin.slash.fill" : "pin.fill",
                    color: note.isPinned ? .gray : .orange,
                    haptic: { HapticManager.shared.selection() },
                    action: {
                        onPinToggle(note)
                    }
                )
            )
    }

    private var rowContent: some View {
        Button(action: {
            onTap(note)
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // Note title with lock icon, reminder icon, and attachment indicator
                    HStack(spacing: 6) {
                        if note.isLocked {
                            Image(systemName: "lock.fill")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }

                        if !note.imageUrls.isEmpty {
                            Image(systemName: "paperclip")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }
                        
                        // Reminder icon - shows if note has a reminder
                        if note.reminderDate != nil {
                            Image(systemName: note.isReminderDue ? "bell.badge.fill" : "bell.fill")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(note.isReminderDue ? .orange : (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)))
                        }

                        Text(note.title)
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Note preview or date/folder info
                    HStack(spacing: 8) {
                        Text(note.formattedDateModified)
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                        if let folderId = note.folderId {
                            Text("•")
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                            Text(notesManager.getFolderName(for: folderId))
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                        }
                        
                        // Show reminder date if set
                        if let reminderDate = note.reminderDate {
                            Text("•")
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(note.isReminderDue ? .orange : .white.opacity(0.7))
                            
                            Text(formatReminderDate(reminderDate))
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(note.isReminderDue ? .orange : .white.opacity(0.7))
                        }

                        Spacer()
                    }
                }

                Spacer()

                // Pin button - aligned with count badge
                Button(action: {
                    onPinToggle(note)
                }) {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(
                            note.isPinned ?
                                (colorScheme == .dark ? Color.white : Color.black) :
                                (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        )
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button {
                HapticManager.shared.selection()
                onPinToggle(note)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            
            // Set Reminder option
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