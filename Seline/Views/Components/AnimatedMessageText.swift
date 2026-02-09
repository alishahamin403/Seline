import SwiftUI

/// Wraps MarkdownText with a word-by-word character reveal animation
/// Only animates new assistant messages (not history)
struct AnimatedMessageText: View {
    let markdown: String
    let colorScheme: ColorScheme
    let isNewMessage: Bool

    // Animation state
    @State private var revealedCharCount: Int = 0
    @State private var animationTimer: Timer?
    @State private var isFullyRevealed = false

    // Animation speed: ~12 chars per frame at 50fps = fast, smooth
    private let charsPerFrame: Int = 12
    private let frameInterval: TimeInterval = 1.0 / 50.0

    var body: some View {
        if isNewMessage && !isFullyRevealed {
            MarkdownText(markdown: String(markdown.prefix(revealedCharCount)), colorScheme: colorScheme)
                .opacity(1)
                .onAppear {
                    startRevealAnimation()
                }
                .onDisappear {
                    stopAnimation()
                }
                .onChange(of: markdown) { _ in
                    // If markdown content changes (e.g., streaming), update target
                    if revealedCharCount >= markdown.count {
                        isFullyRevealed = true
                        stopAnimation()
                    }
                }
        } else {
            MarkdownText(markdown: markdown, colorScheme: colorScheme)
        }
    }

    private func startRevealAnimation() {
        guard isNewMessage else {
            isFullyRevealed = true
            return
        }

        revealedCharCount = 0
        isFullyRevealed = false

        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { timer in
            let newCount = revealedCharCount + charsPerFrame
            if newCount >= markdown.count {
                revealedCharCount = markdown.count
                isFullyRevealed = true
                timer.invalidate()
                animationTimer = nil
            } else {
                // Snap to nearest word boundary to avoid mid-word cuts
                let targetIndex = markdown.index(markdown.startIndex, offsetBy: min(newCount, markdown.count))
                if let spaceIndex = markdown[..<targetIndex].lastIndex(of: " ") {
                    revealedCharCount = markdown.distance(from: markdown.startIndex, to: markdown.index(after: spaceIndex))
                } else {
                    revealedCharCount = newCount
                }
            }
        }
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}
