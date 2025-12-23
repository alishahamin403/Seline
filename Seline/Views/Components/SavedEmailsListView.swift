import SwiftUI

struct SavedEmailsListView: View {
    let folder: CustomEmailFolder
    @StateObject private var viewModel = SavedEmailsListViewModel()
    @State private var selectedEmail: SavedEmail?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Emails List
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Spacer()
                    }
                } else if viewModel.emails.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "envelope")
                            .font(.system(size: 50))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.gray)
                        Text("No Emails")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        Text("Save emails to this folder")
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List {
                        ForEach(viewModel.emails) { email in
                            let isDeleting = viewModel.deletingEmailIds.contains(email.id)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(email.senderName ?? email.senderEmail)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(1)

                                    Spacer()

                                    if isDeleting {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Text(email.formattedTime)
                                            .font(.system(size: 12))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.gray)
                                    }
                                }

                                Text(email.subject)
                                    .font(.system(size: 14))
                                    .lineLimit(2)
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black)
                            }
                            .padding(.vertical, 4)
                            .opacity(isDeleting ? 0.5 : 1.0) // Show deletion in progress
                            .onTapGesture {
                                // Don't allow tapping while deleting
                                if !isDeleting {
                                    selectedEmail = email
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    viewModel.deleteEmail(email)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .disabled(isDeleting) // Disable interaction while deleting
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
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
    .presentationBg()
    }
}

// MARK: - View Model

@MainActor
class SavedEmailsListViewModel: ObservableObject {
    @Published var emails: [SavedEmail] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var deletingEmailIds: Set<UUID> = [] // Track emails being deleted

    private let emailService = EmailService.shared

    func loadEmails(in folderId: UUID) {
        isLoading = true
        Task {
            do {
                emails = try await emailService.fetchSavedEmails(in: folderId, forceRefresh: true)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func deleteEmail(_ email: SavedEmail) {
        // Add to deleting set to show loading state
        deletingEmailIds.insert(email.id)

        Task {
            do {
                // CRITICAL FIX: Wait for deletion to complete before removing from UI
                try await emailService.deleteSavedEmail(id: email.id)

                // Only remove from UI after successful deletion
                emails.removeAll { $0.id == email.id }
                deletingEmailIds.remove(email.id)

                print("✅ Email deleted successfully: \(email.subject)")
            } catch {
                // Show error and keep email in list if deletion fails
                deletingEmailIds.remove(email.id)
                errorMessage = "Failed to delete email: \(error.localizedDescription)"
                print("❌ Failed to delete email: \(error)")
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
    @State private var isDeleting: Bool = false
    @State private var showDeleteError: Bool = false

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
                            CompactSenderView(email: convertToEmail())
                                .padding(.horizontal, 20)

                            // AI Summary Section
                            if let summary = email.aiSummary, !summary.isEmpty {
                                AISummaryCard(
                                    email: convertToEmail(),
                                    onGenerateSummary: { _, _ in
                                        // Saved emails don't regenerate summaries
                                        return .success(summary)
                                    }
                                )
                                .padding(.horizontal, 20)
                            }

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
                            Task {
                                isDeleting = true
                                viewModel.deleteEmail(email)

                                // Wait a moment to ensure deletion completes
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                                if viewModel.errorMessage == nil {
                                    // Success - dismiss view
                                    dismiss()
                                } else {
                                    // Error occurred
                                    isDeleting = false
                                    showDeleteError = true
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if isDeleting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.9)
                                    Text("Deleting...")
                                        .font(FontManager.geist(size: .body, weight: .medium))
                                } else {
                                    Image(systemName: "trash")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Delete Email")
                                        .font(FontManager.geist(size: .body, weight: .medium))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isDeleting ? Color.gray.opacity(0.6) : Color.red.opacity(0.8))
                            )
                        }
                        .disabled(isDeleting)
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
        .alert("Delete Failed", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred while deleting the email.")
        }
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


    // MARK: - Original Email Section
    private var emailBodySection: some View {
        VStack(spacing: 0) {
            // Expandable header button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEmailBodyExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Original Email")
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
                if let htmlBody = email.body,
                   !htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   htmlBody.contains("<") {
                    // Display HTML content using WebView with zoom (like EmailDetailView)
                    ZoomableHTMLContentView(htmlContent: htmlBody)
                        .frame(height: 500)
                        .background(
                            colorScheme == .dark ?
                                Color.black :
                                Color.white
                        )
                } else {
                    // Display plain text or show "no content" message
                    let bodyText = email.body ?? email.snippet ?? ""

                    ScrollView {
                        if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundColor(Color.shadcnMuted(colorScheme))

                                Text("No content available")
                                    .font(FontManager.geist(size: .body, weight: .medium))
                                    .foregroundColor(Color.shadcnMuted(colorScheme))

                                Text("This email does not contain any readable content.")
                                    .font(FontManager.geist(size: .caption, weight: .regular))
                                    .foregroundColor(Color.shadcnMuted(colorScheme))
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(20)
                        } else {
                            Text(bodyText)
                                .font(FontManager.geist(size: .body, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        }
                    }
                    .frame(height: 300)
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

    // MARK: - Helper Methods
    private func convertToEmail() -> Email {
        // Convert SavedEmail to Email for AISummaryCard compatibility
        return Email(
            id: email.gmailMessageId,
            threadId: "",
            sender: EmailAddress(name: email.senderName, email: email.senderEmail, avatarUrl: nil),
            recipients: email.recipients.map { EmailAddress(name: nil, email: $0, avatarUrl: nil) },
            ccRecipients: email.ccRecipients.map { EmailAddress(name: nil, email: $0, avatarUrl: nil) },
            subject: email.subject,
            snippet: email.snippet ?? "",
            body: email.body,
            timestamp: email.timestamp,
            isRead: true,
            isImportant: false,
            hasAttachments: !email.attachments.isEmpty,
            attachments: email.attachments.map { attachment in
                EmailAttachment(
                    id: attachment.id.uuidString,
                    name: attachment.fileName,
                    size: attachment.fileSize,
                    mimeType: attachment.mimeType ?? "application/octet-stream",
                    url: nil
                )
            },
            labels: [],
            aiSummary: email.aiSummary,
            gmailMessageId: email.gmailMessageId,
            gmailThreadId: nil
        )
    }
}

#Preview {
    let folder = CustomEmailFolder(
        id: UUID(),
        userId: UUID(),
        name: "Work",
        color: "#84cae9",
        createdAt: Date(),
        updatedAt: Date(),
        isImportedLabel: false,
        gmailLabelId: nil,
        lastSyncedAt: nil,
        syncEnabled: false
    )
    SavedEmailsListView(folder: folder)
}
