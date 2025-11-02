import SwiftUI

struct TrashView: View {
    @Binding var isPresented: Bool
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingRestoreConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var selectedNote: DeletedNote?
    @State private var selectedFolder: DeletedFolder?
    @State private var showingEmptyTrashConfirmation = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()

                if notesManager.deletedNotes.isEmpty && notesManager.deletedFolders.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "trash")
                            .font(.system(size: 64, weight: .light))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                        Text("Trash is empty")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                        Text("Deleted items will appear here and be automatically removed after 30 days")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Info banner
                            HStack(spacing: 12) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.gray)

                                Text("Items are kept for 30 days before permanent deletion")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))

                                Spacer()
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color.gray.opacity(0.15) : Color.gray.opacity(0.1))
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                            // Deleted notes section
                            if !notesManager.deletedNotes.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("DELETED NOTES")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                                        Spacer()

                                        Text("\(notesManager.deletedNotes.count)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                    }
                                    .padding(.horizontal, 16)

                                    ForEach(notesManager.deletedNotes) { deletedNote in
                                        DeletedNoteRow(
                                            deletedNote: deletedNote,
                                            onRestore: {
                                                selectedNote = deletedNote
                                                showingRestoreConfirmation = true
                                            },
                                            onDelete: {
                                                selectedNote = deletedNote
                                                showingDeleteConfirmation = true
                                            }
                                        )
                                    }
                                }
                            }

                            // Deleted folders section
                            if !notesManager.deletedFolders.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("DELETED FOLDERS")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                                        Spacer()

                                        Text("\(notesManager.deletedFolders.count)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                    }
                                    .padding(.horizontal, 16)

                                    ForEach(notesManager.deletedFolders) { deletedFolder in
                                        DeletedFolderRow(
                                            deletedFolder: deletedFolder,
                                            onRestore: {
                                                selectedFolder = deletedFolder
                                                showingRestoreConfirmation = true
                                            },
                                            onDelete: {
                                                selectedFolder = deletedFolder
                                                showingDeleteConfirmation = true
                                            }
                                        )
                                    }
                                }
                            }

                            Spacer()
                                .frame(height: 40)
                        }
                    }
                }
            }
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !notesManager.deletedNotes.isEmpty || !notesManager.deletedFolders.isEmpty {
                        Button(action: {
                            showingEmptyTrashConfirmation = true
                        }) {
                            Text("Empty")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .alert("Restore Item", isPresented: $showingRestoreConfirmation) {
                Button("Cancel", role: .cancel) {
                    selectedNote = nil
                    selectedFolder = nil
                }
                Button("Restore") {
                    if let note = selectedNote {
                        notesManager.restoreNote(note)
                        selectedNote = nil
                    } else if let folder = selectedFolder {
                        notesManager.restoreFolder(folder)
                        selectedFolder = nil
                    }
                }
            } message: {
                if selectedNote != nil {
                    Text("Are you sure you want to restore this note?")
                } else {
                    Text("Are you sure you want to restore this folder?")
                }
            }
            .alert("Delete Permanently", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {
                    selectedNote = nil
                    selectedFolder = nil
                }
                Button("Delete", role: .destructive) {
                    if let note = selectedNote {
                        notesManager.permanentlyDeleteNote(note)
                        selectedNote = nil
                    } else if let folder = selectedFolder {
                        notesManager.permanentlyDeleteFolder(folder)
                        selectedFolder = nil
                    }
                }
            } message: {
                Text("This action cannot be undone. The item will be permanently deleted.")
            }
            .alert("Empty Trash", isPresented: $showingEmptyTrashConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Empty Trash", role: .destructive) {
                    emptyTrash()
                }
            } message: {
                Text("Are you sure you want to permanently delete all items in trash? This action cannot be undone.")
            }
        }
        .onAppear {
            // Load deleted items from Supabase
            Task {
                await notesManager.loadDeletedItemsFromSupabase()
            }
        }
    }

    private func emptyTrash() {
        // Permanently delete all items
        for note in notesManager.deletedNotes {
            notesManager.permanentlyDeleteNote(note)
        }

        for folder in notesManager.deletedFolders {
            notesManager.permanentlyDeleteFolder(folder)
        }
    }
}

// MARK: - Deleted Note Row

struct DeletedNoteRow: View {
    let deletedNote: DeletedNote
    let onRestore: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Note icon
                Image(systemName: "note.text")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    // Title
                    Text(deletedNote.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    // Preview
                    if !deletedNote.content.isEmpty {
                        Text(deletedNote.content)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            .lineLimit(2)
                    }

                    // Deletion info
                    HStack(spacing: 8) {
                        Text("Deleted \(timeAgo(deletedNote.deletedAt))")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                        Text("•")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                        Text("\(deletedNote.daysUntilPermanentDeletion) days remaining")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.orange)
                    }
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onRestore) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .medium))
                        Text("Restore")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                    )
                }

                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                        Text("Delete")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.red.opacity(0.2) : Color.red.opacity(0.1))
                    )
                }

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(
                    color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
                    radius: 8,
                    x: 0,
                    y: 2
                )
        )
        .padding(.horizontal, 16)
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Deleted Folder Row

struct DeletedFolderRow: View {
    let deletedFolder: DeletedFolder
    let onRestore: () -> Void
    let onDelete: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Folder icon
                Image(systemName: "folder.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color(hex: deletedFolder.color) ?? .gray)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    // Name
                    Text(deletedFolder.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    // Deletion info
                    HStack(spacing: 8) {
                        Text("Deleted \(timeAgo(deletedFolder.deletedAt))")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                        Text("•")
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                        Text("\(deletedFolder.daysUntilPermanentDeletion) days remaining")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.orange)
                    }
                }

                Spacer()
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onRestore) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14, weight: .medium))
                        Text("Restore")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                    )
                }

                Button(action: onDelete) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                        Text("Delete")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.red.opacity(0.2) : Color.red.opacity(0.1))
                    )
                }

                Spacer()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(
                    color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
                    radius: 8,
                    x: 0,
                    y: 2
                )
        )
        .padding(.horizontal, 16)
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    TrashView(isPresented: .constant(true))
}
