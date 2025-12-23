import SwiftUI
import UIKit

// Clean, simple rich text editor - rebuilt from scratch to eliminate glitches
struct SimpleRichTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var colorScheme: ColorScheme
    var onSelectionChange: (NSRange) -> Void
    var onTextChange: (NSAttributedString) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.textAlignment = .left
        textView.isEditable = true
        textView.isUserInteractionEnabled = true
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default

        // Configure text container for proper wrapping
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineFragmentPadding = 0

        // Ensure text view expands to fill available width
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Set initial content
        textView.attributedText = attributedText

        // Set typing attributes
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
        ]

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only update if content actually changed
        if !uiView.attributedText.isEqual(to: attributedText) {
            let selectedRange = uiView.selectedRange
            uiView.attributedText = attributedText
            uiView.selectedRange = selectedRange
        }

        // Update typing attributes for color scheme changes
        uiView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
        ]
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        // Use the proposed width to constrain the text view for proper wrapping
        if let width = proposal.width {
            uiView.frame.size.width = width
            let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: width, height: size.height)
        }
        return nil
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: SimpleRichTextEditor

        init(_ parent: SimpleRichTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let text = textView.text else {
                parent.onTextChange(textView.attributedText ?? NSAttributedString())
                return
            }

            let cursorPosition = textView.selectedRange.location

            // CLEAN BULLET DETECTION - only trigger on Enter after bullet
            if cursorPosition >= 1 && cursorPosition <= text.count {
                let charBeforeCursor = (text as NSString).substring(with: NSRange(location: cursorPosition - 1, length: 1))

                // User just pressed Enter
                if charBeforeCursor == "\n" && cursorPosition >= 2 {
                    // Check if previous line had a bullet
                    let beforeEnter = (text as NSString).substring(to: cursorPosition - 1)
                    let lines = beforeEnter.components(separatedBy: "\n")

                    if let lastLine = lines.last {
                        let trimmed = lastLine.trimmingCharacters(in: .whitespaces)

                        // Previous line was a bullet point
                        if lastLine.hasPrefix("- ") {
                            // If previous line is empty bullet, remove it
                            if trimmed == "-" || trimmed == "- " {
                                // Remove the empty bullet
                                let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
                                let removeRange = NSRange(location: cursorPosition - lastLine.count - 1, length: lastLine.count + 1)
                                if removeRange.location >= 0 && removeRange.location + removeRange.length <= mutable.length {
                                    mutable.deleteCharacters(in: removeRange)
                                    textView.attributedText = mutable
                                    textView.selectedRange = NSRange(location: removeRange.location, length: 0)
                                }
                            } else {
                                // Add new bullet
                                insertBullet(in: textView, at: cursorPosition, numbered: false)
                                return
                            }
                        }
                        // Previous line was numbered
                        else if let match = trimmed.range(of: "^(\\d+)\\.", options: .regularExpression) {
                            let numberStr = String(trimmed[match]).dropLast() // Remove the dot
                            if let currentNum = Int(numberStr) {
                                // If previous line is empty numbered item, remove it
                                if trimmed == "\(currentNum)." || trimmed == "\(currentNum). " {
                                    // Remove the empty numbered item
                                    let mutable = NSMutableAttributedString(attributedString: textView.attributedText)
                                    let removeRange = NSRange(location: cursorPosition - lastLine.count - 1, length: lastLine.count + 1)
                                    if removeRange.location >= 0 && removeRange.location + removeRange.length <= mutable.length {
                                        mutable.deleteCharacters(in: removeRange)
                                        textView.attributedText = mutable
                                        textView.selectedRange = NSRange(location: removeRange.location, length: 0)
                                    }
                                } else {
                                    // Add new numbered bullet
                                    insertBullet(in: textView, at: cursorPosition, numbered: true, number: currentNum + 1)
                                    return
                                }
                            }
                        }
                    }
                }
            }

            // Notify parent of change
            parent.onTextChange(textView.attributedText ?? NSAttributedString())
        }

        private func insertBullet(in textView: UITextView, at position: Int, numbered: Bool, number: Int = 1) {
            let mutable = NSMutableAttributedString(attributedString: textView.attributedText)

            let bulletText = numbered ? "\(number). " : "- "
            let bulletAttr = NSAttributedString(
                string: bulletText,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                    .foregroundColor: parent.colorScheme == .dark ? UIColor.white : UIColor.black
                ]
            )

            if position >= 0 && position <= mutable.length {
                mutable.insert(bulletAttr, at: position)
                textView.attributedText = mutable
                textView.selectedRange = NSRange(location: position + bulletText.count, length: 0)
                parent.onTextChange(textView.attributedText ?? NSAttributedString())
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            parent.onSelectionChange(textView.selectedRange)
        }
    }
}
