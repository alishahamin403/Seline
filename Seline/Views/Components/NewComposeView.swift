import SwiftUI

/// Standalone in-app compose view for new emails (not reply/forward).
/// Structure and styling mirror EmailComposeView exactly.
struct NewComposeView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var emailService = EmailService.shared

    @State private var toRecipients: String = ""
    @State private var ccRecipients: String = ""
    @State private var bccRecipients: String = ""
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var isSending: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showCcBcc: Bool = false
    @State private var contactSuggestions: [ContactSuggestion] = []
    @State private var showSuggestions: Bool = false
    @State private var showDiscardDialog: Bool = false
    @FocusState private var focusedField: Field?

    struct ContactSuggestion: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let email: String
    }

    enum Field: Hashable {
        case to
        case cc
        case bcc
        case subject
        case body
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    headerFieldsSection
                    bodyEditorSection
                    Spacer()
                }
                .navigationTitle("New Message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            handleCancel()
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        sendButton
                    }
                }
                .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)

                // Contact suggestions overlay — positioned below the To field
                if showSuggestions && !contactSuggestions.isEmpty && focusedField == .to {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 50)
                        contactSuggestionsOverlay
                    }
                    .zIndex(100)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog("Discard this message?", isPresented: $showDiscardDialog) {
            Button("Discard", role: .destructive) {
                dismiss()
            }
            Button("Keep Draft") {}
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = .to
            }
        }
    }

    // MARK: - Header Fields Section

    private var headerFieldsSection: some View {
        VStack(spacing: 0) {
            toFieldSection
            Divider().opacity(0.3)

            if showCcBcc {
                ccFieldSection
                Divider().opacity(0.3)
                bccFieldSection
                Divider().opacity(0.3)
            }

            subjectFieldSection
            Divider().opacity(0.3)
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
    }

    // MARK: - To Field

    private var toFieldSection: some View {
        HStack {
            Text("To:")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                .frame(width: 40, alignment: .leading)

            TextField("Recipients", text: $toRecipients)
                .font(FontManager.geist(size: 14, weight: .regular))
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                .focused($focusedField, equals: .to)
                .onChange(of: toRecipients) { newValue in
                    updateContactSuggestions(for: newValue)
                }

            if !showCcBcc {
                ccBccButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Cc/Bcc Toggle Button

    private var ccBccButton: some View {
        Button(action: { showCcBcc = true }) {
            Text("Cc/Bcc")
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                )
        }
    }

    // MARK: - Cc Field

    private var ccFieldSection: some View {
        HStack {
            Text("Cc:")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                .frame(width: 40, alignment: .leading)

            TextField("CC Recipients", text: $ccRecipients)
                .font(FontManager.geist(size: 14, weight: .regular))
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                .focused($focusedField, equals: .cc)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Bcc Field

    private var bccFieldSection: some View {
        HStack {
            Text("Bcc:")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                .frame(width: 40, alignment: .leading)

            TextField("BCC Recipients", text: $bccRecipients)
                .font(FontManager.geist(size: 14, weight: .regular))
                .autocapitalization(.none)
                .keyboardType(.emailAddress)
                .focused($focusedField, equals: .bcc)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Subject Field

    private var subjectFieldSection: some View {
        HStack {
            Text("Subject:")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                .frame(width: 60, alignment: .leading)

            TextField("Subject", text: $subject)
                .font(FontManager.geist(size: 14, weight: .regular))
                .focused($focusedField, equals: .subject)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Body Editor Section

    private var bodyEditorSection: some View {
        ZStack(alignment: .topLeading) {
            if bodyText.isEmpty && focusedField != .body {
                Text("Write your message…")
                    .font(FontManager.geist(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                    .padding(16)
            }

            TextEditor(text: $bodyText)
                .font(FontManager.geist(size: 15, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .tint(colorScheme == .dark ? .white : .black)
                .padding(16)
                .focused($focusedField, equals: .body)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button(action: {
            Task {
                await sendEmail()
            }
        }) {
            if isSending {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "paperplane.fill")
                    .font(FontManager.geist(size: 16, weight: .medium))
            }
        }
        .disabled(isSending || !canSend)
        .foregroundColor((isSending || !canSend) ? Color.gray : (colorScheme == .dark ? .white : .black))
    }

    // MARK: - Computed Properties

    private var canSend: Bool {
        !toRecipients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasContent: Bool {
        !toRecipients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !ccRecipients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !bccRecipients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Methods

    private func handleCancel() {
        if hasContent {
            showDiscardDialog = true
        } else {
            dismiss()
        }
    }

    private func sendEmail() async {
        isSending = true

        do {
            let toList = toRecipients
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let ccList = ccRecipients
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let bccList = bccRecipients
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            try await GmailAPIClient.shared.sendEmail(
                to: toList,
                cc: ccList,
                bcc: bccList,
                subject: subject,
                body: bodyText,
                htmlBody: nil
            )

            await MainActor.run {
                isSending = false
                HapticManager.shared.success()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isSending = false
                errorMessage = "Failed to send email: \(error.localizedDescription)"
                showError = true
                HapticManager.shared.error()
            }
        }
    }

    // MARK: - Contact Autocomplete

    private func updateContactSuggestions(for query: String) {
        let searchTerm = query.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? query

        if searchTerm.isEmpty {
            showSuggestions = false
            contactSuggestions = []
            return
        }

        Task {
            var uniqueContacts: [String: ContactSuggestion] = [:]

            // 1. Seed from local cache (instant — currently loaded inbox + sent)
            for email in emailService.inboxEmails {
                if uniqueContacts[email.sender.email.lowercased()] == nil {
                    uniqueContacts[email.sender.email.lowercased()] = ContactSuggestion(
                        name: email.sender.displayName,
                        email: email.sender.email
                    )
                }
            }
            for email in emailService.sentEmails {
                for recipient in email.recipients {
                    if uniqueContacts[recipient.email.lowercased()] == nil {
                        uniqueContacts[recipient.email.lowercased()] = ContactSuggestion(
                            name: recipient.displayName,
                            email: recipient.email
                        )
                    }
                }
            }

            // 2. Run Google Contacts API and Gmail message history search in parallel.
            //    Google Contacts only covers saved contacts.
            //    Gmail message search covers ALL senders/recipients across email history —
            //    this is the primary source, matching how Gmail's own compose autocomplete works.
            let contactsTask = Task {
                (try? await GmailAPIClient.shared.searchGmailContacts(query: searchTerm)) ?? []
            }
            let messagesTask = Task {
                let gmailQuery = "(from:\(searchTerm) OR to:\(searchTerm))"
                return (try? await GmailAPIClient.shared.searchEmails(query: gmailQuery, maxResults: 10)) ?? []
            }

            let gmailContacts = await contactsTask.value
            let gmailEmails = await messagesTask.value

            // Merge Google Contacts results
            for contact in gmailContacts {
                if uniqueContacts[contact.email.lowercased()] == nil {
                    uniqueContacts[contact.email.lowercased()] = ContactSuggestion(
                        name: contact.name,
                        email: contact.email
                    )
                }
            }

            // Merge Gmail message history results — extract every sender and recipient
            for email in gmailEmails {
                if uniqueContacts[email.sender.email.lowercased()] == nil {
                    uniqueContacts[email.sender.email.lowercased()] = ContactSuggestion(
                        name: email.sender.displayName,
                        email: email.sender.email
                    )
                }
                for recipient in email.recipients {
                    if uniqueContacts[recipient.email.lowercased()] == nil {
                        uniqueContacts[recipient.email.lowercased()] = ContactSuggestion(
                            name: recipient.displayName,
                            email: recipient.email
                        )
                    }
                }
            }

            // Guard against stale results: if the user kept typing while we fetched,
            // the current To field value will have moved on — discard this batch.
            let currentTerm = await MainActor.run {
                toRecipients.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? toRecipients
            }
            guard currentTerm == searchTerm else { return }

            // Filter the merged pool by the search term
            let searchLower = searchTerm.lowercased()
            let filtered = uniqueContacts.values.filter { contact in
                let nameLower = contact.name.lowercased()
                let emailLower = contact.email.lowercased()
                let emailPrefix = emailLower.components(separatedBy: "@").first ?? ""

                return nameLower.contains(searchLower) ||
                       emailLower.contains(searchLower) ||
                       emailPrefix.contains(searchLower)
            }
            .sorted { $0.name < $1.name }
            .prefix(15)

            await MainActor.run {
                contactSuggestions = Array(filtered)
                showSuggestions = !contactSuggestions.isEmpty
            }
        }
    }

    private func selectContact(_ contact: ContactSuggestion) {
        let existingRecipients = toRecipients
            .components(separatedBy: ",")
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if existingRecipients.isEmpty {
            toRecipients = contact.email
        } else {
            toRecipients = existingRecipients.joined(separator: ", ") + ", " + contact.email
        }

        showSuggestions = false
        contactSuggestions = []
    }

    // MARK: - Contact Suggestions Overlay

    private var contactSuggestionsOverlay: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(contactSuggestions) { contact in
                    contactSuggestionRow(contact: contact)
                    if contact.id != contactSuggestions.last?.id {
                        Divider().opacity(0.2).padding(.leading, 64)
                    }
                }
            }
        }
        .frame(height: min(CGFloat(contactSuggestions.count) * 56, 300))
        .background(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
    }

    private func contactSuggestionRow(contact: ContactSuggestion) -> some View {
        Button(action: {
            selectContact(contact)
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .frame(width: 36, height: 36)

                    Text(String(contact.name.prefix(1)).uppercased())
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.name)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text(contact.email)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    NewComposeView()
}
