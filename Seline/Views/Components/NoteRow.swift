import SwiftUI

struct NoteRow: View {
    let note: Note
    let onPinToggle: (Note) -> Void
    let onTap: (Note) -> Void
    let onDelete: ((Note) -> Void)?
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showDeleteConfirmation = false

    var body: some View {
        Button(action: {
            onTap(note)
        }) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    // Note title with lock icon and attachment indicator
                    HStack(spacing: 6) {
                        if note.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }

                        if !note.imageUrls.isEmpty {
                            Image(systemName: "paperclip")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }

                        Text(note.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Note preview or date/folder info
                    HStack(spacing: 8) {
                        Text(note.formattedDateModified)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                        if let folderId = note.folderId {
                            Text("•")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                            Text(notesManager.getFolderName(for: folderId))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
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
                        .font(.system(size: 12, weight: .medium))
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