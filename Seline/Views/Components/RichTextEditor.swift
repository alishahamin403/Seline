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

        // Set initial attributed text while preserving existing formatting
        let mutableAttrString = NSMutableAttributedString(attributedString: attributedText)
        if mutableAttrString.length > 0 {
            // Preserve existing formatting and only update color scheme
            let fullRange = NSRange(location: 0, length: mutableAttrString.length)
            let textColor = colorScheme == .dark ? UIColor.white : UIColor.black

            // Update color for all text
            mutableAttrString.addAttribute(.foregroundColor, value: textColor, range: fullRange)

            // Ensure all text has a font (preserve existing, apply default if missing)
            var position = 0
            while position < mutableAttrString.length {
                let range = NSRange(location: position, length: 1)
                var effectiveRange = NSRange()
                if let font = mutableAttrString.attribute(.font, at: position, effectiveRange: &effectiveRange) as? UIFont {
                    // Font exists at this position, skip to end of this font range
                    position = effectiveRange.location + effectiveRange.length
                } else {
                    // No font exists, apply default
                    mutableAttrString.addAttribute(.font, value: UIFont.systemFont(ofSize: 15, weight: .regular), range: range)
                    position += 1
                }
            }
        }

        // Hide table and todo markers from display
        let displayText = hideMarkers(mutableAttrString)
        textView.attributedText = displayText

        return textView
    }

    func updateUIView(_ uiView: CustomTextView, context: Context) {
        // Only update if the attributed text has actually changed
        if !uiView.attributedText.isEqual(to: attributedText) {
            let currentSelectedRange = uiView.selectedRange

            let mutableAttrString = NSMutableAttributedString(attributedString: attributedText)
            if mutableAttrString.length > 0 {
                // Preserve existing formatting and only update color scheme
                let fullRange = NSRange(location: 0, length: mutableAttrString.length)
                let textColor = colorScheme == .dark ? UIColor.white : UIColor.black

                // Update color for all text
                mutableAttrString.addAttribute(.foregroundColor, value: textColor, range: fullRange)

                // Ensure all text has a font (preserve existing, apply default if missing)
                var position = 0
                while position < mutableAttrString.length {
                    let range = NSRange(location: position, length: 1)
                    var effectiveRange = NSRange()
                    if let font = mutableAttrString.attribute(.font, at: position, effectiveRange: &effectiveRange) as? UIFont {
                        // Font exists at this position, skip to end of this font range
                        position = effectiveRange.location + effectiveRange.length
                    } else {
                        // No font exists, apply default
                        mutableAttrString.addAttribute(.font, value: UIFont.systemFont(ofSize: 15, weight: .regular), range: range)
                        position += 1
                    }
                }
            }

            // Hide table and todo markers from display
            let displayText = hideMarkers(mutableAttrString)
            uiView.attributedText = displayText
            uiView.selectedRange = currentSelectedRange
        }

        // Update typing attributes for new text
        uiView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black
        ]
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    // Helper function to hide table and todo markers from display
    private func hideMarkers(_ attributedString: NSMutableAttributedString) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(attributedString: attributedString)

        // Hide table markers [TABLE:UUID]
        let tablePattern = "\\[TABLE:[0-9A-F-]+\\]"
        if let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: .caseInsensitive) {
            let text = result.string
            let tableMatches = tableRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            // Process matches in reverse order to maintain correct indices
            for match in tableMatches.reversed() {
                result.deleteCharacters(in: match.range)
            }
        }

        // Hide todo markers [TODO:UUID]
        let todoPattern = "\\[TODO:[0-9A-F-]+\\]"
        if let todoRegex = try? NSRegularExpression(pattern: todoPattern, options: .caseInsensitive) {
            let text = result.string
            let todoMatches = todoRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))

            // Process matches in reverse order to maintain correct indices
            for match in todoMatches.reversed() {
                result.deleteCharacters(in: match.range)
            }
        }

        return result
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

                // Bounds check: ensure cursor position is valid
                guard cursorPosition >= 0 && cursorPosition <= text.count else {
                    if let attributedText = textView.attributedText {
                        parent.onTextChange(attributedText)
                    }
                    return
                }

                // Check for "- " pattern (2 chars)
                if cursorPosition >= 2 && cursorPosition <= text.count {
                    // Use safe index validation
                    guard let startIndex = text.index(text.startIndex, offsetBy: cursorPosition - 2, limitedBy: text.endIndex),
                          let endIndex = text.index(text.startIndex, offsetBy: cursorPosition, limitedBy: text.endIndex),
                          startIndex < endIndex else {
                        if let attributedText = textView.attributedText {
                            parent.onTextChange(attributedText)
                        }
                        return
                    }

                    let lastTwoChars = String(text[startIndex..<endIndex])

                    if lastTwoChars == "- " {
                        // Find start of line
                        var lineStart = cursorPosition - 2
                        while lineStart > 0 && lineStart - 1 < text.count {
                            if let index = text.index(text.startIndex, offsetBy: lineStart - 1, limitedBy: text.endIndex) {
                                if text[index] == "\n" {
                                    break
                                }
                            }
                            lineStart -= 1
                        }

                        // Check if it's at the beginning of a line
                        var isAtLineStart = lineStart == cursorPosition - 2
                        if !isAtLineStart && lineStart > 0 && lineStart - 1 < text.count {
                            if let index = text.index(text.startIndex, offsetBy: lineStart - 1, limitedBy: text.endIndex) {
                                isAtLineStart = text[index] == "\n"
                            }
                        }

                        if isAtLineStart {
                            applyBulletFormatting(to: textView, lineStart: lineStart, cursorPosition: cursorPosition)
                            if let attributedText = textView.attributedText {
                                parent.onTextChange(attributedText)
                            }
                            return
                        }
                    }
                }

                // Check for "1. " or "2. " pattern (3 chars)
                if cursorPosition >= 3 && cursorPosition <= text.count {
                    // Use safe index validation
                    guard let startIndex = text.index(text.startIndex, offsetBy: cursorPosition - 3, limitedBy: text.endIndex),
                          let endIndex = text.index(text.startIndex, offsetBy: cursorPosition, limitedBy: text.endIndex),
                          startIndex < endIndex else {
                        if let attributedText = textView.attributedText {
                            parent.onTextChange(attributedText)
                        }
                        return
                    }

                    let lastThreeChars = String(text[startIndex..<endIndex])

                    // Check if it matches number + period + space
                    if lastThreeChars.count == 3,
                       let firstChar = lastThreeChars.first,
                       firstChar.isNumber,
                       lastThreeChars[lastThreeChars.index(lastThreeChars.startIndex, offsetBy: 1)] == ".",
                       lastThreeChars.last == " " {

                        // Find start of line
                        var lineStart = cursorPosition - 3
                        while lineStart > 0 && lineStart - 1 < text.count {
                            if let index = text.index(text.startIndex, offsetBy: lineStart - 1, limitedBy: text.endIndex) {
                                if text[index] == "\n" {
                                    break
                                }
                            }
                            lineStart -= 1
                        }

                        // Check if it's at the beginning of a line
                        var isAtLineStart = lineStart == cursorPosition - 3
                        if !isAtLineStart && lineStart > 0 && lineStart - 1 < text.count {
                            if let index = text.index(text.startIndex, offsetBy: lineStart - 1, limitedBy: text.endIndex) {
                                isAtLineStart = text[index] == "\n"
                            }
                        }

                        if isAtLineStart {
                            applyBulletFormatting(to: textView, lineStart: lineStart, cursorPosition: cursorPosition)
                            if let attributedText = textView.attributedText {
                                parent.onTextChange(attributedText)
                            }
                            return
                        }
                    }
                }

                // Maintain bullet formatting while typing on existing bullet lines
                maintainBulletFormatting(textView: textView, cursorPosition: cursorPosition)
            }

            if let attributedText = textView.attributedText {
                parent.onTextChange(attributedText)
            }
        }

        private func maintainBulletFormatting(textView: UITextView, cursorPosition: Int) {
            // Find the current line
            let text = textView.text as NSString

            // Bounds check
            guard cursorPosition >= 0 && cursorPosition <= text.length else { return }

            var lineStart = cursorPosition
            while lineStart > 0 && lineStart - 1 < text.length && text.character(at: lineStart - 1) != 10 { // 10 is newline
                lineStart -= 1
            }

            var lineEnd = cursorPosition
            while lineEnd < text.length && text.character(at: lineEnd) != 10 {
                lineEnd += 1
            }

            // Bounds check for line range
            guard lineStart >= 0 && lineEnd <= text.length && lineStart <= lineEnd else { return }

            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
            let currentLine = text.substring(with: lineRange)

            // Check if the current line starts with a bullet
            if currentLine.hasPrefix("- ") || currentLine.range(of: "^\\d+\\.\\s", options: .regularExpression) != nil {
                let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.headIndent = 25
                paragraphStyle.firstLineHeadIndent = 0
                paragraphStyle.lineBreakMode = .byWordWrapping

                mutableAttrString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
                textView.attributedText = mutableAttrString

                // Restore cursor position
                if let newPosition = textView.position(from: textView.beginningOfDocument, offset: cursorPosition) {
                    textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
                }
            }
        }

        private func applyBulletFormatting(to textView: UITextView, lineStart: Int, cursorPosition: Int) {
            // Apply bullet point formatting
            let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = 25
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.lineBreakMode = .byWordWrapping

            // Find the end of the current line (or end of text)
            let text = textView.text as NSString

            // Bounds check
            guard lineStart >= 0 && cursorPosition >= 0 && cursorPosition <= text.length else { return }

            var lineEnd = cursorPosition
            while lineEnd < text.length && text.character(at: lineEnd) != 10 { // 10 is newline
                lineEnd += 1
            }

            // Bounds check for line range
            guard lineStart <= lineEnd && lineEnd <= text.length else { return }

            // Apply paragraph style to the entire line
            let lineRange = NSRange(location: lineStart, length: lineEnd - lineStart)
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

        // Handle Return key to continue bullet points
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Check if user pressed Return
            guard text == "\n" else { return true }

            let content = textView.text as NSString

            // Bounds check
            guard range.location <= content.length else { return true }

            // Find the current line
            var lineStart = range.location
            while lineStart > 0 && lineStart - 1 < content.length && content.character(at: lineStart - 1) != 10 { // 10 is newline
                lineStart -= 1
            }

            let lineEnd = range.location

            // Bounds check for line range
            guard lineStart >= 0 && lineEnd <= content.length && lineStart <= lineEnd else { return true }

            let currentLine = content.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))

            // Check if current line has a bullet point
            let trimmedLine = currentLine.trimmingCharacters(in: .whitespaces)

            // If the line only has the bullet marker (no content), remove the bullet
            if trimmedLine == "-" || trimmedLine.matches(of: /^\d+\.$/).count > 0 {
                // Remove the bullet marker
                let deleteRange = NSRange(location: lineStart, length: lineEnd - lineStart)
                textView.textStorage.replaceCharacters(in: deleteRange, with: "")
                return false
            }

            // Check for dash bullet
            if currentLine.hasPrefix("- ") {
                // Insert newline and new bullet
                let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)

                // Create paragraph style for bullet
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.headIndent = 25
                paragraphStyle.firstLineHeadIndent = 0
                paragraphStyle.lineBreakMode = .byWordWrapping

                // Create new bullet line with attributes
                let newBullet = NSAttributedString(
                    string: "\n- ",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                        .foregroundColor: parent.colorScheme == .dark ? UIColor.white : UIColor.black,
                        .paragraphStyle: paragraphStyle
                    ]
                )

                mutableAttrString.insert(newBullet, at: range.location)
                textView.attributedText = mutableAttrString

                // Move cursor after the new bullet
                if let newPosition = textView.position(from: textView.beginningOfDocument, offset: range.location + 3) {
                    textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
                }

                parent.onTextChange(mutableAttrString)
                return false
            }

            // Check for numbered bullet (e.g., "1. ", "2. ")
            let numberPattern = /^(\d+)\.\s/
            if let match = currentLine.firstMatch(of: numberPattern) {
                let currentNumber = Int(match.1) ?? 0
                let nextNumber = currentNumber + 1

                // Insert newline and new numbered bullet
                let mutableAttrString = NSMutableAttributedString(attributedString: textView.attributedText)

                // Create paragraph style for bullet
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.headIndent = 25
                paragraphStyle.firstLineHeadIndent = 0
                paragraphStyle.lineBreakMode = .byWordWrapping

                // Create new bullet line with attributes
                let newBullet = NSAttributedString(
                    string: "\n\(nextNumber). ",
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                        .foregroundColor: parent.colorScheme == .dark ? UIColor.white : UIColor.black,
                        .paragraphStyle: paragraphStyle
                    ]
                )

                mutableAttrString.insert(newBullet, at: range.location)
                textView.attributedText = mutableAttrString

                // Move cursor after the new bullet
                let bulletLength = "\n\(nextNumber). ".count
                if let newPosition = textView.position(from: textView.beginningOfDocument, offset: range.location + bulletLength) {
                    textView.selectedTextRange = textView.textRange(from: newPosition, to: newPosition)
                }

                parent.onTextChange(mutableAttrString)
                return false
            }

            return true
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
