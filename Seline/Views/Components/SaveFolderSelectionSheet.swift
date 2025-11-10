import SwiftUI

struct SaveFolderSelectionSheet: View {
    let email: Email
    @Binding var isPresented: Bool
    @StateObject private var viewModel = SaveFolderSelectionViewModel()
    @State private var showCreateFolder = false
    @State private var newFolderName = ""
    @State private var selectedFolderColor = "#84cae9"
    @State private var isSaving = false

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
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Save Email To Folder")
                        .font(.headline)
                        .fontWeight(.bold)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .background(Color.white)
                .border(Color(.systemGray5), width: 1)

                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.folders.isEmpty {
                    // Create Folder Prompt
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)

                        Text("No Folders Yet")
                            .font(.headline)
                            .foregroundColor(.gray)

                        Text("Create a folder to save this email")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Button(action: { showCreateFolder = true }) {
                            Text("Create Folder")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(12)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        .padding()

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            // Existing Folders
                            ForEach(viewModel.folders) { folder in
                                Button(action: {
                                    saveEmailToFolder(folder)
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(Color(hex: folder.color) ?? .blue)
                                            .font(.title3)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(folder.name)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.black)

                                            if let count = viewModel.folderEmailCounts[folder.id] {
                                                Text("\(count) email\(count != 1 ? "s" : "")")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }

                                        Spacer()

                                        if isSaving {
                                            ProgressView()
                                        }
                                    }
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                }
                                .disabled(isSaving)
                            }

                            // Create New Folder Button
                            Button(action: { showCreateFolder = true }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.blue)
                                        .font(.title3)

                                    Text("Create New Folder")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)

                                    Spacer()
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                }

                Spacer()
            }
            .background(Color(.systemGray6))
            .onAppear {
                viewModel.loadFolders()
            }
            .sheet(isPresented: $showCreateFolder) {
                NavigationStack {
                    Form {
                        Section("Folder Name") {
                            TextField("Enter folder name", text: $newFolderName)
                        }

                        Section("Color") {
                            HStack(spacing: 12) {
                                ForEach(colors, id: \.self) { color in
                                    Circle()
                                        .fill(Color(hex: color) ?? .blue)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            selectedFolderColor == color ?
                                            Circle().stroke(Color.black, lineWidth: 2) :
                                            nil
                                        )
                                        .onTapGesture {
                                            selectedFolderColor = color
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
                                showCreateFolder = false
                                newFolderName = ""
                                selectedFolderColor = "#84cae9"
                            }
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Create & Save") {
                                createFolderAndSave()
                            }
                            .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        }
                    }
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
                    color: selectedFolderColor
                )
                _ = try await EmailService.shared.saveEmailToFolder(email, folderId: newFolder.id)
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
    let email = Email.sampleEmails[0]
    @State var isPresented = true
    SaveFolderSelectionSheet(email: email, isPresented: $isPresented)
}
