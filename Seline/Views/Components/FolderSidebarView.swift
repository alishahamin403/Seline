import SwiftUI

struct FolderSidebarView: View {
    @Binding var isPresented: Bool
    @Binding var selectedFolderId: UUID?
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var collapsedFolders: Set<UUID> = Set(NotesManager.shared.folders.map { $0.id })
    @State private var selectedFolderForNote: NoteFolder? = nil

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
            // Header
            HStack {
                Text("Folders")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // New folder button
            Button(action: {
                showingNewFolderAlert = true
            }) {
                HStack {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                    Text("New Folder")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ?
                            Color(red: 0.40, green: 0.65, blue: 0.80) :
                            Color(red: 0.20, green: 0.34, blue: 0.40))
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Folder list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(organizedFolders, id: \.folder.id) { item in
                        FolderRowView(
                            folder: item.folder,
                            depth: item.depth,
                            isCollapsed: collapsedFolders.contains(item.folder.id),
                            hasChildren: hasChildren(item.folder),
                            isSelected: selectedFolderId == item.folder.id,
                            onToggleCollapse: {
                                withAnimation {
                                    if collapsedFolders.contains(item.folder.id) {
                                        collapsedFolders.remove(item.folder.id)
                                    } else {
                                        collapsedFolders.insert(item.folder.id)
                                    }
                                }
                            },
                            onTap: {
                                selectedFolderId = item.folder.id
                                withAnimation {
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
                                    // Store parent ID for subfolder creation
                                }
                            },
                            onCreateNote: { folder in
                                selectedFolderForNote = folder
                            }
                        )
                    }

                    if notesManager.folders.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "folder")
                                .font(.system(size: 48, weight: .light))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                            Text("No folders yet")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                            Text("Create a folder to organize your notes")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 20)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                .ignoresSafeArea()
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 5, y: 0)
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

    var body: some View {
        HStack(spacing: 8) {
            // Indentation based on depth (reduced from 20 to 12)
            if depth > 0 {
                Spacer()
                    .frame(width: CGFloat(depth * 12))
            }

            // Collapse/Expand chevron (only for folders with children and depth < 2)
            if hasChildren && depth < 2 {
                Button(action: {
                    onToggleCollapse()
                }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(PlainButtonStyle())
            } else if hasChildren || depth > 0 {
                // Spacer to align folders without collapse button
                Spacer()
                    .frame(width: 16)
            }

            Button(action: {
                onTap()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text(folder.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Add note button
            Button(action: {
                onCreateNote(folder)
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    isSelected ?
                        (colorScheme == .dark ?
                            Color(red: 0.40, green: 0.65, blue: 0.80).opacity(0.3) :
                            Color(red: 0.20, green: 0.34, blue: 0.40).opacity(0.2)) :
                        (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                )
        )
        .onLongPressGesture {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()

            showingActionSheet = true
        }
        .confirmationDialog("Folder Options", isPresented: $showingActionSheet, titleVisibility: .visible) {
            Button("Rename") {
                renameFolderName = folder.name
                showingRenameAlert = true
            }
            // Only show create subfolder if depth < 2
            if depth < 2 {
                Button("Create Subfolder") {
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
