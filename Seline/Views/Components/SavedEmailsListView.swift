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
    @Environment(\.colorScheme) var colorScheme
    @State private var isEmailBodyExpanded: Bool = false

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Main content
                    ScrollView {
                        VStack(spacing: 20) {
                            // Email Header
                            headerSection
                                .padding(.horizontal, 20)

                            // Sender/Recipient Information
                            senderSection
                                .padding(.horizontal, 20)

                            // Email Body Section (with expand/collapse)
                            emailBodySection

                            // Attachments Section
                            if !email.attachments.isEmpty {
                                attachmentsSection
                                    .padding(.horizontal, 20)
                            }

                            // Bottom spacing to account for delete button
                            Spacer()
                                .frame(height: 40)
                        }
                        .padding(.top, 24)
                    }

                    // Fixed delete button at bottom
                    VStack(spacing: 0) {
                        Button(role: .destructive) {
                            viewModel.deleteEmail(email)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Delete Email")
                                    .font(FontManager.geist(size: .body, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.red.opacity(0.8))
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                        .padding(.top, 4)
                        .background(
                            colorScheme == .dark ?
                                Color.gmailDarkBackground :
                                Color.white
                        )
                    }
                }
                .background(
                    colorScheme == .dark ?
                        Color.gmailDarkBackground :
                        Color.white
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(email.subject)
                .font(FontManager.geist(size: .title1, weight: .bold))
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Sender Section
    private var senderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // From
            HStack(spacing: 8) {
                Text("From")
                    .font(FontManager.geist(size: .caption, weight: .semibold))
                    .foregroundColor(Color.shadcnMuted(colorScheme))

                VStack(alignment: .leading, spacing: 2) {
                    if let senderName = email.senderName {
                        Text(senderName)
                            .font(FontManager.geist(size: .body, weight: .medium))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                    }
                    Text(email.senderEmail)
                        .font(FontManager.geist(size: .caption, weight: .regular))
                        .foregroundColor(Color.shadcnMuted(colorScheme))
                }

                Spacer()

                Text(email.formattedTime)
                    .font(FontManager.geist(size: .caption, weight: .regular))
                    .foregroundColor(Color.shadcnMuted(colorScheme))
            }

            Divider()

            // To
            HStack(alignment: .top, spacing: 8) {
                Text("To")
                    .font(FontManager.geist(size: .caption, weight: .semibold))
                    .foregroundColor(Color.shadcnMuted(colorScheme))

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(email.recipients, id: \.self) { recipient in
                        Text(recipient)
                            .font(FontManager.geist(size: .caption, weight: .regular))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                    }
                }

                Spacer()
            }

            // CC (if present)
            if !email.ccRecipients.isEmpty {
                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Text("CC")
                        .font(FontManager.geist(size: .caption, weight: .semibold))
                        .foregroundColor(Color.shadcnMuted(colorScheme))

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(email.ccRecipients, id: \.self) { recipient in
                            Text(recipient)
                                .font(FontManager.geist(size: .caption, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            colorScheme == .dark ?
                Color.white.opacity(0.05) :
                Color.gray.opacity(0.05)
        )
        .cornerRadius(8)
    }

    // MARK: - Email Body Section
    private var emailBodySection: some View {
        VStack(spacing: 0) {
            // Expandable header button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEmailBodyExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Email Body")
                        .font(FontManager.geist(size: .body, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()

                    Image(systemName: isEmailBodyExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.shadcnMuted(colorScheme))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    colorScheme == .dark ?
                        Color.white.opacity(0.05) :
                        Color.gray.opacity(0.1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // Expandable content
            if isEmailBodyExpanded {
                if let body = email.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView {
                        Text(body)
                            .font(FontManager.geist(size: .body, weight: .regular))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .frame(height: 300)
                    .background(
                        colorScheme == .dark ?
                            Color.black :
                            Color.white
                    )
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(Color.shadcnMuted(colorScheme))

                        Text("No content available")
                            .font(FontManager.geist(size: .body, weight: .medium))
                            .foregroundColor(Color.shadcnMuted(colorScheme))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
                    .background(
                        colorScheme == .dark ?
                            Color.black :
                            Color.white
                    )
                }
            }
        }
    }

    // MARK: - Attachments Section
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attachments")
                .font(FontManager.geist(size: .title3, weight: .semibold))
                .foregroundColor(Color.shadcnForeground(colorScheme))

            LazyVStack(spacing: 8) {
                ForEach(email.attachments) { attachment in
                    HStack(spacing: 12) {
                        Image(systemName: attachment.systemIcon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(attachment.fileName)
                                .font(FontManager.geist(size: .body, weight: .medium))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .lineLimit(1)

                            Text(attachment.formattedSize)
                                .font(FontManager.geist(size: .caption, weight: .regular))
                                .foregroundColor(Color.shadcnMuted(colorScheme))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.shadcnMuted(colorScheme))
                    }
                    .padding(12)
                    .background(
                        colorScheme == .dark ?
                            Color.white.opacity(0.05) :
                            Color.gray.opacity(0.05)
                    )
                    .cornerRadius(8)
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
