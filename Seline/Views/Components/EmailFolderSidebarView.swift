import SwiftUI

struct EmailFolderSidebarView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = EmailFolderSidebarViewModel()
    @Environment(\.colorScheme) var colorScheme
    @State private var showCreateFolderSheet = false
    @State private var newFolderName = ""
    @State private var selectedColor = "#333333"
    @State private var showCreationError = false
    @State private var creationErrorMessage = ""

    let colors = [
        "#333333", // Dark gray
        "#1a1a1a", // Darker gray
        "#4a4a4a", // Medium gray
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Text("Email Folders")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                Button(action: { showCreateFolderSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(FontManager.geist(size: 18, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.clear)

            // Folders list
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    if viewModel.isLoading {
                        ProgressView()
                            .padding()
                    } else if viewModel.folders.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(FontManager.geist(size: 28, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                            Text("No Folders")
                                .font(FontManager.geist(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                            Text("Create your first folder")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(viewModel.folders) { folder in
                            NavigationLink(destination: SavedEmailsListView(folder: folder)) {
                                HStack(spacing: 12) {
                                    // Folder icon
                                    Image(systemName: "folder")
                                        .font(FontManager.geist(size: 16, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(width: 20, height: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.name)
                                            .font(FontManager.geist(size: 14, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)

                                        if let count = viewModel.folderEmailCounts[folder.id] {
                                            Text("\(count) email\(count != 1 ? "s" : "")")
                                                .font(FontManager.geist(size: 11, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
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
                Color(red: 0.03, green: 0.03, blue: 0.03) :
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
                                viewModel.createFolder(name: newFolderName) { error in
                                    if let error = error {
                                        creationErrorMessage = error
                                        showCreationError = true
                                    } else {
                                        showCreateFolderSheet = false
                                        newFolderName = ""
                                    }
                                }
                            }
                        }
                        .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    .presentationBg()
        .alert("Error Creating Folder", isPresented: $showCreationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(creationErrorMessage)
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
    private var notificationObserver: NSObjectProtocol?

    init() {
        // Listen for folder creation notifications from SaveFolderSelectionSheet
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.emailFolderCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadFolders()
        }
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func loadFolders() {
        isLoading = true
        Task {
            do {
                print("📂 Loading folders...")
                folders = try await emailService.fetchSavedFolders()
                print("✅ Loaded \(folders.count) folders")

                // Load email counts for each folder
                for folder in folders {
                    do {
                        let count = try await emailService.getSavedEmailCount(in: folder.id)
                        folderEmailCounts[folder.id] = count
                        print("  📧 \(folder.name): \(count) emails")
                    } catch {
                        print("  ⚠️ Failed to count emails in \(folder.name): \(error)")
                        // Continue even if count fails
                    }
                }

                isLoading = false
            } catch {
                print("❌ Error loading folders: \(error)")
                print("🐛 Error details: \(String(describing: error))")
                isLoading = false
            }
        }
    }

    func createFolder(name: String, completion: @escaping (String?) -> Void) {
        Task {
            do {
                print("📁 Creating folder: \(name)")
                let newFolder = try await emailService.createEmailFolder(name: name, color: "#333333")
                print("✅ Folder created: \(newFolder.id)")

                // Clear the folder cache so the new folder is included next time
                emailService.clearFolderCache()
                print("🗑️ Folder cache cleared to reflect new folder")

                folders.append(newFolder)
                folderEmailCounts[newFolder.id] = 0

                await MainActor.run {
                    completion(nil) // Success - no error
                }
            } catch {
                print("❌ Error creating folder: \(error)")

                // Check if it's a duplicate key error (folder already exists)
                let errorString = String(describing: error)
                if errorString.contains("23505") || errorString.lowercased().contains("unique constraint") {
                    print("ℹ️ Folder already exists, reloading folders list...")

                    // Reload folders from Supabase to show the existing folder
                    emailService.clearFolderCache()
                    loadFolders()

                    await MainActor.run {
                        completion("Folder '\(name)' already exists") // User-friendly message
                    }
                } else {
                    let errorMessage = error.localizedDescription
                    await MainActor.run {
                        completion(errorMessage) // Pass error to completion handler
                    }
                }
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
