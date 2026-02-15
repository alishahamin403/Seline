import SwiftUI
import WebKit
import QuickLook

struct EmailDetailView: View {
    let email: Email
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode // Backup dismissal for fullScreenCover
    @StateObject private var emailService = EmailService.shared
    @StateObject private var openAIService = GeminiService.shared
    @State private var isOriginalEmailExpanded: Bool = true // Expand by default like Gmail
    @State private var fullEmail: Email? = nil
    @State private var isLoadingFullBody: Bool = false
    @State private var showAddEventSheet: Bool = false
    @State private var showSaveFolderSheet: Bool = false
    @State private var showForwardSheet: Bool = false
    @State private var isSenderInfoExpanded: Bool = false
    
    // Inline reply states
    @State private var showReplySection: Bool = false
    @State private var isForwardMode: Bool = false
    @State private var showCcBcc: Bool = false
    @State private var toRecipients: String = ""
    @State private var ccRecipients: String = ""
    @State private var bccRecipients: String = ""
    @State private var replyBody: String = ""
    @State private var isSending: Bool = false
    @State private var sendError: String? = nil
    @State private var showSentSuccess: Bool = false
    @State private var isCleaningUpText: Bool = false
    @FocusState private var focusedField: Field?
    
    // Smart reply states
    @State private var showSmartReplyOptions: Bool = false
    @State private var isGeneratingSmartReply: Bool = false
    @State private var smartReplyPrompt: String = ""
    @State private var loadingChipLabel: String? = nil

    // HTML content height for proper scrolling
    @State private var htmlContentHeight: CGFloat = 300

    // Unsubscribe states
    @State private var showUnsubscribeConfirmation: Bool = false
    @State private var isUnsubscribing: Bool = false
    @State private var unsubscribeError: String? = nil
    @State private var showUnsubscribeSuccess: Bool = false

    enum Field: Hashable {
        case to, cc, bcc, body, smartPrompt
    }

    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: .bottom) {
            // Main scrollable content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    // Subject with Inbox label (Gmail style)
                    gmailSubjectSection
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Sender/Recipient Information (Gmail style)
                    // Remove padding here - padding is handled inside gmailSenderSection
                    gmailSenderSection
                        .padding(.top, 16)

                    // AI Summary Section - Collapse when replying
                    if !showReplySection {
                        AISummaryCard(
                            email: email,
                            onGenerateSummary: { email, forceRegenerate in
                                await generateAISummary(for: email, forceRegenerate: forceRegenerate)
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 20) // More space between sender box and AI summary
                    }

                    // Reply Section - ABOVE original email when shown
                    if showReplySection {
                        gmailReplySection
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                     // Original Email Content - Edge-to-edge, full width
                     gmailEmailBodySection
                         .padding(.top, 12)

                    // Bottom spacing for fixed bottom elements
                    Spacer()
                        .frame(height: hasAttachments ? 160 : 100)
                }
                .padding(.top, 8)
                .frame(width: geometry.size.width) // CRITICAL: Constrain content to screen width
            }

            // Fixed bottom section with attachments + action bar
            VStack(spacing: 0) {
                // Modern floating attachments section
                if hasAttachments {
                    modernAttachmentsSection
                }

                // Reply/Forward bar
                gmailBottomActionBar
            }
        }
        } // GeometryReader
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color(UIColor.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Left: Back button - larger tap area, immediate dismiss
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    // Dismiss keyboard first
                    focusedField = nil
                    // Use both dismissal methods for reliability (fullScreenCover + NavigationLink)
                    dismiss()
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            // Right: Action buttons (Gmail style) - Trash at the end, colored red
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                // Save to Event
                Button(action: { showAddEventSheet = true }) {
                    Image(systemName: "calendar.badge.plus")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                // Save to Folder
                Button(action: { showSaveFolderSheet = true }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                // Mark as Unread
                Button(action: {
                    emailService.markAsUnread(email)
                    dismiss()
                }) {
                    Image(systemName: "envelope")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                // Delete - RED and at rightmost position
                Button(action: {
                    Task {
                        do {
                            try await emailService.deleteEmail(email)
                            dismiss()
                        } catch {
                            print("Failed to delete: \(error)")
                        }
                    }
                }) {
                    Image(systemName: "trash")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(.red)
                }
            }
        }
        .sheet(isPresented: $showAddEventSheet) {
            AddEventFromEmailView(email: fullEmail ?? email)
        }
        .presentationBg()
        .sheet(isPresented: $showSaveFolderSheet) {
            SaveFolderSelectionSheet(email: email, isPresented: $showSaveFolderSheet)
        }
        .presentationBg()
        .fullScreenCover(isPresented: $showForwardSheet) {
            EmailComposeView(
                email: fullEmail ?? email,
                mode: .forward,
                onDismiss: { showForwardSheet = false }
            )
        }
        .onAppear {
            // Reset content height for new email
            htmlContentHeight = 300

            if !email.isRead {
                emailService.markAsRead(email)
            }
            toRecipients = email.sender.email
            Task {
                await fetchFullEmailBodyIfNeeded()
            }
        }
    }
    
    // MARK: - Gmail Style Subject Section
    
    private var gmailSubjectSection: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(email.subject)
                .font(FontManager.geist(size: 20, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
    }
    
    // MARK: - Gmail Style Sender Section
    
    private var gmailSenderSection: some View {
        VStack(spacing: 0) {
            // Main row - always visible (no box)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSenderInfoExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    // Avatar
                    gmailAvatarView
                    
                    // Sender info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(email.sender.shortDisplayName)
                                .font(FontManager.geist(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            Text(email.formattedTime)
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        }
                        
                        HStack(spacing: 4) {
                            Text("to me")
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                            
                            Image(systemName: isSenderInfoExpanded ? "chevron.up" : "chevron.down")
                                .font(FontManager.geist(size: 10, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded details - matches AI Summary style exactly
            if isSenderInfoExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    gmailDetailRow(label: "From", name: email.sender.displayName, email: email.sender.email)
                    gmailDetailRow(label: "To", name: email.recipients.first?.displayName ?? "Me", email: email.recipients.first?.email ?? "")
                    gmailDetailRow(label: "Date", name: formatFullDate(email.timestamp), email: "")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .shadcnTileStyle(colorScheme: colorScheme)
                .padding(.horizontal, 16) // Same margins as AI Summary
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    private func gmailDetailRow(label: String, name: String, email: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(FontManager.geist(size: 11, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                .frame(width: 50, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 1) {
                if !name.isEmpty {
                    Text(name)
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                if !email.isEmpty {
                    Text(email)
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                }
            }
        }
    }
    
    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
    
    @ViewBuilder
    private var gmailAvatarView: some View {
        // Sender avatar - colored circle with initials
        fallbackAvatar
    }
    
    private var fallbackAvatar: some View {
        // Use same Google brand colors as EmailRow for consistency
        let colors: [Color] = [
            Color(red: 0.2588, green: 0.5216, blue: 0.9569),  // Google Blue #4285F4
            Color(red: 0.9176, green: 0.2627, blue: 0.2078),  // Google Red #EA4335
            Color(red: 0.9843, green: 0.7373, blue: 0.0157),  // Google Yellow #FBBC04
            Color(red: 0.2039, green: 0.6588, blue: 0.3255),  // Google Green #34A853
        ]
        // Use deterministic hash for consistent color across app restarts
        let hash = HashUtils.deterministicHash(email.sender.email)
        let color = colors[abs(hash) % colors.count]
        
        // Generate initials from sender name (e.g., "Wealthsimple" -> "WS", "John Doe" -> "JD")
        let initials = generateInitials(from: email.sender.shortDisplayName)
        
        return Circle()
            .fill(color)
            .frame(width: 40, height: 40)
            .overlay(
                Text(initials)
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
    
    /// Generate initials from a name (e.g., "Wealthsimple" -> "WS", "John Doe" -> "JD")
    private func generateInitials(from name: String) -> String {
        let words = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        if words.count >= 2 {
            // Multiple words: take first letter of first two words
            let first = String(words[0].prefix(1).uppercased())
            let second = String(words[1].prefix(1).uppercased())
            return first + second
        } else if words.count == 1 {
            // Single word: take first two letters if long enough, otherwise just first
            let word = words[0]
            if word.count >= 2 {
                return String(word.prefix(2).uppercased())
            } else {
                return String(word.prefix(1).uppercased())
            }
        } else {
            // Fallback: use first character of email
            return String(email.sender.email.prefix(1).uppercased())
        }
    }
    
    // MARK: - Gmail Style Email Body Section

    private var gmailEmailBodySection: some View {
        VStack(spacing: 0) {
            if isLoadingFullBody {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading email...")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
                .frame(height: 150)
                .frame(maxWidth: .infinity)
            } else {
                let bodyContent = (fullEmail ?? email).body ?? email.snippet
                let hasHTML = bodyContent.contains("<") && bodyContent.contains(">")

                if hasHTML {
                    // Use ZoomableHTMLView - expands to content height, no internal scroll
                    // Parent ScrollView handles all scrolling
                    ZoomableHTMLView(htmlContent: bodyContent, contentHeight: $htmlContentHeight)
                        .frame(height: max(300, htmlContentHeight))
                        .frame(maxWidth: .infinity)
                        .clipped() // Force content to stay within bounds
                } else {
                    // Plain text - show full content with proper text selection
                    Text(bodyContent)
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true) // Allow full height
                        .padding(.vertical, 12)
                }
            }
        }
    }
    
    // MARK: - Gmail Style Bottom Action Bar

    private var gmailBottomActionBar: some View {
        VStack(spacing: 8) {
            // Unsubscribe banner (if available)
            if let unsubInfo = (fullEmail ?? email).unsubscribeInfo, unsubInfo.hasUnsubscribeOption {
                unsubscribeBanner(unsubInfo: unsubInfo)
            }

            HStack(spacing: 16) {
                // Reply button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showReplySection = true
                        isForwardMode = false
                    }
                    // Focus the reply text field after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focusedField = .body
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrowshape.turn.up.left")
                            .font(FontManager.geist(size: 14, weight: .medium))
                        Text("Reply")
                            .font(FontManager.geist(size: 14, weight: .medium))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Forward button
                Button(action: {
                    // Use in-app forward - Gmail URL scheme doesn't support forwarding with content
                    showForwardSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrowshape.turn.up.right")
                            .font(FontManager.geist(size: 14, weight: .medium))
                        Text("Forward")
                            .font(FontManager.geist(size: 14, weight: .medium))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }

    // MARK: - Unsubscribe Banner

    private func unsubscribeBanner(unsubInfo: UnsubscribeInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))

            Text("Unsubscribe from this sender")
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))

            Spacer()

            Button(action: {
                showUnsubscribeConfirmation = true
            }) {
                if isUnsubscribing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 70, height: 28)
                } else {
                    Text("Unsubscribe")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.8))
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isUnsubscribing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .confirmationDialog(
            "Unsubscribe from \(email.sender.shortDisplayName)?",
            isPresented: $showUnsubscribeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unsubscribe", role: .destructive) {
                Task {
                    await handleUnsubscribe(unsubInfo: unsubInfo)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will stop receiving emails from this sender. This action cannot be undone from within the app.")
        }
        .alert("Unsubscribed", isPresented: $showUnsubscribeSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You have been unsubscribed from \(email.sender.shortDisplayName). It may take a few days for the change to take effect.")
        }
        .alert("Unsubscribe Failed", isPresented: Binding(
            get: { unsubscribeError != nil },
            set: { if !$0 { unsubscribeError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(unsubscribeError ?? "An error occurred while trying to unsubscribe.")
        }
    }

    // MARK: - Handle Unsubscribe

    private func handleUnsubscribe(unsubInfo: UnsubscribeInfo) async {
        isUnsubscribing = true
        unsubscribeError = nil

        // Prefer URL method over email
        if let urlString = unsubInfo.url, let url = URL(string: urlString) {
            await MainActor.run {
                // Open the unsubscribe URL in Safari
                UIApplication.shared.open(url) { success in
                    if success {
                        self.isUnsubscribing = false
                        self.showUnsubscribeSuccess = true
                        HapticManager.shared.success()
                    } else {
                        self.isUnsubscribing = false
                        self.unsubscribeError = "Could not open unsubscribe link."
                        HapticManager.shared.error()
                    }
                }
            }
        } else if let emailAddress = unsubInfo.email {
            // Create mailto URL for unsubscribe
            let subject = "Unsubscribe"
            let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
            let mailtoString = "mailto:\(emailAddress)?subject=\(encodedSubject)"

            await MainActor.run {
                if let mailtoURL = URL(string: mailtoString) {
                    UIApplication.shared.open(mailtoURL) { success in
                        if success {
                            self.isUnsubscribing = false
                            self.showUnsubscribeSuccess = true
                            HapticManager.shared.success()
                        } else {
                            self.isUnsubscribing = false
                            self.unsubscribeError = "Could not open mail app."
                            HapticManager.shared.error()
                        }
                    }
                } else {
                    self.isUnsubscribing = false
                    self.unsubscribeError = "Invalid unsubscribe email address."
                    HapticManager.shared.error()
                }
            }
        } else {
            await MainActor.run {
                self.isUnsubscribing = false
                self.unsubscribeError = "No unsubscribe option available."
                HapticManager.shared.error()
            }
        }
    }
    
    // MARK: - Gmail Style Reply Section
    
    private var gmailReplySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                
                Text("To: \(toRecipients)")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: { showCcBcc.toggle() }) {
                    Text("Cc/Bcc")
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    withAnimation { showReplySection = false }
                }) {
                    Image(systemName: "xmark")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Cc/Bcc fields
            if showCcBcc {
                VStack(spacing: 6) {
                    HStack {
                        Text("Cc:")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                            .frame(width: 30, alignment: .leading)
                        TextField("", text: $ccRecipients)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .focused($focusedField, equals: .cc)
                    }
                    HStack {
                        Text("Bcc:")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                            .frame(width: 30, alignment: .leading)
                        TextField("", text: $bccRecipients)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .focused($focusedField, equals: .bcc)
                    }
                }
            }
            
            // Text editor
            ZStack(alignment: .topLeading) {
                if replyBody.isEmpty {
                    Text("Write your reply...")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                        .padding(8)
                }
                
                TextEditor(text: $replyBody)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 80, maxHeight: 150)
                    .focused($focusedField, equals: .body)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            
            // Quick reply suggestions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(getContextAwareSuggestions(), id: \.label) { suggestion in
                        Button(action: {
                            loadingChipLabel = suggestion.label
                            smartReplyPrompt = suggestion.prompt
                            Task {
                                await generateSmartReply()
                                loadingChipLabel = nil
                            }
                        }) {
                            Text(suggestion.label)
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // Action row
            HStack {
                // AI button
                Button(action: { showSmartReplyOptions.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(FontManager.geist(size: 10, weight: .medium))
                        Text("AI")
                            .font(FontManager.geist(size: 11, weight: .semibold))
                    }
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                // Send button
                Button(action: { Task { await sendMessage() } }) {
                    HStack(spacing: 4) {
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(FontManager.geist(size: 10, weight: .medium))
                        }
                        Text("Send")
                            .font(FontManager.geist(size: 11, weight: .semibold))
                    }
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(canSend ? (colorScheme == .dark ? .white : .black) : Color.gray.opacity(0.5))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSend || isSending)
            }
            
            // Error/Success messages
            if let error = sendError {
                Text(error)
                    .font(FontManager.geist(size: 11, weight: .regular))
                    .foregroundColor(.red)
            }
            
            if showSentSuccess {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(.green)
                    Text("Sent!")
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showSentSuccess = false
                        replyBody = ""
                        showReplySection = false
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Wrap HTML for Gmail-style display
    
    private func wrapHTMLForGmailStyle(_ html: String) -> String {
        """
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
            \(html)
        </body>
        </html>
        """
    }
    
    // MARK: - Helper Properties
    
    private var canSend: Bool {
        !replyBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !toRecipients.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - Context-Aware Suggestions
    
    private func getContextAwareSuggestions() -> [(label: String, prompt: String)] {
        let summary = (email.aiSummary ?? email.snippet).lowercased()
        let subject = email.subject.lowercased()
        let combined = summary + " " + subject
        
        var suggestions: [(label: String, prompt: String)] = []
        
        if combined.contains("meeting") || combined.contains("schedule") || combined.contains("call") {
            suggestions.append(("Confirm", "Confirm the meeting"))
            suggestions.append(("Reschedule", "Suggest a different time"))
        }
        
        if combined.contains("payment") || combined.contains("transfer") || combined.contains("$") {
            suggestions.append(("Acknowledge received", "Acknowledge receipt with thanks"))
            suggestions.append(("Request details", "Ask for more details"))
        }
        
        if combined.contains("?") {
            suggestions.append(("Yes", "Respond positively"))
            suggestions.append(("No", "Politely decline"))
        }
        
        if suggestions.isEmpty {
            suggestions = [
                ("Sounds good", "Agree politely"),
                ("Need more info", "Ask for clarification"),
                ("Thanks", "Express gratitude")
            ]
        }
        
        return Array(suggestions.prefix(3))
    }
    
    // MARK: - Attachments Helper
    private var hasAttachments: Bool {
        !(fullEmail ?? email).attachments.isEmpty
    }

    // MARK: - Modern Floating Attachments Section
    private var modernAttachmentsSection: some View {
        VStack(spacing: 0) {
            // Subtle top border/shadow
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 8)

            // Attachments content
            VStack(alignment: .leading, spacing: 10) {
                // Header with count
                HStack {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))

                    Text("\((fullEmail ?? email).attachments.count) Attachment\((fullEmail ?? email).attachments.count > 1 ? "s" : "")")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))

                    Spacer()
                }

                // Horizontal scrolling attachment chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach((fullEmail ?? email).attachments) { attachment in
                            ModernAttachmentChip(
                                attachment: attachment,
                                emailMessageId: (fullEmail ?? email).gmailMessageId
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }
    
    // MARK: - Full Email Body Fetching
    private func fetchFullEmailBodyIfNeeded() async {
        guard fullEmail == nil else { return }
        guard let messageId = email.gmailMessageId else { return }

        isLoadingFullBody = true

        do {
            if let fetchedEmail = try await GmailAPIClient.shared.fetchFullEmailBody(messageId: messageId) {
                await MainActor.run {
                    self.fullEmail = fetchedEmail
                    self.isLoadingFullBody = false
                }
            } else {
                await MainActor.run {
                    self.isLoadingFullBody = false
                }
            }
        } catch {
            print("Failed to fetch full email body: \(error)")
            await MainActor.run {
                self.isLoadingFullBody = false
            }
        }
    }

    // MARK: - Send Message
    private func sendMessage() async {
        guard canSend else { return }

        isSending = true
        sendError = nil

        do {
            let toEmails = toRecipients.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let ccEmails = ccRecipients.isEmpty ? [] : ccRecipients.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let bccEmails = bccRecipients.isEmpty ? [] : bccRecipients.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            _ = try await GmailAPIClient.shared.replyToEmail(
                originalEmail: fullEmail ?? email,
                body: replyBody,
                htmlBody: nil,
                replyAll: false
            )

            await MainActor.run {
                isSending = false
                showSentSuccess = true
                HapticManager.shared.success()
            }
        } catch {
            await MainActor.run {
                isSending = false
                sendError = "Failed to send: \(error.localizedDescription)"
                HapticManager.shared.error()
            }
        }
    }

    // MARK: - Smart Reply Generation
    private func generateSmartReply() async {
        guard !smartReplyPrompt.isEmpty else { return }

        isGeneratingSmartReply = true

        do {
            let prompt = """
            Generate a professional email reply based on the user's intent.
            
            ORIGINAL EMAIL:
            From: \(email.sender.displayName) <\(email.sender.email)>
            Subject: \(email.subject)
            Content: \(email.body ?? email.snippet)
            
            USER'S INTENT FOR REPLY: \(smartReplyPrompt)
            
            INSTRUCTIONS:
            - Write a natural, professional email reply
            - Keep it concise but friendly
            - Don't include subject line or email headers
            - Don't include placeholder text like [Your Name]
            - Just write the email body text
            - Match the tone of the original email
            """

            let response = try await openAIService.answerQuestion(
                query: prompt,
                conversationHistory: [],
                operationType: "smart_reply"
            )

            await MainActor.run {
                replyBody = response.trimmingCharacters(in: .whitespacesAndNewlines)
                isGeneratingSmartReply = false
                smartReplyPrompt = ""
                showSmartReplyOptions = false
                HapticManager.shared.success()
            }
        } catch {
            await MainActor.run {
                isGeneratingSmartReply = false
                HapticManager.shared.error()
            }
        }
    }

    // MARK: - Generate AI Summary
    private func generateAISummary(for email: Email, forceRegenerate: Bool) async -> Result<String, Error> {
        if !forceRegenerate, let existingSummary = email.aiSummary {
            return .success(existingSummary)
        }

        do {
            guard let messageId = email.gmailMessageId else {
                throw NSError(domain: "EmailError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No message ID available"])
            }

            let bodyForAI = try await GmailAPIClient.shared.fetchBodyForAI(messageId: messageId)
            let body = bodyForAI ?? email.snippet

            let summary = try await openAIService.summarizeEmail(
                subject: email.subject,
                body: body
            )

            let finalSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No content available" : summary

            await emailService.updateEmailWithAISummary(email, summary: finalSummary)

            return .success(finalSummary)
        } catch {
            print("Failed to generate AI summary: \(error)")
            return .failure(error)
        }
    }
}

// MARK: - Modern Attachment Chip

struct ModernAttachmentChip: View {
    let attachment: EmailAttachment
    let emailMessageId: String?
    @Environment(\.colorScheme) var colorScheme
    @State private var isDownloading = false
    @State private var showPreview = false
    @State private var downloadedURL: URL?

    private var fileIcon: String {
        switch attachment.fileExtension {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.split.3x3.fill"
        case "jpg", "jpeg", "png", "gif", "webp", "heic": return "photo.fill"
        case "mp4", "mov", "avi": return "video.fill"
        case "mp3", "wav", "m4a": return "music.note"
        case "zip", "rar", "7z": return "archivebox.fill"
        default: return "doc.fill"
        }
    }

     private var fileColor: Color {
         // Use consistent black/white colors based on color scheme for all file types
         return colorScheme == .dark ? .white : .black
     }

    var body: some View {
        Button(action: downloadAttachment) {
            HStack(spacing: 10) {
                // File type icon with colored background
                fileIconView

                // File info
                fileInfoView
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showPreview) {
            if let url = downloadedURL {
                QuickLookPreview(url: url)
            }
        }
    }

    private var fileIconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(fileColor.opacity(0.15))
                .frame(width: 36, height: 36)

            if isDownloading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: fileIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(fileColor)
            }
        }
    }

    private var fileInfoView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attachment.name)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)

            Text(attachment.formattedSize)
                .font(FontManager.geist(size: 10, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
        }
    }

    private func downloadAttachment() {
        guard let messageId = emailMessageId else { return }
        isDownloading = true

        Task {
            do {
                if let data = try await GmailAPIClient.shared.downloadAttachment(
                    messageId: messageId,
                    attachmentId: attachment.id
                ) {
                    let tempDir = FileManager.default.temporaryDirectory
                    let fileURL = tempDir.appendingPathComponent(attachment.name)
                    try data.write(to: fileURL)

                    await MainActor.run {
                        downloadedURL = fileURL
                        isDownloading = false
                        showPreview = true
                        HapticManager.shared.success()
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    HapticManager.shared.error()
                }
            }
        }
    }
}

// MARK: - QuickLook Preview

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}

// MARK: - Zoomable HTML View (expands to content height, no internal scroll)

struct ZoomableHTMLView: UIViewRepresentable {
    let htmlContent: String
    @Binding var contentHeight: CGFloat
    @Environment(\.colorScheme) var colorScheme

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences

        // Enable inline media playback for images and videos
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Allow data detection (links, addresses, etc.)
        let webPrefs = WKPreferences()
        webPrefs.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences = webPrefs

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.parent = self

        // CRITICAL: Set autoresizing mask to ensure WebView fills container properly
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

         // CRITICAL: Disable WebView's internal scrolling - parent ScrollView handles all scrolling
         webView.scrollView.isScrollEnabled = false
         webView.scrollView.bounces = false
         webView.scrollView.showsVerticalScrollIndicator = false
         webView.scrollView.showsHorizontalScrollIndicator = false
         webView.scrollView.contentInset = .zero
         webView.scrollView.contentInsetAdjustmentBehavior = .never
         
         // Disable zoom on WebView - we handle scaling with viewport meta tag
         webView.scrollView.minimumZoomScale = 1.0
         webView.scrollView.maximumZoomScale = 1.0
         webView.scrollView.zoomScale = 1.0
         
         // Enable scrolling to top with status bar tap
         webView.scrollView.scrollsToTop = false

        // Disable back/forward navigation gestures that can interfere with toolbar
        webView.allowsBackForwardNavigationGestures = false

        // Disable link preview gestures that can delay tap recognition
        webView.allowsLinkPreview = false

        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // Allow loading remote content
        webView.configuration.websiteDataStore = .default()

        // Reduce gesture recognizer delays
        for gestureRecognizer in webView.scrollView.gestureRecognizers ?? [] {
            gestureRecognizer.cancelsTouchesInView = false
            gestureRecognizer.delaysTouchesBegan = false
            gestureRecognizer.delaysTouchesEnded = false
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !htmlContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            return
        }

         // Get screen width to properly scale content
         let screenWidth = UIScreen.main.bounds.width
         
         // Wrap HTML with proper viewport and scaling meta tags
         let wrappedHTML = """
         <!DOCTYPE html>
         <html>
         <head>
             <meta charset="UTF-8">
             <meta name="viewport" content="width=device-width, initial-scale=1.0, shrink-to-fit=yes, viewport-fit=cover">
             <meta http-equiv="Content-Security-Policy" content="default-src * 'unsafe-inline' 'unsafe-eval' data: blob:; img-src * data: blob: https: http:;">
             <style>
                 * {
                     box-sizing: border-box !important;
                 }
                 html {
                     margin: 0 !important;
                     padding: 0 !important;
                     width: 100% !important;
                     max-width: 100% !important;
                     overflow-x: hidden !important;
                 }
                 body {
                     margin: 0 !important;
                     padding: 16px !important;
                     width: 100% !important;
                     max-width: 100% !important;
                     min-width: 0 !important;
                     overflow-x: hidden !important;
                     overflow-y: visible !important;
                     font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                     font-size: 14px;
                     line-height: 1.5;
                     color: \(colorScheme == .dark ? "#ffffff" : "#202124");
                     background-color: transparent;
                     -webkit-text-size-adjust: none;
                     word-wrap: break-word !important;
                     overflow-wrap: break-word !important;
                     word-break: break-word !important;
                 }
                 
                 /* Wrapper to contain and scale content if needed */
                 #email-content-wrapper {
                     width: 100%;
                     max-width: 100%;
                     overflow: hidden;
                 }

                 /* CRITICAL: Force ALL images to fit within viewport and ensure loading */
                 img {
                     max-width: 100% !important;
                     width: auto !important;
                     height: auto !important;
                     display: inline-block !important;
                     object-fit: contain !important;
                 }

                /* Override inline width/height attributes on images */
                img[width], img[height], img[style] {
                    max-width: 100% !important;
                    width: auto !important;
                    height: auto !important;
                }

                 /* Handle tables - common in email templates */
                 table {
                     max-width: 100% !important;
                     table-layout: auto !important;
                     border-collapse: collapse !important;
                     margin: 12px 0 !important;
                 }
                 
                 /* Fix tables with explicit width attributes */
                 table[width] {
                     width: auto !important;
                     max-width: 100% !important;
                 }

                 /* Table cells need to shrink */
                 td, th {
                     max-width: 100% !important;
                     word-wrap: break-word !important;
                     overflow-wrap: break-word !important;
                     word-break: break-word !important;
                     padding: 8px !important;
                 }

                /* Images inside tables */
                td img, th img {
                    max-width: 100% !important;
                    height: auto !important;
                }

                 /* Base structural elements */
                 div, p, section, article {
                     max-width: 100% !important;
                     overflow-wrap: break-word !important;
                     word-wrap: break-word !important;
                     word-break: break-word !important;
                 }

                h1, h2, h3, h4, h5, h6 {
                    margin: 16px 0 12px 0 !important;
                    word-wrap: break-word !important;
                }

                a {
                    color: #1a73e8 !important;
                    word-break: break-word !important;
                }

                blockquote {
                    margin: 12px 0 !important;
                    padding-left: 12px !important;
                    border-left: 3px solid \(colorScheme == .dark ? "#555" : "#ddd") !important;
                    opacity: 0.8 !important;
                }

                pre, code {
                    white-space: pre-wrap !important;
                    word-wrap: break-word !important;
                    max-width: 100% !important;
                    overflow-x: auto !important;
                    background-color: \(colorScheme == .dark ? "#1a1a1a" : "#f5f5f5") !important;
                    padding: 8px !important;
                    border-radius: 4px !important;
                }

                /* Hide problematic tracking pixels but keep other images visible */
                img[width="1"][height="1"],
                img[width="0"][height="0"] {
                    display: none !important;
                }

                /* Horizontal rules */
                hr {
                    border: none !important;
                    border-top: 1px solid \(colorScheme == .dark ? "#444" : "#ddd") !important;
                    margin: 12px 0 !important;
                }

                /* Support for iframes in email */
                iframe {
                    max-width: 100% !important;
                    width: 100% !important;
                    height: auto !important;
                }

                /* List styles */
                ul, ol {
                    margin: 12px 0 !important;
                    padding-left: 24px !important;
                }

                li {
                    margin: 4px 0 !important;
                }
            </style>
            <script>
                 // Ensure all content fits properly and scale if needed
                 function formatEmailContent() {
                     var wrapper = document.getElementById('email-content-wrapper');
                     var screenWidth = \(screenWidth) - 32; // Account for body padding
                     
                     // Remove fixed dimensions from all images
                     var images = document.querySelectorAll('img');
                     images.forEach(function(img) {
                         img.removeAttribute('width');
                         img.removeAttribute('height');
                         img.style.maxWidth = '100%';
                         img.style.height = 'auto';
                         img.style.width = 'auto';

                         // Handle image load errors with retry logic
                         img.onerror = function() {
                             if (!this.dataset.retried && this.src) {
                                 this.dataset.retried = 'true';
                                 var originalSrc = this.src;
                                 this.referrerPolicy = 'no-referrer';
                                 this.crossOrigin = 'anonymous';
                                 this.src = originalSrc;
                             }
                         };

                         // Ensure images load by triggering a reload if needed
                         if (img.complete && img.naturalHeight === 0 && img.src) {
                             img.referrerPolicy = 'no-referrer';
                             var src = img.src;
                             img.src = '';
                             img.src = src;
                         }
                     });

                     // Fix tables to fit width
                     var tables = document.querySelectorAll('table');
                     tables.forEach(function(table) {
                         table.removeAttribute('width');
                         table.style.maxWidth = '100%';
                     });

                     // Remove fixed widths from containers
                     var containers = document.querySelectorAll('div, section, article, td, th');
                     containers.forEach(function(el) {
                         var width = el.getAttribute('width');
                         if (width && parseInt(width) > screenWidth) {
                             el.removeAttribute('width');
                             el.style.maxWidth = '100%';
                         }
                     });
                     
                     // Scale content if it's wider than viewport
                     setTimeout(function() {
                         var contentWidth = wrapper.scrollWidth;
                         if (contentWidth > screenWidth) {
                             var scale = screenWidth / contentWidth;
                             wrapper.style.transform = 'scale(' + scale + ')';
                             wrapper.style.transformOrigin = 'top left';
                             wrapper.style.width = (contentWidth) + 'px';
                             document.body.style.height = (wrapper.scrollHeight * scale) + 'px';
                         }
                     }, 100);
                 }

                // Initial formatting on DOMContentLoaded
                document.addEventListener('DOMContentLoaded', formatEmailContent);
                
                // Apply formatting on window load as well
                window.addEventListener('load', function() {
                    formatEmailContent();
                    // Return total height for SwiftUI
                    return document.body.scrollHeight;
                });
                
                // Monitor for dynamic content changes
                setTimeout(function() {
                    formatEmailContent();
                }, 500);
            </script>
         </head>
         <body>
             <div id="email-content-wrapper">
                 \(htmlContent)
             </div>
         </body>
         </html>
         """

        // Use a base URL to help resolve relative image paths
        let baseURL = URL(string: "https://mail.google.com/")
        webView.loadHTMLString(wrappedHTML, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ZoomableHTMLView?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
             // Format content and measure height after page load
             let jsFixAndMeasure = """
             (function() {
                 // Remove fixed dimensions from all images
                 var images = document.querySelectorAll('img');
                 images.forEach(function(img) {
                     img.removeAttribute('width');
                     img.removeAttribute('height');
                     img.style.maxWidth = '100%';
                     img.style.height = 'auto';
                     img.style.width = 'auto';
                 });

                 // Fix tables to fit width
                 var tables = document.querySelectorAll('table');
                 tables.forEach(function(table) {
                     table.removeAttribute('width');
                     table.style.maxWidth = '100%';
                     table.style.width = '100%';
                 });

                 // Fix containers
                 var containers = document.querySelectorAll('div, section, article, td, th');
                 containers.forEach(function(el) {
                     if (el.style.width && el.style.width !== '100%') {
                         el.style.maxWidth = '100%';
                     }
                 });

                 // Return the document height (add padding for safety)
                 var height = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
                 return height;
             })();
             """

             webView.evaluateJavaScript(jsFixAndMeasure) { [weak self] height, _ in
                 if let contentHeight = height as? CGFloat, contentHeight > 0 {
                     DispatchQueue.main.async {
                         self?.parent?.contentHeight = max(300, contentHeight)
                     }
                 }
             }

             // Additional measurement for images that load asynchronously
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                 webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] height, _ in
                     if let contentHeight = height as? CGFloat, contentHeight > 300 {
                         DispatchQueue.main.async {
                             self?.parent?.contentHeight = contentHeight
                         }
                     }
                 }
             }
             
             // Final measurement after images load
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                 webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] height, _ in
                     if let contentHeight = height as? CGFloat, contentHeight > 0 {
                         DispatchQueue.main.async {
                             self?.parent?.contentHeight = max(300, contentHeight)
                         }
                     }
                 }
             }
         }
    }
}

#Preview {
    EmailDetailView(email: Email.sampleEmails[0])
}