import SwiftUI

struct EmailFolderSidebarView: View {
    @Binding var isPresented: Bool
    @StateObject private var viewModel = EmailFolderSidebarViewModel()
    @StateObject private var syncProgress = SyncProgress()
    @Environment(\.colorScheme) var colorScheme
    @State private var showCreateFolderSheet = false
    @State private var newFolderName = ""
    @State private var selectedColor = "#333333"
    @State private var showSyncResult = false
    @State private var syncResultMessage = ""
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                // Manual sync button
                if syncProgress.isSyncing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                        Text("Syncing...")
                            .font(.system(size: 12))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
                } else {
                    Button(action: { viewModel.syncLabelsManually(with: syncProgress) }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(action: { showCreateFolderSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
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
                                    // Folder icon with different colors for imported vs user-created
                                    Image(systemName: "folder")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(folder.isImported ? Color(hex: "#FF9500") ?? .orange : (colorScheme == .dark ? .white : .black))
                                        .frame(width: 20, height: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(folder.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                                .lineLimit(1)

                                            // Sync status indicator for imported labels
                                            if folder.isImported {
                                                if let lastSynced = folder.lastSyncedAt {
                                                    let timeAgo = formatTimeAgo(since: lastSynced)
                                                    Text(timeAgo)
                                                        .font(.system(size: 9))
                                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                                }
                                            }
                                        }

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
                                if folder.isImported {
                                    Button {
                                        viewModel.toggleSyncForFolder(folder)
                                    } label: {
                                        Label(folder.syncEnabled ?? true ? "Disable Sync" : "Enable Sync", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    Divider()
                                }
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
        .overlay {
            if syncProgress.isSyncing && syncProgress.total > 0 {
                SyncProgressOverlay(progress: syncProgress)
            }
        }
        .overlay(alignment: .top) {
            if syncProgress.isComplete {
                SyncResultBanner(
                    progress: syncProgress,
                    onDismiss: {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                            syncProgress.isComplete = false
                        }
                    }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
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
        .alert("Error Creating Folder", isPresented: $showCreationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(creationErrorMessage)
        }
    }

    // MARK: - Helper Functions

    private func formatTimeAgo(since date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 {
            return "just now"
        } else if minutes < 60 {
            return "\(minutes)m"
        } else if hours < 24 {
            return "\(hours)h"
        } else if days == 1 {
            return "1d"
        } else if days < 7 {
            return "\(days)d"
        } else {
            return "older"
        }
    }
}

// MARK: - View Model

@MainActor
class EmailFolderSidebarViewModel: ObservableObject {
    @Published var folders: [CustomEmailFolder] = []
    @Published var folderEmailCounts: [UUID: Int] = [:]
    @Published var isLoading = false
    @Published var showNewLabelsAlert = false
    @Published var newLabelsFound: [GmailLabel] = []
    @Published var newLabelsToImport: Set<String> = []

    private let emailService = EmailService.shared

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
                await emailService.clearFolderCache()
                print("🗑️ Folder cache cleared to reflect new folder")

                folders.append(newFolder)
                folderEmailCounts[newFolder.id] = 0

                await MainActor.run {
                    completion(nil) // Success - no error
                }
            } catch {
                print("❌ Error creating folder: \(error)")
                let errorMessage = error.localizedDescription
                await MainActor.run {
                    completion(errorMessage) // Pass error to completion handler
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

    func toggleSyncForFolder(_ folder: CustomEmailFolder) {
        Task {
            do {
                // Update the sync_enabled flag in the database
                let newSyncStatus = !(folder.syncEnabled ?? true)
                try await emailService.updateFolderSyncStatus(id: folder.id, syncEnabled: newSyncStatus)

                // Update local state
                if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                    var updatedFolder = folders[index]
                    updatedFolder.syncEnabled = newSyncStatus
                    folders[index] = updatedFolder
                }
            } catch {
                print("Error toggling sync: \(error)")
            }
        }
    }

    func syncLabelsManually(with progress: SyncProgress) {
        Task {
            do {
                print("🔄 Starting manual sync of existing labels...")
                try await emailService.manualSyncLabels()
                print("✅ Existing labels synced")

                // Check for new labels
                print("🔍 Checking for new labels...")
                let newLabels = try await emailService.checkForNewLabels()

                // Reload folders to show updated counts and sync timestamps
                await MainActor.run {
                    loadFolders()

                    // If new labels found, show prompt to import them
                    if !newLabels.isEmpty {
                        print("✨ Found \(newLabels.count) new labels")
                        showNewLabelsPrompt(newLabels: newLabels)
                    } else {
                        print("✅ No new labels found")
                    }
                }
            } catch {
                print("❌ Error during sync: \(error)")
            }
        }
    }

    private func showNewLabelsPrompt(newLabels: [GmailLabel]) {
        self.newLabelsFound = newLabels.sorted { $0.name < $1.name }
        self.newLabelsToImport.removeAll()
        self.showNewLabelsAlert = true
        print("💡 New labels available: \(newLabels.map { $0.name }.joined(separator: ", "))")
    }

    func importSelectedNewLabels() {
        Task {
            do {
                let labelSyncService = LabelSyncService.shared
                let selectedLabels = newLabelsFound.filter { newLabelsToImport.contains($0.id) }

                print("📥 Importing \(selectedLabels.count) new labels...")
                for (index, label) in selectedLabels.enumerated() {
                    try await labelSyncService.importLabel(label, progress: (index + 1, selectedLabels.count))
                }

                print("✅ New labels imported successfully")
                showNewLabelsAlert = false
                newLabelsFound = []
                newLabelsToImport = []

                // Reload folders to show the new labels
                await MainActor.run {
                    loadFolders()
                }
            } catch {
                print("❌ Error importing new labels: \(error)")
            }
        }
    }
}

// MARK: - Sync Progress Overlay

struct SyncProgressOverlay: View {
    @ObservedObject var progress: SyncProgress
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            // Content
            VStack(spacing: 20) {
                // Progress indicator
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(Color.blue.opacity(0.2), lineWidth: 3)
                            .frame(width: 70, height: 70)

                        Circle()
                            .trim(from: 0, to: progress.progressPercentage)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .cyan]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 70, height: 70)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.3), value: progress.progressPercentage)

                        VStack(spacing: 2) {
                            Text("\(Int(progress.progressPercentage * 100))%")
                                .font(.system(.title3, design: .rounded))
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }

                    Text(progress.status)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if progress.total > 0 {
                        Text("\(progress.current) of \(progress.total)")
                            .font(.caption)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }
                }

                // Progress bar
                ProgressView(value: progress.progressPercentage)
                    .tint(.blue)
                    .frame(height: 4)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
            )
            .padding(40)
        }
    }
}

// MARK: - Sync Result Banner

struct SyncResultBanner: View {
    @ObservedObject var progress: SyncProgress
    @Environment(\.colorScheme) var colorScheme
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(progress.isSuccess ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                        .frame(width: 36, height: 36)

                    Image(systemName: progress.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(progress.isSuccess ? .green : .red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.isSuccess ? "Sync Successful" : "Sync Failed")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    if !progress.message.isEmpty {
                        Text(progress.message)
                            .font(.caption)
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            .lineLimit(2)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        .padding(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.98, green: 0.98, blue: 0.98))
        )
        .padding(12)
    }
}

#Preview {
    EmailFolderSidebarView(isPresented: .constant(true))
}
