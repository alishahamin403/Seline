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
    @State private var searchText = ""

    let colors = [
        "#333333", // Dark gray
        "#1a1a1a", // Darker gray
        "#4a4a4a", // Medium gray
    ]

    private var filteredFolders: [CustomEmailFolder] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.folders }
        return viewModel.folders.filter { $0.name.lowercased().contains(query) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.45))

                    TextField("Search folders", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )

                Button(action: {
                    HapticManager.shared.buttonTap()
                    showCreateFolderSheet = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                        Text("Folder")
                            .font(FontManager.geist(size: 13, weight: .medium))
                    }
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(colorScheme == .dark ? Color.black : Color(white: 0.99))

            // Folders list
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.folders.isEmpty {
                    emptyStateView
                } else if isSearching && filteredFolders.isEmpty {
                    noSearchResultsView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FOLDERS")
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                .textCase(.uppercase)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 6)

                            ForEach(filteredFolders) { folder in
                                NavigationLink(destination: SavedEmailsListView(folder: folder)) {
                                    EmailFolderRow(
                                        folder: folder,
                                        emailCount: viewModel.folderEmailCounts[folder.id],
                                        colorScheme: colorScheme
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    Button(role: .destructive) {
                                        viewModel.deleteFolder(folder)
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                        .padding(.vertical, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colorScheme == .dark ? Color.black : Color(white: 0.99))
        }
        .background(colorScheme == .dark ? Color.black : Color(white: 0.99))
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

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.25) : .black.opacity(0.2))
            Text("No folders yet")
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
            Text("Create your first folder to organize emails")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 8) {
            Text("No folders found")
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
            Text("Try another search term")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.45))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Email Folder Row (ChatGPT-style minimal row)

struct EmailFolderRow: View {
    let folder: CustomEmailFolder
    let emailCount: Int?
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(folder.name)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let count = emailCount, count > 0 {
                Text("\(count)")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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
