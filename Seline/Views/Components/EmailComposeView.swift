import SwiftUI

/// In-app email compose view for reply and forward
struct EmailComposeView: View {
    let email: Email
    let mode: ComposeMode
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var emailService = EmailService.shared
    @State private var toRecipients: String = ""
    @State private var ccRecipients: String = ""
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var isSending: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showCc: Bool = false
    @State private var contactSuggestions: [ContactSuggestion] = []
    @State private var showSuggestions: Bool = false
    @State private var contactSearchTask: Task<Void, Never>? = nil
    @FocusState private var focusedField: Field?
    
    struct ContactSuggestion: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let email: String
    }
    
    enum ComposeMode {
        case reply
        case replyAll
        case forward
    }
    
    enum Field: Hashable {
        case to
        case cc
        case subject
        case body
    }
    
    init(email: Email, mode: ComposeMode, onDismiss: @escaping () -> Void) {
        self.email = email
        self.mode = mode
        self.onDismiss = onDismiss
        
        // Initialize fields based on mode
        switch mode {
        case .reply:
            _toRecipients = State(initialValue: email.sender.email)
            _subject = State(initialValue: email.subject.hasPrefix("Re: ") ? email.subject : "Re: \(email.subject)")
            _bodyText = State(initialValue: "")
            
        case .replyAll:
            // Include sender and all recipients
            var recipients = [email.sender.email]
            recipients.append(contentsOf: email.recipients.map { $0.email })
            // Remove duplicates and current user (would need to get from auth)
            _toRecipients = State(initialValue: recipients.joined(separator: ", "))
            _ccRecipients = State(initialValue: email.ccRecipients.map { $0.email }.joined(separator: ", "))
            _subject = State(initialValue: email.subject.hasPrefix("Re: ") ? email.subject : "Re: \(email.subject)")
            _bodyText = State(initialValue: "")
            _showCc = State(initialValue: !email.ccRecipients.isEmpty)
            
        case .forward:
            _toRecipients = State(initialValue: "")
            _subject = State(initialValue: email.subject.hasPrefix("Fwd: ") ? email.subject : "Fwd: \(email.subject)")
            // Initialize with empty body text for user input
            _bodyText = State(initialValue: "")
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    headerFieldsSection
                    
                    // For forwarding, use a scrollable layout with compact message area
                    if mode == .forward {
                        ScrollView {
                            VStack(spacing: 0) {
                                // Compact message input area
                                compactBodyEditor
                                
                                // Forwarded content (scrolls with the page)
                                forwardedContentPreview
                            }
                        }
                    } else {
                        bodyEditorSection
                        Spacer()
                    }
                }
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            onDismiss()
                        }
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        sendButton
                    }
                }
                .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                
                // Contact suggestions overlay - positioned below active recipient field
                if showSuggestions && !contactSuggestions.isEmpty && (focusedField == .to || focusedField == .cc) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: suggestionsTopOffset)
                        
                        contactSuggestionsOverlay
                            .zIndex(100)
                        
                        Spacer()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                focusedField = mode == .forward ? .to : .body
            }
        }
        .onDisappear {
            contactSearchTask?.cancel()
            contactSearchTask = nil
        }
        .onChange(of: focusedField) { newValue in
            guard let field = newValue, field == .to || field == .cc else {
                showSuggestions = false
                contactSuggestions = []
                return
            }
            
            let currentInput = field == .to ? toRecipients : ccRecipients
            updateContactSuggestions(for: currentInput, field: field)
        }
    }
    
    // MARK: - Compact Body Editor (for forward mode)
    
    private var compactBodyEditor: some View {
        ZStack(alignment: .topLeading) {
            if bodyText.isEmpty {
                Text("Add a message...")
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            
            TextEditor(text: $bodyText)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .focused($focusedField, equals: .body)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(minHeight: 60, maxHeight: 120)
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.02) : Color.white)
    }
    
    // MARK: - Header Fields Section
    
    private var headerFieldsSection: some View {
        VStack(spacing: 0) {
            toFieldSection
            Divider().opacity(0.3)
            
            if showCc {
                ccFieldSection
                Divider().opacity(0.3)
            }
            
            subjectFieldSection
            Divider().opacity(0.3)
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
    }
    
    // MARK: - To Field Section
    
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
                    updateContactSuggestions(for: newValue, field: .to)
                }
            
            if !showCc {
                ccBccButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Cc/Bcc Button
    
    private var ccBccButton: some View {
        Button(action: { showCc = true }) {
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
    
    // MARK: - Contact Suggestions Overlay
    
    private var contactSuggestionsOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(contactSuggestions) { contact in
                contactSuggestionRow(contact: contact)
                if contact.id != contactSuggestions.last?.id {
                    Divider().opacity(0.2).padding(.leading, 64)
                }
            }
        }
        .frame(maxHeight: 250)
        .background(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
    }
    
    // Keeping old one for backward compatibility
    private var contactSuggestionsDropdown: some View {
        contactSuggestionsOverlay
    }
    
    // MARK: - Contact Suggestion Row
    
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
    
    // MARK: - CC Field Section
    
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
                .onChange(of: ccRecipients) { newValue in
                    updateContactSuggestions(for: newValue, field: .cc)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Subject Field Section
    
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
            if bodyText.isEmpty && mode == .forward {
                Text("Add a message...")
                    .font(FontManager.geist(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                    .padding(20)
            }
            
            TextEditor(text: $bodyText)
                .font(FontManager.geist(size: 15, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(16)
                .focused($focusedField, equals: .body)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
        }
    }
    
    // MARK: - Forwarded Content Preview
    
    private var forwardedContentPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Gmail-style forwarded message header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text("---------- Forwarded message ---------")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                }
                
                Group {
                    HStack(spacing: 4) {
                        Text("From:")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.35))
                        Text("\(email.sender.displayName) <\(email.sender.email)>")
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                    }
                    
                    HStack(spacing: 4) {
                        Text("Date:")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.35))
                        Text(formatForwardDate(email.timestamp))
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                    }
                    
                    HStack(spacing: 4) {
                        Text("Subject:")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.35))
                        Text(email.subject)
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 4) {
                        Text("To:")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.35))
                        Text(email.recipients.map { $0.email }.joined(separator: ", "))
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
            
            Divider().opacity(0.3)
            
            // Original email body - displayed exactly like in EmailDetailView
            let bodyContent = email.body ?? email.snippet
            AutoHeightHTMLView(htmlContent: wrapOriginalEmailForDisplay())
                .frame(minHeight: max(400, CGFloat(bodyContent.count / 5)))
                .frame(maxWidth: .infinity)
        }
    }
    
    private func formatForwardDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    private func wrapOriginalEmailForDisplay() -> String {
        let bodyContent = email.body ?? email.snippet
        let hasHTML = bodyContent.contains("<") && bodyContent.contains(">")
        
        if hasHTML {
            // Match EmailDetailView's wrapHTMLForGmailStyle exactly
            return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, shrink-to-fit=yes">
                <style>
                    * { 
                        box-sizing: border-box;
                        max-width: 100% !important;
                    }
                    html, body {
                        margin: 0;
                        padding: 0;
                        width: 100%;
                        overflow-x: hidden;
                    }
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                        font-size: 14px;
                        line-height: 1.5;
                        color: \(colorScheme == .dark ? "#ffffff" : "#202124");
                        background-color: \(colorScheme == .dark ? "#000000" : "#ffffff");
                        padding: 8px;
                        -webkit-text-size-adjust: 100%;
                        word-wrap: break-word;
                        overflow-wrap: break-word;
                    }
                    img { 
                        max-width: 100% !important; 
                        height: auto !important;
                        display: block;
                    }
                    table {
                        max-width: 100% !important;
                        width: auto !important;
                        table-layout: fixed !important;
                        word-wrap: break-word;
                    }
                    td, th {
                        max-width: 100% !important;
                        word-wrap: break-word !important;
                        overflow-wrap: break-word !important;
                    }
                    div, p, span {
                        max-width: 100% !important;
                    }
                    pre, code {
                        white-space: pre-wrap;
                        word-wrap: break-word;
                        max-width: 100%;
                    }
                    a { color: #1a73e8; text-decoration: none; }
                    blockquote {
                        margin: 8px 0;
                        padding-left: 10px;
                        border-left: 2px solid \(colorScheme == .dark ? "#444" : "#ccc");
                        color: \(colorScheme == .dark ? "#999" : "#666");
                    }
                    /* Force wide elements to shrink */
                    [width], [style*="width"] {
                        max-width: 100% !important;
                        width: auto !important;
                    }
                </style>
            </head>
            <body>
                \(bodyContent)
            </body>
            </html>
            """
        } else {
            // Plain text, convert to HTML
            let escapedContent = bodyContent
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            
            return """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    body {
                        font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                        font-size: 14px;
                        line-height: 1.5;
                        color: \(colorScheme == .dark ? "#ffffff" : "#202124");
                        background-color: \(colorScheme == .dark ? "#000000" : "#ffffff");
                        padding: 12px;
                        margin: 0;
                    }
                </style>
            </head>
            <body>
                \(escapedContent)
            </body>
            </html>
            """
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
    
    private var navigationTitle: String {
        switch mode {
        case .reply:
            return "Reply"
        case .replyAll:
            return "Reply All"
        case .forward:
            return "Forward"
        }
    }
    
    private var canSend: Bool {
        !toRecipients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Methods
    
    private func buildForwardBody() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d, yyyy 'at' h:mm a"
        
        // Get the body content and strip HTML if present
        let rawBody = email.body ?? email.snippet
        let cleanBody = stripHTMLTags(from: rawBody)
        
        return """
        
        
        ---------- Forwarded message ----------
        From: \(email.sender.displayName) (\(email.sender.email))
        Date: \(dateFormatter.string(from: email.timestamp))
        Subject: \(email.subject)
        To: \(email.recipients.map { "\($0.displayName) (\($0.email))" }.joined(separator: ", "))
        
        \(cleanBody)
        """
    }
    
    private func buildForwardHTMLBody() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, MMM d, yyyy 'at' h:mm a"
        
        let originalBody = email.body ?? (email.snippet.replacingOccurrences(of: "\n", with: "<br>"))
        // Check if original body is already full HTML document
        // If it is, we might need to be careful about nesting, but for now we'll append
        
        return """
        <br><br>
        <div class="gmail_quote">
            <div dir="ltr" class="gmail_attr">
                ---------- Forwarded message ---------<br>
                From: <strong class="gmail_sendername" dir="auto">\(email.sender.displayName)</strong> <span dir="ltr">&lt;<a href="mailto:\(email.sender.email)">\(email.sender.email)</a>&gt;</span><br>
                Date: \(dateFormatter.string(from: email.timestamp))<br>
                Subject: \(email.subject)<br>
                To: \(email.recipients.map { "&lt;<a href=\"mailto:\($0.email)\">\($0.email)</a>&gt;" }.joined(separator: ", "))<br>
            </div>
            <br>
            \(originalBody)
        </div>
        """
    }
    
    private func stripHTMLTags(from html: String) -> String {
        var text = html
        
        // Remove script and style tags with their content
        text = text.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: .regularExpression
        )
        
        // Replace common block elements with newlines
        text = text.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<p[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<div[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<tr[^>]*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "\n• ", options: .regularExpression)
        
        // Remove all other HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        
        // Decode common HTML entities
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'", "&#39;": "'", "&#x27;": "'",
            "&ndash;": "–", "&mdash;": "—", "&copy;": "©", "&reg;": "®",
            "&trade;": "™", "&hellip;": "…", "&rsquo;": "'", "&lsquo;": "'",
            "&rdquo;": "\"", "&ldquo;": "\"", "&bull;": "•"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Decode numeric HTML entities
        text = text.replacingOccurrences(
            of: "&#(\\d+);",
            with: "",
            options: .regularExpression
        )
        
        // Clean up excessive whitespace
        text = text.replacingOccurrences(of: "\\s*\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return text
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
            
            switch mode {
            case .reply, .replyAll:
                // Use reply function to maintain thread
                _ = try await GmailAPIClient.shared.replyToEmail(
                    originalEmail: email,
                    body: bodyText,
                    htmlBody: nil,
                    replyAll: mode == .replyAll
                )
                
            case .forward:
                // Use forward function with HTML support
                let htmlBody = buildForwardHTMLBody()
                
                _ = try await GmailAPIClient.shared.forwardEmail(
                    originalEmail: email,
                    to: toList,
                    additionalMessage: bodyText.isEmpty ? nil : bodyText,
                    htmlBody: htmlBody
                )
            }
            
            await MainActor.run {
                isSending = false
                HapticManager.shared.success()
                onDismiss()
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
    
    private var suggestionsTopOffset: CGFloat {
        if showCc && focusedField == .cc {
            return 98
        }
        return 50
    }
    
    private func updateContactSuggestions(for query: String, field: Field) {
        guard field == .to || field == .cc else {
            showSuggestions = false
            contactSuggestions = []
            return
        }
        
        // Get the last part of the input (after comma)
        let searchTerm = query.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? query
        
        contactSearchTask?.cancel()
        
        if searchTerm.isEmpty || searchTerm.count < 1 {
            showSuggestions = false
            contactSuggestions = []
            return
        }
        
        let activeField = field
        
        // Use cancellable task to avoid stale results overriding fresh input
        contactSearchTask = Task {
            // Start with unique contacts from inbox and sent emails (local cache - fast)
            var uniqueContacts: [String: ContactSuggestion] = [:]
            
            // From inbox (senders)
            for email in emailService.inboxEmails {
                let suggestion = ContactSuggestion(
                    name: email.sender.displayName,
                    email: email.sender.email
                )
                if uniqueContacts[email.sender.email.lowercased()] == nil {
                    uniqueContacts[email.sender.email.lowercased()] = suggestion
                }
            }
            
            // From sent (recipients)
            for email in emailService.sentEmails {
                for recipient in email.recipients {
                    let suggestion = ContactSuggestion(
                        name: recipient.displayName,
                        email: recipient.email
                    )
                    if uniqueContacts[recipient.email.lowercased()] == nil {
                        uniqueContacts[recipient.email.lowercased()] = suggestion
                    }
                }
                // Also include CC recipients
                for ccRecipient in email.ccRecipients {
                    let suggestion = ContactSuggestion(
                        name: ccRecipient.displayName,
                        email: ccRecipient.email
                    )
                    if uniqueContacts[ccRecipient.email.lowercased()] == nil {
                        uniqueContacts[ccRecipient.email.lowercased()] = suggestion
                    }
                }
            }
            
            // Also fetch from Gmail Contacts API for better results
            if let gmailContacts = try? await GmailAPIClient.shared.searchGmailContacts(query: searchTerm) {
                if Task.isCancelled { return }
                for contact in gmailContacts {
                    if uniqueContacts[contact.email.lowercased()] == nil {
                        uniqueContacts[contact.email.lowercased()] = ContactSuggestion(
                            name: contact.name,
                            email: contact.email
                        )
                    }
                }
            }
            
            // Filter by search term - more flexible matching
            let searchLower = searchTerm.lowercased()
            let filtered = uniqueContacts.values.map { contact -> (ContactSuggestion, Int) in
                // Match against name, email, or email prefix (before @)
                let nameLower = contact.name.lowercased()
                let emailLower = contact.email.lowercased()
                let emailPrefix = emailLower.components(separatedBy: "@").first ?? ""
                
                let score: Int
                if nameLower == searchLower || emailLower == searchLower {
                    score = 1000
                } else if nameLower.hasPrefix(searchLower) || emailPrefix.hasPrefix(searchLower) {
                    score = 800
                } else if emailLower.hasPrefix(searchLower) {
                    score = 700
                } else if nameLower.contains(searchLower) || emailPrefix.contains(searchLower) {
                    score = 500
                } else if emailLower.contains(searchLower) {
                    score = 300
                } else {
                    score = 0
                }
                
                return (contact, score)
            }
            .filter { $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.name.localizedCaseInsensitiveCompare($1.0.name) == .orderedAscending
                }
                return $0.1 > $1.1
            }
            .prefix(20)
            
            if Task.isCancelled { return }
            await MainActor.run {
                let isActiveField = focusedField == activeField
                contactSuggestions = Array(filtered.map { $0.0 })
                showSuggestions = isActiveField && !contactSuggestions.isEmpty
            }
        }
    }
    
    private func selectContact(_ contact: ContactSuggestion) {
        let targetField: Field = (focusedField == .cc) ? .cc : .to

        switch targetField {
        case .cc:
            ccRecipients = appendRecipient(contact.email, to: ccRecipients)
        default:
            toRecipients = appendRecipient(contact.email, to: toRecipients)
        }
        
        showSuggestions = false
        contactSuggestions = []
    }
    
    private func appendRecipient(_ email: String, to currentValue: String) -> String {
        let segments = currentValue.components(separatedBy: ",")
        let completeRecipients = segments.dropLast().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        let emailLower = email.lowercased()
        let existingSet = Set(completeRecipients.map { $0.lowercased() })
        
        var updated = completeRecipients
        if !existingSet.contains(emailLower) {
            updated.append(email)
        }
        
        if updated.isEmpty {
            return "\(email), "
        }
        
        return updated.joined(separator: ", ") + ", "
    }
}

// MARK: - Preview

#Preview {
    EmailComposeView(
        email: Email.sampleEmails[0],
        mode: .reply,
        onDismiss: {}
    )
}
