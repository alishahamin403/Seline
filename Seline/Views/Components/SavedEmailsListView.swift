import SwiftUI

struct SavedEmailsListView: View {
    let folder: CustomEmailFolder
    @StateObject private var viewModel = SavedEmailsListViewModel()
    @State private var searchText = ""
    @State private var selectedEmail: SavedEmail?

    var filteredEmails: [SavedEmail] {
        if searchText.isEmpty {
            return viewModel.emails
        }
        return viewModel.emails.filter { email in
            email.subject.localizedCaseInsensitiveContains(searchText) ||
            email.senderEmail.localizedCaseInsensitiveContains(searchText) ||
            email.senderName?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)

                    TextField("Search emails", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color.white)

                // Emails List
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Spacer()
                    }
                } else if filteredEmails.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "envelope")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        Text(searchText.isEmpty ? "No Emails" : "No Results")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text(searchText.isEmpty ? "Save emails to this folder" : "Try a different search")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(filteredEmails) { email in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(email.senderName ?? email.senderEmail)
                                        .font(.headline)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(email.formattedTime)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                Text(email.subject)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                    .foregroundColor(.black)

                                if !email.previewText.isEmpty {
                                    Text(email.previewText)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                }

                                if !email.attachments.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "paperclip")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        Text("\(email.attachments.count) attachment\(email.attachments.count != 1 ? "s" : "")")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .onTapGesture {
                                selectedEmail = email
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.deleteEmail(email)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadEmails(in: folder.id)
        }
        .sheet(item: $selectedEmail) { email in
            SavedEmailDetailView(email: email, folder: folder, viewModel: viewModel)
        }
    }
}

// MARK: - View Model

@MainActor
class SavedEmailsListViewModel: ObservableObject {
    @Published var emails: [SavedEmail] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let emailService = EmailService.shared

    func loadEmails(in folderId: UUID) {
        isLoading = true
        Task {
            do {
                emails = try await emailService.fetchSavedEmails(in: folderId)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func deleteEmail(_ email: SavedEmail) {
        Task {
            do {
                try await emailService.deleteSavedEmail(id: email.id)
                emails.removeAll { $0.id == email.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func moveEmail(_ email: SavedEmail, to folderId: UUID) {
        Task {
            do {
                _ = try await emailService.moveSavedEmail(id: email.id, toFolder: folderId)
                emails.removeAll { $0.id == email.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Email Detail View

struct SavedEmailDetailView: View {
    let email: SavedEmail
    let folder: CustomEmailFolder
    @ObservedObject var viewModel: SavedEmailsListViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(email.subject)
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack {
                            Text(email.senderName ?? email.senderEmail)
                                .font(.subheadline)

                            Spacer()

                            Text(email.formattedTime)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                    // Recipient Info
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("From:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(email.senderEmail)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }

                        if !email.recipients.isEmpty {
                            HStack {
                                Text("To:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(email.recipients.joined(separator: ", "))
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }

                        if !email.ccRecipients.isEmpty {
                            HStack {
                                Text("CC:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(email.ccRecipients.joined(separator: ", "))
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                    // Body
                    if let body = email.body {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(body)
                                .font(.body)
                                .lineLimit(nil)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }

                    // Attachments
                    if !email.attachments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Attachments")
                                .font(.headline)

                            ForEach(email.attachments) { attachment in
                                HStack {
                                    Image(systemName: attachment.systemIcon)
                                        .foregroundColor(.blue)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(attachment.fileName)
                                            .font(.subheadline)
                                        Text(attachment.formattedSize)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            viewModel.deleteEmail(email)
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
}

#Preview {
    let folder = CustomEmailFolder(
        id: UUID(),
        userId: UUID(),
        name: "Work",
        color: "#84cae9",
        createdAt: Date(),
        updatedAt: Date()
    )
    SavedEmailsListView(folder: folder)
}
