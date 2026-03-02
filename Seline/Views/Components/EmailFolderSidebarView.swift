import SwiftUI

struct EmailFolderSidebarView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = EmailFolderSidebarViewModel()
    @Environment(\.colorScheme) var colorScheme
    @State private var showCreateFolderSheet = false
    @State private var newFolderName = ""
    @State private var showCreationError = false
    @State private var creationErrorMessage = ""
    @State private var searchText = ""

    private var filteredFolders: [CustomEmailFolder] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return viewModel.folders }
        return viewModel.folders.filter { $0.name.lowercased().contains(query) }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var importedFolders: [CustomEmailFolder] {
        filteredFolders.filter { $0.isImported }
    }

    private var customFolders: [CustomEmailFolder] {
        filteredFolders.filter { !$0.isImported }
    }

    private var sidebarBackgroundColor: Color {
        colorScheme == .dark ? Color.black : .white
    }

    private var topControlFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : .white
    }

    private var topControlBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    var body: some View {
        ZStack {
            sidebarBackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                sidebarHeader

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
                            LazyVStack(alignment: .leading, spacing: 20) {
                                if !customFolders.isEmpty {
                                    folderSection(title: "Custom", folders: customFolders)
                                }

                                if !importedFolders.isEmpty {
                                    folderSection(title: "Imported", folders: importedFolders)
                                }
                            }
                            .padding(.vertical, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(sidebarBackgroundColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.loadFoldersIfNeeded()
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

    private var sidebarHeader: some View {
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
                    .fill(topControlFillColor)
                    .overlay(
                        Capsule()
                            .stroke(topControlBorderColor, lineWidth: 0.8)
                    )
            )

            Button(action: {
                HapticManager.shared.buttonTap()
                showCreateFolderSheet = true
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Folder")
                        .font(FontManager.geist(size: 13, weight: .medium))
                }
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(
                    Capsule()
                        .fill(topControlFillColor)
                        .overlay(
                            Capsule()
                                .stroke(topControlBorderColor, lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(sidebarBackgroundColor)
        .frame(maxWidth: .infinity)
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
        .padding(.horizontal, 16)
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

    private func folderSection(title: String, folders: [CustomEmailFolder]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
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

                if index < folders.count - 1 {
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                        .frame(height: 1)
                        .padding(.leading, 32)
                        .padding(.trailing, 20)
                }
            }
        }
    }
}

// MARK: - Email Folder Row (ChatGPT-style minimal row)

struct EmailFolderRow: View {
    let folder: CustomEmailFolder
    let emailCount: Int?
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(folder.isImported ? Color.homeGlassAccent.opacity(0.8) : (colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.16)))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)

                Text(folder.isImported ? "Imported label" : "Custom folder")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
            }

            Spacer(minLength: 0)

            if let count = emailCount, count > 0 {
                Text("\(count)")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
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
    private var hasLoadedOnce = false

    init() {
        // Listen for folder creation notifications from SaveFolderSelectionSheet
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.emailFolderCreated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadFolders(force: true)
        }
    }

    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func loadFoldersIfNeeded() {
        loadFolders(force: false)
    }

    func loadFolders(force: Bool) {
        guard force || !hasLoadedOnce else { return }
        guard !isLoading else { return }

        isLoading = true
        Task {
            do {
                let loadedFolders = try await emailService.fetchSavedFolders()
                var counts: [UUID: Int] = [:]

                for folder in loadedFolders {
                    do {
                        let count = try await emailService.getSavedEmailCount(in: folder.id)
                        counts[folder.id] = count
                    } catch {
                        continue
                    }
                }

                folders = loadedFolders
                folderEmailCounts = counts
                hasLoadedOnce = true
                isLoading = false
            } catch {
                isLoading = false
            }
        }
    }

    func createFolder(name: String, completion: @escaping (String?) -> Void) {
        Task {
            do {
                let newFolder = try await emailService.createEmailFolder(name: name, color: "#333333")
                emailService.clearFolderCache()
                folders.append(newFolder)
                folderEmailCounts[newFolder.id] = 0
                hasLoadedOnce = true

                await MainActor.run {
                    completion(nil)
                }
            } catch {
                let errorString = String(describing: error)
                if errorString.contains("23505") || errorString.lowercased().contains("unique constraint") {
                    emailService.clearFolderCache()
                    loadFolders(force: true)

                    await MainActor.run {
                        completion("Folder '\(name)' already exists")
                    }
                } else {
                    let errorMessage = error.localizedDescription
                    await MainActor.run {
                        completion(errorMessage)
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
