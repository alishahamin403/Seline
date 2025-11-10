import SwiftUI

struct EmailFolderListView: View {
    @StateObject private var viewModel = EmailFolderListViewModel()
    @State private var showCreateFolderSheet = false
    @State private var showFolderActionSheet: CustomEmailFolder?
    @State private var editingFolderName: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGray6)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Email Folders")
                            .font(.title2)
                            .fontWeight(.bold)

                        Spacer()

                        Button(action: { showCreateFolderSheet = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color.white)

                    // Folders List
                    if viewModel.isLoading {
                        VStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(1.2)
                            Spacer()
                        }
                    } else if viewModel.folders.isEmpty {
                        VStack {
                            Spacer()
                            Image(systemName: "folder")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("No Folders Yet")
                                .font(.headline)
                                .foregroundColor(.gray)
                            Text("Create a folder to save emails")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        List {
                            ForEach(viewModel.folders) { folder in
                                NavigationLink(destination: SavedEmailsListView(folder: folder)) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(Color(hex: folder.color) ?? .blue)
                                            .font(.title2)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(folder.name)
                                                .font(.headline)
                                                .foregroundColor(.black)

                                            if let count = viewModel.folderEmailCounts[folder.id] {
                                                Text("\(count) email\(count != 1 ? "s" : "")")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .contextMenu {
                                    Button("Rename") {
                                        editingFolderName = folder.name
                                        showFolderActionSheet = folder
                                    }

                                    Button("Delete", role: .destructive) {
                                        viewModel.deleteFolder(folder)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .sheet(isPresented: $showCreateFolderSheet) {
                CreateFolderSheet(viewModel: viewModel, isPresented: $showCreateFolderSheet)
            }
            .alert("Rename Folder", isPresented: Binding(
                get: { showFolderActionSheet != nil },
                set: { if !$0 { showFolderActionSheet = nil } }
            )) {
                TextField("Folder name", text: $editingFolderName)
                Button("Cancel", role: .cancel) {
                    showFolderActionSheet = nil
                }
                Button("Rename") {
                    if let folder = showFolderActionSheet {
                        viewModel.renameFolder(folder, newName: editingFolderName)
                        showFolderActionSheet = nil
                    }
                }
            }
            .onAppear {
                viewModel.loadFolders()
            }
        }
    }
}

// MARK: - View Model

@MainActor
class EmailFolderListViewModel: ObservableObject {
    @Published var folders: [CustomEmailFolder] = []
    @Published var folderEmailCounts: [UUID: Int] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

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
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func createFolder(name: String, color: String) {
        Task {
            do {
                let newFolder = try await emailService.createEmailFolder(name: name, color: color)
                folders.append(newFolder)
                folderEmailCounts[newFolder.id] = 0
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func renameFolder(_ folder: CustomEmailFolder, newName: String) {
        Task {
            do {
                if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                    let updated = try await emailService.renameEmailFolder(id: folder.id, newName: newName)
                    folders[index] = updated
                }
            } catch {
                errorMessage = error.localizedDescription
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
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Create Folder Sheet

struct CreateFolderSheet: View {
    @ObservedObject var viewModel: EmailFolderListViewModel
    @Binding var isPresented: Bool
    @State private var folderName = ""
    @State private var selectedColor = "#84cae9"

    let colors = [
        "#84cae9", // Blue
        "#ff6b6b", // Red
        "#ffd93d", // Yellow
        "#6bcf7f", // Green
        "#c78bfa", // Purple
        "#f87171", // Orange
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder Name") {
                    TextField("Enter folder name", text: $folderName)
                }

                Section("Color") {
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color) ?? .blue)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    selectedColor == color ?
                                    Circle().stroke(Color.black, lineWidth: 2) :
                                    nil
                                )
                                .onTapGesture {
                                    selectedColor = color
                                }
                        }
                        Spacer()
                    }
                }
            }
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        if !folderName.trimmingCharacters(in: .whitespaces).isEmpty {
                            viewModel.createFolder(name: folderName, color: selectedColor)
                            isPresented = false
                        }
                    }
                    .disabled(folderName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

#Preview {
    EmailFolderListView()
}
