import SwiftUI

struct FolderPickerView: View {
    @Binding var selectedFolderId: UUID?
    @Binding var isPresented: Bool
    @StateObject private var notesManager = NotesManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showingNewFolderAlert = false
    @State private var newFolderName = ""

    // Computed property to organize folders by hierarchy
    var organizedFolders: [(folder: NoteFolder, depth: Int)] {
        var result: [(folder: NoteFolder, depth: Int)] = []

        // Get root folders (no parent)
        let rootFolders = notesManager.folders.filter { $0.parentFolderId == nil }

        for rootFolder in rootFolders {
            result.append((rootFolder, 0))
            addChildFolders(of: rootFolder.id, depth: 1, to: &result)
        }

        return result
    }

    private func addChildFolders(of parentId: UUID, depth: Int, to result: inout [(folder: NoteFolder, depth: Int)]) {
        let children = notesManager.folders.filter { $0.parentFolderId == parentId }
        for child in children {
            result.append((child, depth))
            if depth < 2 {
                addChildFolders(of: child.id, depth: depth + 1, to: &result)
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Folder list
                ScrollView {
                    VStack(spacing: 12) {
                        // No folder option
                        Button(action: {
                            selectedFolderId = nil
                            isPresented = false
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 40)

                                Text("No Folder")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)

                                Spacer()

                                if selectedFolderId == nil {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        // Existing folders with hierarchy
                        ForEach(organizedFolders, id: \.folder.id) { item in
                            Button(action: {
                                selectedFolderId = item.folder.id
                                isPresented = false
                            }) {
                                HStack(spacing: 8) {
                                    // Indentation based on depth
                                    if item.depth > 0 {
                                        Spacer()
                                            .frame(width: CGFloat(item.depth * 12))
                                    }

                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(width: 32)

                                    Text(item.folder.name)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)

                                    Spacer()

                                    if selectedFolderId == item.folder.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // New folder button
                        Button(action: {
                            showingNewFolderAlert = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    .frame(width: 40)

                                Text("New Folder")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .background(
                (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                    .ignoresSafeArea()
            )
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
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
                    selectedFolderId = folder.id
                    newFolderName = ""
                    isPresented = false
                }
            }
        } message: {
            Text("Enter a name for your new folder. The note will be moved to this folder.")
        }
    }
}
