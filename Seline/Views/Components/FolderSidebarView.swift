import SwiftUI

struct FolderSidebarView: View {
    @Binding var isPresented: Bool
    @Binding var selectedFolderId: UUID?
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var collapsedFolders: Set<UUID> = []
    @State private var selectedFolderForNote: NoteFolder? = nil
    @State private var showingTrash = false

    // Computed property to organize folders by hierarchy
    var organizedFolders: [(folder: NoteFolder, depth: Int)] {
        var result: [(folder: NoteFolder, depth: Int)] = []

        // Get root folders (no parent)
        let rootFolders = notesManager.folders.filter { $0.parentFolderId == nil }

        for rootFolder in rootFolders {
            result.append((rootFolder, 0))
            if !collapsedFolders.contains(rootFolder.id) {
                addChildFolders(of: rootFolder.id, depth: 1, to: &result)
            }
        }

        return result
    }

    private func addChildFolders(of parentId: UUID, depth: Int, to result: inout [(folder: NoteFolder, depth: Int)]) {
        let children = notesManager.folders.filter { $0.parentFolderId == parentId }
        for child in children {
            result.append((child, depth))
            // Allow up to 3 tiers: depth 0 (parent), depth 1 (subfolder), depth 2 (sub-subfolder)
            if depth < 2 && !collapsedFolders.contains(child.id) {
                addChildFolders(of: child.id, depth: depth + 1, to: &result)
            }
        }
    }

    private func hasChildren(_ folder: NoteFolder) -> Bool {
        return notesManager.folders.contains { $0.parentFolderId == folder.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    // All Notes option
                    Button(action: {
                        HapticManager.shared.selection()
                        selectedFolderId = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "note.text")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 20)

                            Text("All Notes")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)

                            Spacer()

                            Text("\(notesManager.notes.count)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedFolderId == nil ?
                                    Color(red: 0.29, green: 0.29, blue: 0.29) :
                                    Color.clear
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Folders section
                    if !notesManager.folders.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("FOLDERS")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                            ForEach(organizedFolders, id: \.folder.id) { item in
                                FolderRowView(
                                    folder: item.folder,
                                    depth: item.depth,
                                    isCollapsed: collapsedFolders.contains(item.folder.id),
                                    hasChildren: hasChildren(item.folder),
                                    isSelected: selectedFolderId == item.folder.id,
                                    onToggleCollapse: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if collapsedFolders.contains(item.folder.id) {
                                                collapsedFolders.remove(item.folder.id)
                                            } else {
                                                collapsedFolders.insert(item.folder.id)
                                            }
                                        }
                                    },
                                    onTap: {
                                        HapticManager.shared.selection()
                                        selectedFolderId = item.folder.id
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isPresented = false
                                        }
                                    },
                                    onDelete: {
                                        notesManager.deleteFolder(item.folder)
                                    },
                                    onCreateSubfolder: { parentFolder in
                                        let depth = parentFolder.getDepth(in: notesManager.folders)
                                        if depth < 2 {
                                            showingNewFolderAlert = true
                                        }
                                    },
                                    onCreateNote: { folder in
                                        selectedFolderForNote = folder
                                    }
                                )
                            }
                        }
                    }

                    // Trash section
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("TRASH")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                        .padding(.top, 16)
                        .padding(.bottom, 4)

                        Button(action: {
                            HapticManager.shared.selection()
                            showingTrash = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 20)

                                Text("Deleted Items")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                Spacer()

                                if !notesManager.deletedNotes.isEmpty || !notesManager.deletedFolders.isEmpty {
                                    Text("\(notesManager.deletedNotes.count + notesManager.deletedFolders.count)")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 12)
                    }

                    // Empty state
                    if notesManager.folders.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.2) : .black.opacity(0.2))

                            Text("No folders yet")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                            Text("Create a folder to organize your notes")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }

                    Spacer()
                        .frame(height: 100)
                }
            }

            // Sticky Footer - New folder button
            VStack(spacing: 0) {
                Divider()
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                Button(action: {
                    HapticManager.shared.buttonTap()
                    showingNewFolderAlert = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                        Text("New Folder")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.29, green: 0.29, blue: 0.29))
                    )
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            (colorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.08) : Color(red: 0.98, green: 0.98, blue: 0.98))
                .ignoresSafeArea()
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 5, y: 0)
        .alert("New Folder", isPresented: $showingNewFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Create") {
                if !newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let folder = NoteFolder(name: newFolderName)
                    notesManager.addFolder(folder)
                    newFolderName = ""
                }
            }
        } message: {
            Text("Enter a name for your new folder")
        }
        .sheet(item: $selectedFolderForNote) { folder in
            NoteEditView(
                note: nil,
                isPresented: Binding(
                    get: { selectedFolderForNote != nil },
                    set: { if !$0 { selectedFolderForNote = nil } }
                ),
                initialFolderId: folder.id
            )
        }
        .sheet(isPresented: $showingTrash) {
            TrashView(isPresented: $showingTrash)
        }
    }
}

struct FolderRowView: View {
    let folder: NoteFolder
    let depth: Int
    let isCollapsed: Bool
    let hasChildren: Bool
    let isSelected: Bool
    let onToggleCollapse: () -> Void
    let onTap: () -> Void
    let onDelete: () -> Void
    let onCreateSubfolder: (NoteFolder) -> Void
    let onCreateNote: (NoteFolder) -> Void
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var notesManager = NotesManager.shared
    @State private var showingActionSheet = false
    @State private var showingSubfolderAlert = false
    @State private var newSubfolderName = ""
    @State private var showingRenameAlert = false
    @State private var renameFolderName = ""
    @State private var isHovering = false

    private var notesCount: Int {
        notesManager.notes.filter { $0.folderId == folder.id }.count
    }

    var body: some View {
        HStack(spacing: 8) {
                // Indentation based on depth
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth * 24))
                }

                // Collapse/Expand chevron - always reserve space for alignment
                Group {
                    if hasChildren && depth < 2 {
                        Button(action: {
                            HapticManager.shared.selection()
                            onToggleCollapse()
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        // Spacer to maintain alignment for folders without children or at max depth
                        Spacer()
                            .frame(width: 16)
                    }
                }

                // Folder icon
                Image(systemName: isSelected ? "folder.fill" : "folder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white : .black))
                    .frame(width: 20)

                // Folder name
                Text(folder.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white : .black))
                    .lineLimit(1)

                Spacer()

                // Note count badge
                if notesCount > 0 {
                    Text("\(notesCount)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : (colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)))
                }

                // Add note button - always visible
                Button(action: {
                    HapticManager.shared.buttonTap()
                    onCreateNote(folder)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : (colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6)))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isSelected ?
                        Color(red: 0.29, green: 0.29, blue: 0.29) :
                        Color.clear
                )
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.selection()
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            HapticManager.shared.selection()
            showingActionSheet = true
        }
        .confirmationDialog("Folder Options", isPresented: $showingActionSheet, titleVisibility: .visible) {
            Button("Rename") {
                renameFolderName = folder.name
                showingRenameAlert = true
            }
            // Only show create subfolder if depth < 2 (allows depth 0 and 1 to have children, max depth is 2)
            if depth < 2 {
                Button("Add Sub-Folder") {
                    showingSubfolderAlert = true
                }
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(folder.name)")
        }
        .alert("Rename Folder", isPresented: $showingRenameAlert) {
            TextField("Folder name", text: $renameFolderName)
            Button("Cancel", role: .cancel) {
                renameFolderName = ""
            }
            Button("Rename") {
                if !renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    var updatedFolder = folder
                    updatedFolder.name = renameFolderName
                    notesManager.updateFolder(updatedFolder)
                    renameFolderName = ""
                }
            }
        } message: {
            Text("Enter a new name for \"\(folder.name)\"")
        }
        .alert("Create Subfolder", isPresented: $showingSubfolderAlert) {
            TextField("Subfolder name", text: $newSubfolderName)
            Button("Cancel", role: .cancel) {
                newSubfolderName = ""
            }
            Button("Create") {
                if !newSubfolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let subfolder = NoteFolder(name: newSubfolderName, parentFolderId: folder.id)
                    notesManager.addFolder(subfolder)
                    newSubfolderName = ""
                }
            }
        } message: {
            Text("Create a subfolder under \"\(folder.name)\"")
        }
    }
}

// Helper extension to parse hex colors
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
