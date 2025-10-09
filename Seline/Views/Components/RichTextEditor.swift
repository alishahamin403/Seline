import SwiftUI
import UIKit

// Custom TextEditor wrapper that supports rich text formatting
struct FormattableTextEditor: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var colorScheme: ColorScheme
    var onSelectionChange: (NSRange) -> Void
    var onTextChange: (NSAttributedString) -> Void

    func makeUIView(context: Context) -> CustomTextView {
        let textView = CustomTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        // CRITICAL FIX: Disable internal scrolling - let outer ScrollView handle it
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        textView.coordinator = context.coordinator
        textView.textAlignment = .left
        textView.isEditable = true
        textView.isUserInteractionEnabled = true

        // Configure text container for proper wrapping
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineFragmentPadding = 0

        // Ensure the text view expands to fill available width
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Set initial attributed text with default attributes
        let mutableAttrString = NSMutableAttributedString(attributedString: attributedText)
        if mutableAttrString.length > 0 {
            mutableAttrString.addAttributes([
                .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
            ], range: NSRange(location: 0, length: mutableAttrString.length))
        }
        textView.attributedText = mutableAttrString

        return textView
    }

    func updateUIView(_ uiView: CustomTextView, context: Context) {
        // Only update if the attributed text has actually changed
        if !uiView.attributedText.isEqual(to: attributedText) {
            let currentSelectedRange = uiView.selectedRange

            let mutableAttrString = NSMutableAttributedString(attributedString: attributedText)
            if mutableAttrString.length > 0 {
                // Preserve existing formatting but update color scheme
                mutableAttrString.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: mutableAttrString.length)) { _, range, _ in
                    mutableAttrString.addAttribute(.foregroundColor, value: colorScheme == .dark ? UIColor.white : UIColor.black, range: range)
                }
            }

            uiView.attributedText = mutableAttrString
            uiView.selectedRange = currentSelectedRange
        }

        // Update typing attributes for new text
        uiView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
        ]
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CustomTextView, context: Context) -> CGSize? {
        // Use the proposed width to constrain the text view
        if let width = proposal.width {
            uiView.frame.size.width = width
            let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            return CGSize(width: width, height: size.height)
        }
        return nil
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: FormattableTextEditor
        weak var textView: CustomTextView?

        init(_ parent: FormattableTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // Check for bullet point trigger patterns
            if let text = textView.text, let selectedRange = textView.selectedTextRange {
                let cursorPosition = textView.offset(from: textView.beginningOfDocument, to: selectedRange.start)

                // Check for "- " pattern (2 chars)
                if cursorPosition >= 2 {
                    let startIndex = text.index(text.startIndex, offsetBy: cursorPosition - 2)
                    let endIndex = text.index(text.startIndex, offsetBy: cursorPosition)
                    let lastTwoChars = String(text[startIndex..<endIndex])

                    if lastTwoChars == "- " {
                        // Find start of line
                        var lineStart = cursorPosition - 2
                        while lineStart > 0 {
                            let index = text.index(text.startIndex, offsetBy: lineStart - 1)
                            if text[index] == "\n" {
                                break
                            }
                            lineStart -= 1
                        }

                        // Check if it's at the beginning of a line
                        if lineStart == cursorPosition - 2 || (lineStart > 0 && text[text.index(text.startIndex, offsetBy: lineStart - 1)] == "\n") {
                            applyBulletFormatting(to: textView, lineStart: lineStart, cursorPosition: cursorPosition)
                            if let attributedText = textView.attributedText {
                                parent.onTextChange(attributedText)
                            }
                            return
                        }
                    }
                }

                // Check for "1. " or "2. " pattern (3 chars)
                if cursorPosition >= 3 {
                    let startIndex = text.index(text.startIndex, offsetBy: cursorPosition - 3)
                    let endIndex = text.index(text.startIndex, offsetBy: cursorPosition)
                    let lastThreeChars = String(text[startIndex..<endIndex])

                    // Check if it matches number + period + space
                    if lastThreeChars.count == 3,
                       let firstChar = lastThreeChars.first,
                       firstChar.isNumber,
                       lastThreeChars[lastThreeChars.index(lastThreeChars.startIndex, offsetBy: 1)] == ".",
                       lastThreeChars.last == " " {

                        // Find start of line
                        var lineStart = cursorPosition - 3
                        while lineStart > 0 {
                            let index = text.index(text.startIndex, offsetBy: lineStart - 1)
                            if text[index] == "\n" {
                                break
                            }
                            lineStart -= 1
                        }

                        // Check if it's at the beginning of a line
                        if lineStart == cursorPosition - 3 || (lineStart > 0 && text[text.index(text.startIndex, offsetBy: lineStart - 1)] == "\n") {
                            applyBulletFormatting(to: textView, lineStart: lineStart, cursorPosition: cursorPosition)
                            if let attributedText = textView.attributedText {
                                parent.onTextChange(attributedText)
                            }
                            return
                        }
                    }
                }
            }

            if let attributedText = textView.attributedText {
                parent.onTextChange(attributedText)
            }
        }

        private func applyBulletFormatting(to textView: UITextView, lineStart: Int, cursorPosition: Int) {
            // Apply bullet point formatting
            let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = 25
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.lineBreakMode = .byWordWrapping

            // Find the range of the current line
            let lineRange = NSRange(location: lineStart, length: cursorPosition - lineStart)
            mutableAttrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)

            textView.attributedText = mutableAttrString

            // Restore cursor position
            if let newPosition = textView.position(from: textView.beginningOfDocument, offset: cursorPosition) {
                textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            self.textView = textView as? CustomTextView
            parent.onSelectionChange(textView.selectedRange)
        }

        @objc func makeBold() {
            applyFormat(.bold)
        }

        @objc func makeItalic() {
            applyFormat(.italic)
        }

        @objc func makeUnderline() {
            applyFormat(.underline)
        }

        @objc func makeHeading1() {
            applyFormat(.heading1)
        }

        @objc func makeHeading2() {
            applyFormat(.heading2)
        }

        func applyFormat(_ format: TextFormat) {
            guard let textView = textView else { return }
            let selectedRange = textView.selectedRange
            guard selectedRange.length > 0 else { return }

            let mutableAttributedString = NSMutableAttributedString(attributedString: textView.attributedText)

            switch format {
            case .bold:
                toggleTrait(.traitBold, in: mutableAttributedString, range: selectedRange)
            case .italic:
                toggleTrait(.traitItalic, in: mutableAttributedString, range: selectedRange)
            case .underline:
                toggleUnderline(in: mutableAttributedString, range: selectedRange)
            case .heading1:
                applyHeading(size: 20, in: mutableAttributedString, range: selectedRange)
            case .heading2:
                applyHeading(size: 18, in: mutableAttributedString, range: selectedRange)
            }

            textView.attributedText = mutableAttributedString
            textView.selectedRange = selectedRange
            parent.onTextChange(mutableAttributedString)
        }

        private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits, in attributedString: NSMutableAttributedString, range: NSRange) {
            attributedString.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let currentFont = value as? UIFont ?? UIFont.systemFont(ofSize: 15)

                let newFont: UIFont
                if currentFont.fontDescriptor.symbolicTraits.contains(trait) {
                    // Remove trait
                    var traits = currentFont.fontDescriptor.symbolicTraits
                    traits.remove(trait)
                    if let descriptor = currentFont.fontDescriptor.withSymbolicTraits(traits) {
                        newFont = UIFont(descriptor: descriptor, size: currentFont.pointSize)
                    } else {
                        newFont = UIFont.systemFont(ofSize: currentFont.pointSize)
                    }
                } else {
                    // Add trait
                    var traits = currentFont.fontDescriptor.symbolicTraits
                    traits.insert(trait)
                    if let descriptor = currentFont.fontDescriptor.withSymbolicTraits(traits) {
                        newFont = UIFont(descriptor: descriptor, size: currentFont.pointSize)
                    } else {
                        newFont = currentFont
                    }
                }

                attributedString.addAttribute(.font, value: newFont, range: subRange)
            }
        }

        private func toggleUnderline(in attributedString: NSMutableAttributedString, range: NSRange) {
            var hasUnderline = false
            attributedString.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
                if let underlineValue = value as? Int, underlineValue == NSUnderlineStyle.single.rawValue {
                    hasUnderline = true
                }
            }

            if hasUnderline {
                attributedString.removeAttribute(.underlineStyle, range: range)
            } else {
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }

        private func applyHeading(size: CGFloat, in attributedString: NSMutableAttributedString, range: NSRange) {
            attributedString.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let currentFont = value as? UIFont ?? UIFont.systemFont(ofSize: 15)
                let traits = currentFont.fontDescriptor.symbolicTraits

                var newFont: UIFont
                if let descriptor = currentFont.fontDescriptor.withSymbolicTraits(traits.union(.traitBold)) {
                    newFont = UIFont(descriptor: descriptor, size: size)
                } else {
                    newFont = UIFont.boldSystemFont(ofSize: size)
                }

                attributedString.addAttribute(.font, value: newFont, range: subRange)
            }
        }
    }
}

// Custom UITextView that adds formatting menu items
class CustomTextView: UITextView {
    weak var coordinator: FormattableTextEditor.Coordinator?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(FormattableTextEditor.Coordinator.makeBold) ||
           action == #selector(FormattableTextEditor.Coordinator.makeItalic) ||
           action == #selector(FormattableTextEditor.Coordinator.makeUnderline) ||
           action == #selector(FormattableTextEditor.Coordinator.makeHeading1) ||
           action == #selector(FormattableTextEditor.Coordinator.makeHeading2) {
            return selectedRange.length > 0
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        let formatMenu = UIMenu(title: "Format", options: .displayInline, children: [
            UIAction(title: "Bold", image: UIImage(systemName: "bold")) { [weak self] _ in
                self?.coordinator?.makeBold()
            },
            UIAction(title: "Italic", image: UIImage(systemName: "italic")) { [weak self] _ in
                self?.coordinator?.makeItalic()
            },
            UIAction(title: "Underline", image: UIImage(systemName: "underline")) { [weak self] _ in
                self?.coordinator?.makeUnderline()
            },
            UIAction(title: "Heading 1", image: UIImage(systemName: "textformat.size.larger")) { [weak self] _ in
                self?.coordinator?.makeHeading1()
            },
            UIAction(title: "Heading 2", image: UIImage(systemName: "textformat.size")) { [weak self] _ in
                self?.coordinator?.makeHeading2()
            }
        ])

        builder.insertChild(formatMenu, atStartOfMenu: .standardEdit)
    }
}

enum TextFormat {
    case bold
    case italic
    case underline
    case heading1
    case heading2
}
