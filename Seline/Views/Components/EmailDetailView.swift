import SwiftUI

struct EmailDetailView: View {
    let email: Email
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showingGmailAlert = false
    @State private var gmailAlertMessage = ""

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Main content
                    ScrollView {
                        VStack(spacing: 20) {
                            // Email Header
                            headerSection

                            // Sender/Recipient Information
                            CompactSenderView(email: email)

                            // AI Summary Section
                            if let aiSummary = email.aiSummary {
                                AISummaryCard(summary: aiSummary)
                            }

                            // Attachments Section
                            if !email.attachments.isEmpty {
                                attachmentsSection
                            }

                            // Bottom spacing to account for fixed buttons
                            Spacer()
                                .frame(height: 100)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    }

                    // Fixed action buttons at bottom
                    VStack(spacing: 0) {
                        EmailActionButtons(
                            onReply: {
                                // TODO: Implement reply functionality
                                print("Reply to email: \(email.subject)")
                            },
                            onForward: {
                                // TODO: Implement forward functionality
                                print("Forward email: \(email.subject)")
                            },
                            onDelete: {
                                // TODO: Implement delete functionality
                                print("Delete email: \(email.subject)")
                                dismiss()
                            },
                            onOpenInGmail: {
                                openEmailInGmail()
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            colorScheme == .dark ?
                                Color(red: 0.11, green: 0.11, blue: 0.12) : // Dark gray for dark mode
                                Color.white
                        )
                    }
                }
                .background(
                    colorScheme == .dark ?
                        Color(red: 0.11, green: 0.11, blue: 0.12) : // Dark gray for dark mode
                        Color.white
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .alert("Gmail", isPresented: $showingGmailAlert) {
            Button("OK") { }
        } message: {
            Text(gmailAlertMessage)
        }
    }

    // MARK: - Gmail Opening Logic
    private func openEmailInGmail() {
        GmailURLHelper.openEmailInGmail(email) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    // Successfully opened Gmail - no action needed
                    break
                case .failure(let error):
                    gmailAlertMessage = error.userFriendlyMessage
                    showingGmailAlert = true
                }
            }
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
}

#Preview {
    EmailDetailView(email: Email.sampleEmails[0])
}