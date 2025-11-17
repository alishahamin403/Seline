import SwiftUI

/// Reusable email body display component that handles expand/collapse
/// Used in both EmailDetailView and ViewEventView for consistent email display
struct ReusableEmailBodyView: View {
    let htmlContent: String?
    let plainTextContent: String?
    let aiSummary: String?
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let isLoading: Bool
    @Environment(\.colorScheme) var colorScheme

    private var hasHTMLContent: Bool {
        guard let html = htmlContent else { return false }
        return !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && html.contains("<")
    }

    private var bodyText: String? {
        if let html = htmlContent, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return html
        }
        return plainTextContent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Expandable header button
            Button(action: onToggleExpand) {
                HStack {
                    Text("Original Email")
                        .font(FontManager.geist(size: .body, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
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
            if isExpanded {
                if isLoading {
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
                } else {
                    VStack(spacing: 12) {
                        // AI Summary Section (if available)
                        if let summary = aiSummary, !summary.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                                    Text("AI Summary")
                                        .font(FontManager.geist(size: .body, weight: .semibold))
                                        .foregroundColor(Color.shadcnForeground(colorScheme))
                                }

                                Text(summary)
                                    .font(FontManager.geist(size: .body, weight: .regular))
                                    .foregroundColor(Color.shadcnForeground(colorScheme))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ?
                                                Color.white.opacity(0.05) :
                                                Color.black.opacity(0.03))
                                    )
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                        }

                        // Original Email Body
                        if hasHTMLContent {
                            // HTML content with zoom capability
                            ZoomableHTMLContentView(htmlContent: htmlContent ?? "")
                                .frame(height: 500)
                                .background(
                                    colorScheme == .dark ?
                                        Color.black :
                                        Color.white
                                )
                        } else if let bodyText = bodyText {
                            // Plain text content
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
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

#Preview {
    ReusableEmailBodyView(
        htmlContent: "<p>This is a sample email with HTML content</p>",
        plainTextContent: "Sample plain text email",
        aiSummary: "This email discusses an important meeting scheduled for next week.",
        isExpanded: true,
        onToggleExpand: {},
        isLoading: false
    )
}
