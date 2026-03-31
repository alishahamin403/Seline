import SwiftUI

struct FolderSidebarView: View {
    @Binding var isPresented: Bool
    @Binding var selectedFolderId: UUID?
    @Binding var showUnfiledNotesOnly: Bool
    @Binding var showSidebarNotesSelection: Bool
    let isNotesHomeSelected: Bool
    let onOpenHome: (() -> Void)?
    let onActivateNotesPage: (() -> Void)?
    let onOpenJournal: (() -> Void)?
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""
    @State private var collapsedFolders: Set<UUID> = []
    @State private var selectedFolderForNote: NoteFolder? = nil
    @State private var showingTrash = false
    @State private var searchText = ""

    private var sidebarBackgroundColor: Color {
        colorScheme == .dark ? Color.black : .white
    }

    private var searchFieldFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color.black.opacity(0.40)
    }

    private func sidebarRowFill(isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    // Computed property to organize folders by hierarchy (excluding special system folders)
    var organizedFolders: [(folder: NoteFolder, depth: Int)] {
        var result: [(folder: NoteFolder, depth: Int)] = []

        // Get root folders (no parent), excluding special folders handled elsewhere.
        let rootFolders = notesManager.folders.filter {
            $0.parentFolderId == nil && $0.name != "Receipts" && $0.name != "Journal"
        }

        for rootFolder in rootFolders {
            result.append((rootFolder, 0))
            if !collapsedFolders.contains(rootFolder.id) {
                addChildFolders(of: rootFolder.id, depth: 1, to: &result)
            }
        }

        return result
    }

    private var filteredOrganizedFolders: [(folder: NoteFolder, depth: Int)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return organizedFolders }
        return organizedFolders.filter { item in
            item.folder.name.lowercased().contains(query)
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var unfiledNotesCount: Int {
        notesManager.notes.filter { note in
            !note.isPinned &&
            note.folderId == nil &&
            !note.isJournalEntry &&
            !note.isJournalWeeklyRecap
        }.count
    }

    var body: some View {
        ZStack {
            sidebarBackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.35))

                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(FontManager.geist(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(searchFieldFillColor)
                    )

                    Button(action: {
                        HapticManager.shared.buttonTap()
                        showingNewFolderAlert = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.55))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel("New folder")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(sidebarBackgroundColor)
                .frame(maxWidth: .infinity)

                // Scrollable content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                    // All Notes option
                    if !isSearching {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BROWSE")
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(sectionLabelColor)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 6)

                            Button(action: {
                                HapticManager.shared.selection()
                                onOpenHome?()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isPresented = false
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "house")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                                        .frame(width: 22)
                                    Text("Home")
                                        .font(FontManager.geist(size: 15, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.88))
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(sidebarRowFill(isSelected: isNotesHomeSelected))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                HapticManager.shared.selection()
                                onActivateNotesPage?()
                                selectedFolderId = nil
                                showUnfiledNotesOnly = true
                                showSidebarNotesSelection = true
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isPresented = false
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "tray")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                                        .frame(width: 22)
                                    Text("Unfiled")
                                        .font(FontManager.geist(size: 15, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.88))
                                    Spacer()
                                    Text("\(unfiledNotesCount)")
                                        .font(FontManager.geist(size: 12, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(sidebarRowFill(isSelected: showUnfiledNotesOnly && showSidebarNotesSelection))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            // Journal removed from sidebar — accessible via Notes/Journal tab toggle
                        }
                    }

                    // Folders section
                    if !notesManager.folders.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FOLDERS")
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(sectionLabelColor)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 6)

                            ForEach(filteredOrganizedFolders, id: \.folder.id) { item in
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
                                        onActivateNotesPage?()
                                        selectedFolderId = item.folder.id
                                        showUnfiledNotesOnly = false
                                        showSidebarNotesSelection = true
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

                    if isSearching && filteredOrganizedFolders.isEmpty {
                        VStack(spacing: 8) {
                            Text("No folders found")
                                .font(FontManager.geist(size: 15, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                            Text("Try another search term")
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                    }

                    // Trash section
                    if !isSearching {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TRASH")
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(sectionLabelColor)
                                .textCase(.uppercase)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 6)

                            Button(action: {
                                HapticManager.shared.selection()
                                showingTrash = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                                        .frame(width: 22)
                                    Text("Deleted Items")
                                        .font(FontManager.geist(size: 15, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.88))
                                    Spacer()
                                    let count = notesManager.deletedNotes.count + notesManager.deletedFolders.count
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(FontManager.geist(size: 12, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    // Empty state
                    if notesManager.folders.isEmpty && !isSearching {
                        VStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.system(size: 36, weight: .light))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.25) : .black.opacity(0.2))
                            Text("No folders yet")
                                .font(FontManager.geist(size: 15, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
                            Text("Create a folder to organize your notes")
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    }

                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(sidebarBackgroundColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // Initialize with all root folders collapsed
            let rootFolders = notesManager.folders.filter { $0.parentFolderId == nil }
            collapsedFolders = Set(rootFolders.map { $0.id })
        }
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
    .presentationBg()
        .sheet(isPresented: $showingTrash) {
            TrashView(isPresented: $showingTrash)
        }
    .presentationBg()
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

    private var sectionRowFill: Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Indentation based on depth
            if depth > 0 {
                Spacer()
                    .frame(width: CGFloat(depth * 20))
            }

            // Collapse/Expand chevron
            Group {
                if hasChildren && depth < 2 {
                    Button(action: {
                        HapticManager.shared.selection()
                        onToggleCollapse()
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Spacer()
                        .frame(width: 16)
                }
            }

            Image(systemName: "folder")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.55) : .black.opacity(0.45))
                .frame(width: 20)

            Text(folder.name)
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.88))
                .lineLimit(1)

            Spacer(minLength: 0)

            if notesCount > 0 {
                Text("\(notesCount)")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(sectionRowFill)
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
