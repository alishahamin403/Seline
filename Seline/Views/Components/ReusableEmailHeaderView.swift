import SwiftUI

/// Reusable email header component for displaying sender and email metadata
/// Works with both Email objects and TaskItem email data
struct ReusableEmailHeaderView: View {
    // For Email objects
    let email: Email?

    // For TaskItem email data (when Email object isn't available)
    let emailSubject: String?
    let emailSenderName: String?
    let emailSenderEmail: String?
    let emailTimestamp: Date?
    let emailSnippet: String?

    let showSnippet: Bool
    let showTimestamp: Bool
    let style: HeaderStyle

    @Environment(\.colorScheme) var colorScheme

    enum HeaderStyle {
        case fullScreen      // Used in EmailDetailView
        case embedded        // Used in ViewEventView
    }

    // Extract data from Email object if available
    private var subject: String? {
        email?.subject ?? emailSubject
    }

    private var senderName: String? {
        email?.sender.name ?? emailSenderName
    }

    private var senderEmail: String? {
        email?.sender.email ?? emailSenderEmail
    }

    private var timestamp: Date? {
        email?.timestamp ?? emailTimestamp
    }

    private var snippet: String? {
        email?.snippet ?? emailSnippet
    }

    var body: some View {
        switch style {
        case .fullScreen:
            fullScreenHeader
        case .embedded:
            embeddedHeader
        }
    }

    // MARK: - Full Screen Header (for EmailDetailView)
    private var fullScreenHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let subject = subject {
                Text(subject)
                    .font(FontManager.geist(size: .title1, weight: .bold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Embedded Header (for ViewEventView)
    private var embeddedHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Email icon with colored circle
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ?
                            Color.white.opacity(0.2) :
                            Color.black.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: "envelope.fill")
                        .font(.system(size: 16))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // Subject
                    if let subject = subject {
                        Text(subject)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    // Sender info
                    if let senderName = senderName {
                        HStack(spacing: 4) {
                            Text("From:")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color.gray)

                            Text(senderName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ?
                                    Color.white.opacity(0.7) :
                                    Color.black.opacity(0.6))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }

            // Email snippet (collapsible)
            if showSnippet, let snippet = snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.gray)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
            }

            // Timestamp
            if showTimestamp, let timestamp = timestamp {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(Color.gray)

                    Text(formatEmailTimestamp(timestamp))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color.gray)
                }
                .padding(.top, 4)
            }
        }
    }

    private func formatEmailTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    VStack(spacing: 20) {
        // Full screen style
        ReusableEmailHeaderView(
            email: Email.sampleEmails.first,
            emailSubject: nil,
            emailSenderName: nil,
            emailSenderEmail: nil,
            emailTimestamp: nil,
            emailSnippet: nil,
            showSnippet: false,
            showTimestamp: false,
            style: .fullScreen
        )

        Divider()

        // Embedded style
        ReusableEmailHeaderView(
            email: Email.sampleEmails.first,
            emailSubject: nil,
            emailSenderName: nil,
            emailSenderEmail: nil,
            emailTimestamp: nil,
            emailSnippet: nil,
            showSnippet: true,
            showTimestamp: true,
            style: .embedded
        )
    }
    .padding()
}
