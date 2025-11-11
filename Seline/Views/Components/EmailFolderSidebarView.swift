import SwiftUI

struct EmailFolderSidebarView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = EmailFolderSidebarViewModel()
    @Environment(\.colorScheme) var colorScheme
    @State private var showCreateFolderSheet = false
    @State private var newFolderName = ""
    @State private var selectedColor = "#333333"

    let colors = [
        "#333333", // Dark gray
        "#1a1a1a", // Darker gray
        "#4a4a4a", // Medium gray
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Email Folders")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                Button(action: { showCreateFolderSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                colorScheme == .dark ?
                    Color(red: 0.15, green: 0.15, blue: 0.15) :
                    Color(red: 0.95, green: 0.95, blue: 0.95)
            )

            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

            // Folders list
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    if viewModel.isLoading {
                        ProgressView()
                            .padding()
                    } else if viewModel.folders.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.system(size: 28))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                            Text("No Folders")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                            Text("Create your first folder")
                                .font(.system(size: 12))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(viewModel.folders) { folder in
                            NavigationLink(destination: SavedEmailsListView(folder: folder)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)

                                        if let count = viewModel.folderEmailCounts[folder.id] {
                                            Text("\(count) email\(count != 1 ? "s" : "")")
                                                .font(.system(size: 11))
                                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ?
                                            Color.white.opacity(0.15) :
                                            Color.black.opacity(0.08)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.deleteFolder(folder)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

        }
        .background(
            colorScheme == .dark ?
                Color(red: 0.1, green: 0.1, blue: 0.1) :
                Color.white
        )
        .onAppear {
            viewModel.loadFolders()
        }
        .sheet(isPresented: $showCreateFolderSheet) {
            NavigationStack {
                Form {
                    Section("Folder Name") {
                        TextField("Enter folder name", text: $newFolderName)
                    }
                }
                .navigationTitle("New Folder")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showCreateFolderSheet = false
                            newFolderName = ""
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Create") {
                            if !newFolderName.trimmingCharacters(in: .whitespaces).isEmpty {
                                viewModel.createFolder(name: newFolderName)
                                showCreateFolderSheet = false
                                newFolderName = ""
                            }
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
class EmailFolderSidebarViewModel: ObservableObject {
    @Published var folders: [CustomEmailFolder] = []
    @Published var folderEmailCounts: [UUID: Int] = [:]
    @Published var isLoading = false

    private let emailService = EmailService.shared

    func loadFolders() {
        isLoading = true
        Task {
            do {
                folders = try await emailService.fetchSavedFolders()

                // Load email counts for each folder
                for folder in folders {
                    do {
                        let count = try await emailService.getSavedEmailCount(in: folder.id)
                        folderEmailCounts[folder.id] = count
                    } catch {
                        // Continue even if count fails
                    }
                }

                isLoading = false
            } catch {
                print("Error loading folders: \(error)")
                isLoading = false
            }
        }
    }

    func createFolder(name: String) {
        Task {
            do {
                let newFolder = try await emailService.createEmailFolder(name: name, color: "#333333")
                folders.append(newFolder)
                folderEmailCounts[newFolder.id] = 0
            } catch {
                print("Error creating folder: \(error)")
            }
        }
    }

    func deleteFolder(_ folder: CustomEmailFolder) {
        Task {
            do {
                try await emailService.deleteEmailFolder(id: folder.id)
                folders.removeAll { $0.id == folder.id }
                folderEmailCounts.removeValue(forKey: folder.id)
            } catch {
                print("Error deleting folder: \(error)")
            }
        }
    }
}

#Preview {
    EmailFolderSidebarView(isPresented: .constant(true))
}
