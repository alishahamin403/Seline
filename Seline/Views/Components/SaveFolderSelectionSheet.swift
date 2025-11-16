import SwiftUI

// Notification name for folder creation
extension NSNotification.Name {
    static let emailFolderCreated = NSNotification.Name("emailFolderCreated")
}

struct SaveFolderSelectionSheet: View {
    let email: Email
    @Binding var isPresented: Bool
    @StateObject private var viewModel = SaveFolderSelectionViewModel()
    @Environment(\.colorScheme) var colorScheme
    @State private var showCreateFolder = false
    @State private var newFolderName = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Save Email")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            Text("Choose where to save this email")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }

                        Spacer()

                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Divider()
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.folders.isEmpty {
                    // Create Folder Prompt
                    VStack(spacing: 20) {
                        Spacer()

                        Image(systemName: "folder")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))

                        VStack(spacing: 8) {
                            Text("No Folders Yet")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            Text("Create a folder to save this email")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }

                        Button(action: { showCreateFolder = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Create Folder")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                            )
                        }
                        .padding(.horizontal, 20)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Existing Folders
                            ForEach(viewModel.folders) { folder in
                                Button(action: {
                                    saveEmailToFolder(folder)
                                }) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(folder.name)
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                                .lineLimit(1)

                                            if let count = viewModel.folderEmailCounts[folder.id] {
                                                Text("\(count) email\(count != 1 ? "s" : "")")
                                                    .font(.system(size: 12, weight: .regular))
                                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                                            }
                                        }

                                        Spacer()

                                        if isSaving {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ?
                                                Color.white.opacity(0.05) :
                                                Color.black.opacity(0.02)
                                            )
                                    )
                                }
                                .disabled(isSaving)
                            }

                            // Create New Folder Button
                            Button(action: { showCreateFolder = true }) {
                                HStack(spacing: 14) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(width: 24)

                                    Text("Create New Folder")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ?
                                            Color.white.opacity(0.05) :
                                            Color.black.opacity(0.02)
                                        )
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }

                Spacer()
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .onAppear {
                viewModel.loadFolders()
            }
            .sheet(isPresented: $showCreateFolder) {
                NavigationStack {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Folder Name")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                .padding(.horizontal, 20)
                                .padding(.top, 20)

                            TextField("Enter folder name", text: $newFolderName)
                                .font(.system(size: 16, weight: .regular))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ?
                                            Color.white.opacity(0.05) :
                                            Color.black.opacity(0.05)
                                        )
                                )
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                        }

                        Spacer()

                        VStack(spacing: 10) {
                            Button(action: { createFolderAndSave() }) {
                                Text("Create & Save")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundColor(.white)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ?
                                                Color.white.opacity(0.15) :
                                                Color.black.opacity(0.08)
                                            )
                                    )
                            }
                            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)

                            Button("Cancel") {
                                showCreateFolder = false
                                newFolderName = ""
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .background(colorScheme == .dark ? Color.black : Color.white)
                    .navigationBarHidden(true)
                }
            }
        }
    }

    private func saveEmailToFolder(_ folder: CustomEmailFolder) {
        isSaving = true
        Task {
            do {
                _ = try await EmailService.shared.saveEmailToFolder(email, folderId: folder.id)
                isPresented = false
                isSaving = false
            } catch {
                print("Error saving email: \(error)")
                isSaving = false
            }
        }
    }

    private func createFolderAndSave() {
        isSaving = true
        Task {
            do {
                let newFolder = try await EmailService.shared.createEmailFolder(
                    name: newFolderName,
                    color: "#84cae9" // Default color (not shown in UI)
                )
                _ = try await EmailService.shared.saveEmailToFolder(email, folderId: newFolder.id)

                // Clear the folder cache so sidebar reflects the new folder
                EmailService.shared.clearFolderCache()

                // Post notification so sidebar can reload
                NotificationCenter.default.post(name: NSNotification.Name.emailFolderCreated, object: newFolder)

                isPresented = false
                isSaving = false
            } catch {
                print("Error creating folder and saving email: \(error)")
                isSaving = false
            }
        }
    }
}

// MARK: - View Model

@MainActor
class SaveFolderSelectionViewModel: ObservableObject {
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
}

#Preview {
    @State var isPresented = true
    SaveFolderSelectionSheet(email: Email.sampleEmails[0], isPresented: $isPresented)
}
