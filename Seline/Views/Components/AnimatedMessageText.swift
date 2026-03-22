import SwiftUI

/// Wraps MarkdownText with a word-by-word character reveal animation
/// Only animates new assistant messages (not history)
struct AnimatedMessageText: View {
    let markdown: String
    let colorScheme: ColorScheme
    let isNewMessage: Bool

    // Animation state
    @State private var revealedCharCount: Int = 0
    @State private var revealTask: Task<Void, Never>?
    @State private var isFullyRevealed = false

    // Animation speed: ~12 chars per frame at 50fps = fast, smooth
    private let charsPerFrame: Int = 12
    private let frameInterval: TimeInterval = 1.0 / 50.0

    var body: some View {
        if isNewMessage && !isFullyRevealed {
            MarkdownText(markdown: String(markdown.prefix(revealedCharCount)), colorScheme: colorScheme)
                .opacity(1)
                .onAppear {
                    startRevealAnimation(resetProgress: revealedCharCount == 0)
                }
                .onDisappear {
                    stopAnimation()
                }
                .onChange(of: markdown) { _ in
                    if revealedCharCount >= markdown.count {
                        revealedCharCount = markdown.count
                        isFullyRevealed = true
                        stopAnimation()
                    } else {
                        startRevealAnimation(resetProgress: false)
                    }
                }
        } else {
            MarkdownText(markdown: markdown, colorScheme: colorScheme)
        }
    }

    private func startRevealAnimation(resetProgress: Bool) {
        guard isNewMessage else {
            isFullyRevealed = true
            return
        }

        stopAnimation()

        if resetProgress {
            revealedCharCount = 0
        } else {
            revealedCharCount = min(revealedCharCount, markdown.count)
        }
        isFullyRevealed = false

        revealTask = Task { @MainActor in
            let targetMarkdown = markdown

            while !Task.isCancelled {
                let newCount = revealedCharCount + charsPerFrame
                if newCount >= targetMarkdown.count {
                    revealedCharCount = targetMarkdown.count
                    isFullyRevealed = true
                    revealTask = nil
                    break
                }

                // Snap to nearest word boundary to avoid mid-word cuts.
                let targetIndex = targetMarkdown.index(
                    targetMarkdown.startIndex,
                    offsetBy: min(newCount, targetMarkdown.count)
                )
                if let spaceIndex = targetMarkdown[..<targetIndex].lastIndex(of: " ") {
                    revealedCharCount = targetMarkdown.distance(
                        from: targetMarkdown.startIndex,
                        to: targetMarkdown.index(after: spaceIndex)
                    )
                } else {
                    revealedCharCount = newCount
                }

                try? await Task.sleep(nanoseconds: UInt64(frameInterval * 1_000_000_000))
            }
        }
    }

    private func stopAnimation() {
        revealTask?.cancel()
        revealTask = nil
    }
}
