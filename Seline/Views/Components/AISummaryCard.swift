import SwiftUI
import WebKit

enum AISummaryState {
    case collapsed
    case loading
    case loaded(String)
    case error(String)
}

struct AISummaryCard: View {
    @State private var summaryState: AISummaryState = .collapsed
    let email: Email
    let onGenerateSummary: (Email, Bool) async -> Result<String, Error>
    @Environment(\.colorScheme) var colorScheme

    private var summaryBullets: [String] {
        switch summaryState {
        case .loaded(let summary):
            // Split the summary into bullet points by newlines
            return summary
                .components(separatedBy: .newlines)
                .map { line in
                    // Remove bullet point characters (•, *, -, etc.) since UI adds its own
                    var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleaned.hasPrefix("•") || cleaned.hasPrefix("*") || cleaned.hasPrefix("-") {
                        cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    return cleaned
                }
                .filter { !$0.isEmpty }
        default:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header - always visible, no bullet point
            HStack(spacing: 12) {
                Text("AI Summary")
                    .font(FontManager.geist(size: .body, weight: .semibold))
                    .foregroundColor(Color.shadcnForeground(colorScheme))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Content - always shown
            VStack(alignment: .leading, spacing: 16) {
                switch summaryState {
                case .collapsed:
                    loadingView

                case .loading:
                    loadingView

                case .loaded(let summary):
                    // Check if it's a dummy/invalid summary
                    if isDummySummary(summary) {
                        noContentView
                    } else {
                        summaryContentView
                    }

                case .error(let errorMessage):
                    errorView(errorMessage)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .shadcnTileStyle(colorScheme: colorScheme)
        .onAppear {
            // If we already have a summary, check if it's valid
            if let existingSummary = email.aiSummary {
                // If it's a dummy summary, regenerate it
                if isDummySummary(existingSummary) {
                    Task {
                        await generateSummary(forceRegenerate: true)
                    }
                } else {
                    summaryState = .loaded(existingSummary)
                }
            } else {
                // Automatically start generating summary when view appears
                Task {
                    await generateSummary(forceRegenerate: false)
                }
            }
        }
    }

    // MARK: - Helper Functions

    private func isDummySummary(_ summary: String) -> Bool {
        let dummyPhrases = [
            "Additional details mentioned",
            "Further information provided",
            "See email for more details",
            "No content available"
        ]

        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if empty
        if trimmed.isEmpty {
            return true
        }

        // Check if contains dummy phrases
        for phrase in dummyPhrases {
            if trimmed.contains(phrase) {
                return true
            }
        }

        return false
    }

    // MARK: - View Components

    private var noContentView: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(Color.shadcnMuted(colorScheme))

            Text("No content available")
                .font(FontManager.geist(size: .body, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()
        }
        .padding(.vertical, 16)
    }

    private var loadingView: some View {
        HStack(spacing: 12) {
            ShadcnSpinner(size: .medium)

            Text("Generating AI summary...")
                .font(FontManager.geist(size: .body, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()
        }
        .padding(.vertical, 16)
    }

    private var summaryContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(summaryBullets.enumerated()), id: \.offset) { index, bullet in
                HStack(alignment: .top, spacing: 12) {
                    // Bullet point
                    Circle()
                        .fill(Color.shadcnForeground(colorScheme))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)

                    // Bullet text
                    Text(bullet)
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func errorView(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: errorMessage.contains("Rate limit") ? "clock" : "exclamationmark.triangle")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(errorMessage.contains("Rate limit") ? .orange : .red)

                Text(errorMessage.contains("Rate limit") ? "Rate limit reached" : "Failed to generate summary")
                    .font(FontManager.geist(size: .body, weight: .medium))
                    .foregroundColor(errorMessage.contains("Rate limit") ? .orange : .red)
            }

            Text(errorMessage)
                .font(FontManager.geist(size: .caption, weight: .regular))
                .foregroundColor(Color.shadcnMuted(colorScheme))

            Button(action: {
                Task {
                    await generateSummary(forceRegenerate: true)
                }
            }) {
                Text(errorMessage.contains("Rate limit") ? "Retry Now" : "Try Again")
                    .font(FontManager.geist(size: .body, weight: .medium))
                    .foregroundColor(Color.shadcnPrimary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: ShadcnRadius.md)
                            .stroke(Color.shadcnPrimary, lineWidth: 1)
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func generateSummary(forceRegenerate: Bool = false) async {
        summaryState = .loading

        let result = await onGenerateSummary(email, forceRegenerate)

        await MainActor.run {
            switch result {
            case .success(let summary):
                summaryState = .loaded(summary)
            case .failure(let error):
                summaryState = .error(error.localizedDescription)
            }
        }
    }
}

// MARK: - Zoomable HTML Content View

struct ZoomableHTMLContentView: UIViewRepresentable {
    let htmlContent: String
    @Environment(\.colorScheme) var colorScheme

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()

        // Add error handling and security improvements
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false // Disable JS to prevent crashes
        configuration.defaultWebpagePreferences = preferences
        configuration.suppressesIncrementalRendering = false

        let webView = WKWebView(frame: .zero, configuration: configuration)

        // Set navigation delegate for error handling
        webView.navigationDelegate = context.coordinator

        // Enable zooming and scrolling
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.minimumZoomScale = 0.5
        webView.scrollView.maximumZoomScale = 3.0
        webView.scrollView.bouncesZoom = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Validate HTML content before rendering
        guard !htmlContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Load empty page if no content
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            return
        }

        // Sanitize HTML content to prevent crashes
        let sanitizedHTML = sanitizeHTML(htmlContent)

        // Wrap HTML with basic styling that matches Gmail, with zoom enabled
        let backgroundColor = colorScheme == .dark ? "#000000" : "#ffffff"
        let textColor = colorScheme == .dark ? "#ffffff" : "#000000"

        let styledHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=0.5, maximum-scale=3.0, user-scalable=yes">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                    font-size: 14px;
                    line-height: 1.5;
                    color: \(textColor);
                    background-color: \(backgroundColor);
                    margin: 0;
                    padding: 16px;
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                img {
                    max-width: 100%;
                    height: auto;
                }
                a {
                    color: \(textColor);
                    text-decoration: none;
                }
                table {
                    max-width: 100%;
                }
            </style>
        </head>
        <body>
            \(sanitizedHTML)
        </body>
        </html>
        """

        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Helper Functions

    private func sanitizeHTML(_ html: String) -> String {
        var sanitized = html

        // Remove potentially problematic elements that can cause WebKit crashes
        let problematicPatterns = [
            // Remove script tags (even though JS is disabled, removing for safety)
            "<script[^>]*>[\\s\\S]*?</script>",
            // Remove object/embed tags that can cause issues
            "<object[^>]*>[\\s\\S]*?</object>",
            "<embed[^>]*>",
            // Remove iframe tags
            "<iframe[^>]*>[\\s\\S]*?</iframe>",
            // Remove form elements that can cause issues
            "<form[^>]*>[\\s\\S]*?</form>"
        ]

        for pattern in problematicPatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return sanitized
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ WebView failed to load: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ WebView provisional navigation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - External Link HTML View (opens links in Safari)

struct ExternalLinkHTMLView: UIViewRepresentable {
    let htmlContent: String
    @Environment(\.colorScheme) var colorScheme
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Enable JavaScript for better rendering
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        configuration.suppressesIncrementalRendering = false
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        // Set navigation delegate to intercept link clicks
        webView.navigationDelegate = context.coordinator
        
        // Enable zooming and scrolling
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.minimumZoomScale = 0.5
        webView.scrollView.maximumZoomScale = 3.0
        webView.scrollView.bouncesZoom = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !htmlContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            return
        }
        
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
    
    func makeCoordinator() -> ExternalLinkCoordinator {
        ExternalLinkCoordinator()
    }
    
    // MARK: - Coordinator that opens links in Safari
    
    class ExternalLinkCoordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // If it's a link click (not initial page load)
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    // Open in Safari
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel) // Don't navigate in WebView
            } else {
                decisionHandler(.allow) // Allow initial page load
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ ExternalLinkHTMLView failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ ExternalLinkHTMLView provisional navigation failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Auto-Height HTML View (inline scrollable, auto-sizes to content)

struct AutoHeightHTMLView: UIViewRepresentable {
    let htmlContent: String
    @Environment(\.colorScheme) var colorScheme
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Enable JavaScript for better rendering
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        configuration.suppressesIncrementalRendering = false
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        // Set navigation delegate to intercept link clicks
        webView.navigationDelegate = context.coordinator
        
        // Disable scrolling - let parent ScrollView handle it
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard !htmlContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            return
        }
        
        // Add script to calculate content height
        let htmlWithHeightScript = htmlContent.replacingOccurrences(
            of: "</body>",
            with: """
            <script>
                function notifyHeight() {
                    var height = document.body.scrollHeight;
                    window.webkit.messageHandlers.heightHandler.postMessage(height);
                }
                window.onload = notifyHeight;
                setTimeout(notifyHeight, 100);
                setTimeout(notifyHeight, 500);
            </script>
            </body>
            """
        )
        
        webView.loadHTMLString(htmlWithHeightScript, baseURL: nil)
    }
    
    func makeCoordinator() -> AutoHeightCoordinator {
        AutoHeightCoordinator()
    }
    
    // MARK: - Coordinator that opens links in Safari and tracks height
    
    class AutoHeightCoordinator: NSObject, WKNavigationDelegate {
        var contentHeight: CGFloat = 400
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // If it's a link click (not initial page load)
            if navigationAction.navigationType == .linkActivated {
                if let url = navigationAction.request.url {
                    // Open in Safari
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel) // Don't navigate in WebView
            } else {
                decisionHandler(.allow) // Allow initial page load
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Update height after load
            webView.evaluateJavaScript("document.body.scrollHeight") { result, error in
                if let height = result as? CGFloat {
                    self.contentHeight = height
                    // Force layout update
                    webView.invalidateIntrinsicContentSize()
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ AutoHeightHTMLView failed to load: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ AutoHeightHTMLView provisional navigation failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AISummaryCard(
            email: Email.sampleEmails[0],
            onGenerateSummary: { email, forceRegenerate in
                // Mock function for preview
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                    return .success("Q4 marketing campaign exceeded targets by 23%. Budget approval needed by December 15th. Double video marketing investment recommended.")
                } catch {
                    return .failure(error)
                }
            }
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}