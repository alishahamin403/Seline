import SwiftUI

struct EmailDetailView: View {
    let email: Email
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var emailService = EmailService.shared
    @StateObject private var openAIService = OpenAIService.shared
    @State private var isOriginalEmailExpanded: Bool = false
    @State private var fullEmail: Email? = nil
    @State private var isLoadingFullBody: Bool = false
    @State private var showAddEventSheet: Bool = false
    @State private var showSaveFolderSheet: Bool = false

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
                            CompactSenderView(email: email)
                                .padding(.horizontal, 20)

                            // AI Summary Section - always show
                            AISummaryCard(
                                email: email,
                                onGenerateSummary: { email, forceRegenerate in
                                    await generateAISummary(for: email, forceRegenerate: forceRegenerate)
                                }
                            )
                            .padding(.horizontal, 20)

                            // Original Email Content Section (Full Width)
                            originalEmailSection

                            // Attachments Section
                            if !email.attachments.isEmpty {
                                attachmentsSection
                                    .padding(.horizontal, 20)
                            }

                            // Bottom spacing to account for fixed buttons
                            Spacer()
                                .frame(height: 40)
                        }
                        .padding(.top, 24)
                    }

                    // Fixed action buttons at bottom
                    VStack(spacing: 0) {
                        EmailActionButtons(
                            email: email,
                            onReply: {
                                emailService.replyToEmail(email)
                            },
                            onForward: {
                                emailService.forwardEmail(email)
                            },
                            onDelete: {
                                Task {
                                    do {
                                        try await emailService.deleteEmail(email)
                                        dismiss()
                                    } catch {
                                        print("Failed to delete email: \(error.localizedDescription)")
                                        // You could show an alert here if needed
                                    }
                                }
                            },
                            onMarkAsUnread: {
                                emailService.markAsUnread(email)
                                dismiss()
                            },
                            onAddEvent: !isLoadingFullBody ? {
                                showAddEventSheet = true
                            } : nil,
                            onSave: {
                                showSaveFolderSheet = true
                            }
                        )
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
        .sheet(isPresented: $showAddEventSheet) {
            AddEventFromEmailView(email: fullEmail ?? email)
        }
        .sheet(isPresented: $showSaveFolderSheet) {
            SaveFolderSelectionSheet(email: email, isPresented: $showSaveFolderSheet)
        }
        .onAppear {
            // Mark email as read when view appears
            if !email.isRead {
                emailService.markAsRead(email)
            }

            // Fetch full email body if not already loaded
            Task {
                await fetchFullEmailBodyIfNeeded()
            }
        }
    }


    // MARK: - Full Email Body Fetching

    private func fetchFullEmailBodyIfNeeded() async {
        // Only fetch if we don't have a body or if body is empty/snippet only
        guard let messageId = email.gmailMessageId else { return }
        guard email.body == nil || email.body?.isEmpty == true else {
            fullEmail = email
            return
        }

        isLoadingFullBody = true

        do {
            let fetchedEmail = try await GmailAPIClient.shared.fetchFullEmailBody(messageId: messageId)
            fullEmail = fetchedEmail
            print("✅ Fetched full email body for: \(email.subject)")
        } catch {
            print("❌ Failed to fetch full email body: \(error.localizedDescription)")
            fullEmail = email // Fallback to original email
        }

        isLoadingFullBody = false
    }

    // MARK: - AI Summary Generation

    private func generateAISummary(for email: Email, forceRegenerate: Bool = false) async -> Result<String, Error> {
        // Check if email already has a summary (unless force regeneration is requested)
        if !forceRegenerate, let existingSummary = email.aiSummary {
            return .success(existingSummary)
        }

        do {
            // CRITICAL: When regenerating, always fetch the latest full email body
            // This ensures we use the improved extraction logic
            if forceRegenerate || fullEmail == nil {
                await fetchFullEmailBodyIfNeeded()
            }

            // Use full email body if available, otherwise use snippet
            let emailToSummarize = fullEmail ?? email
            let emailBody = emailToSummarize.body ?? emailToSummarize.snippet

            // Check if we have any meaningful content to summarize
            // Remove HTML tags and check actual text content length
            let plainTextContent = stripHTMLTags(from: emailBody)
            if plainTextContent.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                return .success("No content available")
            }

            let summary = try await openAIService.summarizeEmail(
                subject: email.subject,
                body: emailBody
            )

            // If the summary is empty, show "No content available"
            let finalSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No content available" : summary

            // Cache the summary in the email service
            await emailService.updateEmailWithAISummary(email, summary: finalSummary)

            return .success(finalSummary)
        } catch {
            print("Failed to generate AI summary: \(error)")
            return .failure(error)
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Subject
            Text(email.subject)
                .font(FontManager.geist(size: .title1, weight: .bold))
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }



    // MARK: - Original Email Section
    private var originalEmailSection: some View {
        VStack(spacing: 0) {
            // Expandable header button (with padding)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isOriginalEmailExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Original Email")
                        .font(FontManager.geist(size: .body, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()

                    Image(systemName: isOriginalEmailExpanded ? "chevron.up" : "chevron.down")
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

            // Expandable content (full width, no padding)
            if isOriginalEmailExpanded {
                if isLoadingFullBody {
                    // Show loading indicator while fetching full body
                    VStack {
                        ShadcnSpinner(size: .medium)
                            .padding()
                        Text("Loading email content...")
                            .font(FontManager.geist(size: .caption, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background(
                        colorScheme == .dark ?
                            Color.black :
                            Color.white
                    )
                } else if let displayEmail = fullEmail ?? email as Email?,
                          let htmlBody = displayEmail.body,
                          !htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          htmlBody.contains("<") {
                    // Display HTML content using WebView with zoom
                    ZoomableHTMLContentView(htmlContent: htmlBody)
                        .frame(height: 500)
                        .background(
                            colorScheme == .dark ?
                                Color.black :
                                Color.white
                        )
                } else {
                    // Display plain text or show "no content" message
                    let bodyText = (fullEmail ?? email).body ?? (fullEmail ?? email).snippet

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
                    AttachmentRow(attachment: attachment)
                }
            }
        }
    }

    // MARK: - Helper Methods
    private func stripHTMLTags(from html: String) -> String {
        var text = html

        // Remove script and style tags with their content
        text = text.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: .regularExpression
        )

        // Remove all HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        return text
    }
}

#Preview {
    EmailDetailView(email: Email.sampleEmails[0])
}