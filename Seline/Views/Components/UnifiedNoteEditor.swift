import SwiftUI
import UIKit

// MARK: - Unified Note Editor
// A single-instance text editor that applies Markdown styling dynamically (hiding syntax).

struct UnifiedNoteEditor: UIViewRepresentable {
    @Binding var text: String
    var onEditingChanged: (() -> Void)?
    var onDateDetected: ((Date, String) -> Void)? // (detectedDate, contextText)
    var onTodoInsert: (() -> Void)? // Called when user wants to insert a todo
    var isReceiptNote: Bool = false // Disable calendar icons for receipts
    
    // Typography settings - Fixed hierarchy: title(22) > H1(20) > H2(18) > H3(16)
    private let bodyFont = UIFont.systemFont(ofSize: 15, weight: .regular)
    private let h1Font = UIFont.systemFont(ofSize: 20, weight: .bold)
    private let h2Font = UIFont.systemFont(ofSize: 18, weight: .bold)
    private let h3Font = UIFont.systemFont(ofSize: 16, weight: .bold)
    private let boldFont = UIFont.systemFont(ofSize: 15, weight: .bold)
    private let italicFont = UIFont.italicSystemFont(ofSize: 15)
    
    func makeUIView(context: Context) -> MarkdownTextView {
        let textView = MarkdownTextView()
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.isEditable = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        
        textView.font = bodyFont
        textView.textColor = UIColor.label
        
        // Placeholder
        let placeholderLabel = UILabel()
        placeholderLabel.text = "Start typing..."
        placeholderLabel.font = bodyFont
        placeholderLabel.textColor = UIColor.placeholderText
        placeholderLabel.backgroundColor = .clear
        placeholderLabel.tag = 999
        textView.addSubview(placeholderLabel)
        
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
            placeholderLabel.widthAnchor.constraint(equalTo: textView.widthAnchor)
        ])
        
        textView.text = text
        context.coordinator.updatePlaceholder(textView: textView)
        context.coordinator.applyStyling(to: textView)
        
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        return textView
    }
    
    func updateUIView(_ uiView: MarkdownTextView, context: Context) {
        // Only update if there's an actual difference and not currently focused/editing
        // This prevents cursor jumping during active typing
        let currentText = uiView.text ?? ""
        if currentText != text && !uiView.isFirstResponder {
            let selectedRange = uiView.selectedRange
            uiView.text = text
            context.coordinator.applyStyling(to: uiView)
            context.coordinator.updatePlaceholder(textView: uiView)
            // Restore selection only if within bounds
            if selectedRange.location <= text.count {
                uiView.selectedRange = selectedRange
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: UnifiedNoteEditor
        
        init(_ parent: UnifiedNoteEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            // CRITICAL: Save text immediately to preserve newlines and all characters
            let currentText = textView.text ?? ""
            parent.text = currentText
            
            // Save cursor position before styling
            let cursorPosition = textView.selectedRange
            
            // Apply styling (this sets attributedText which can affect cursor)
            applyStyling(to: textView)
            
            // CRITICAL: Restore cursor position after styling
            if cursorPosition.location <= (textView.text?.count ?? 0) {
                textView.selectedRange = cursorPosition
            }
            
            updatePlaceholder(textView: textView)
            parent.onEditingChanged?()
            textView.invalidateIntrinsicContentSize()
        }
        
        // MARK: - Auto-continue Todo Lists on Enter
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Check if Enter was pressed
            guard text == "\n" else { return true }
            
            let currentText = textView.text ?? ""
            let nsText = currentText as NSString
            
            // Find the current line
            let lineRange = nsText.lineRange(for: range)
            let currentLine = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
            
            // Check if current line is a todo item
            let uncheckedPattern = "^- \\[ \\]\\s*(.*)$"
            let checkedPattern = "^- \\[x\\]\\s*(.*)$"
            
            var isTodoLine = false
            var todoContent = ""
            
            if let regex = try? NSRegularExpression(pattern: uncheckedPattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: currentLine, options: [], range: NSRange(location: 0, length: currentLine.utf16.count)) {
                isTodoLine = true
                if match.numberOfRanges > 1 {
                    todoContent = (currentLine as NSString).substring(with: match.range(at: 1))
                }
            } else if let regex = try? NSRegularExpression(pattern: checkedPattern, options: .caseInsensitive),
                      let match = regex.firstMatch(in: currentLine, options: [], range: NSRange(location: 0, length: currentLine.utf16.count)) {
                isTodoLine = true
                if match.numberOfRanges > 1 {
                    todoContent = (currentLine as NSString).substring(with: match.range(at: 1))
                }
            }
            
            if isTodoLine {
                // If the todo is empty (just "- [ ]" or "- [x]"), remove the todo marker
                if todoContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Remove the empty todo line and insert a blank line
                    let newText = nsText.replacingCharacters(in: lineRange, with: "\n")
                    textView.text = newText
                    parent.text = newText
                    
                    // Position cursor after the newline
                    let newPosition = lineRange.location + 1
                    textView.selectedRange = NSRange(location: min(newPosition, newText.count), length: 0)
                    
                    // Re-apply styling
                    applyStyling(to: textView)
                    parent.onEditingChanged?()
                    return false
                }
                
                // Insert new todo line
                let insertPosition = range.location
                let todoPrefix = "\n- [ ] "
                let newText = nsText.replacingCharacters(in: range, with: todoPrefix)
                textView.text = newText
                parent.text = newText
                
                // Position cursor after the new todo prefix
                let newCursorPosition = insertPosition + todoPrefix.count
                textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
                
                // Re-apply styling
                applyStyling(to: textView)
                parent.onEditingChanged?()
                textView.invalidateIntrinsicContentSize()
                return false
            }
            
            return true
        }
        
        func updatePlaceholder(textView: UITextView) {
            if let label = textView.viewWithTag(999) as? UILabel {
                label.isHidden = !textView.text.isEmpty
            }
        }
        
        // MARK: - Markdown Styling Engine
        func applyStyling(to textView: UITextView) {
            guard let text = textView.text else { return }
            let attributedString = NSMutableAttributedString(string: text)
            let fullRange = NSRange(location: 0, length: text.utf16.count)
            
            // Reset Base Style
            attributedString.addAttribute(.font, value: parent.bodyFont, range: fullRange)
            attributedString.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
            
            // H1: # Heading
            let h1Regex = try? NSRegularExpression(pattern: "^(#\\s+)(.+)$", options: .anchorsMatchLines)
            h1Regex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let syntaxRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: syntaxRange)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: syntaxRange)
                attributedString.addAttribute(.font, value: parent.h1Font, range: contentRange)
            }
            
            // H2: ## Heading
            let h2Regex = try? NSRegularExpression(pattern: "^(##\\s+)(.+)$", options: .anchorsMatchLines)
            h2Regex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let syntaxRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: syntaxRange)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: syntaxRange)
                attributedString.addAttribute(.font, value: parent.h2Font, range: contentRange)
            }
            
            // H3: ### Heading
            let h3Regex = try? NSRegularExpression(pattern: "^(###\\s+)(.+)$", options: .anchorsMatchLines)
            h3Regex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let syntaxRange = match.range(at: 1)
                let contentRange = match.range(at: 2)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: syntaxRange)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: syntaxRange)
                attributedString.addAttribute(.font, value: parent.h3Font, range: contentRange)
            }
            
            // 3. Bold (**bold**)
            let boldRegex = try? NSRegularExpression(pattern: "(\\*\\*)(.+?)(\\*\\*)", options: [])
            boldRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let leadingSyntax = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let trailingSyntax = match.range(at: 3)
                
                // Hide Syntax
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: leadingSyntax)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: trailingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: leadingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: trailingSyntax)
                
                // Style Content
                attributedString.addAttribute(.font, value: parent.boldFont, range: contentRange)
            }
            
            // 4. Todo Checkboxes - Unchecked: - [ ] or * [ ]
            let uncheckedRegex = try? NSRegularExpression(pattern: "^(- \\[ \\]|\\* \\[ \\])\\s*", options: .anchorsMatchLines)
            uncheckedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Replace checkbox syntax with visual checkbox
                let attachment = NSTextAttachment()
                attachment.image = UIImage(systemName: "square")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
                attachment.bounds = CGRect(x: 0, y: -2, width: 16, height: 16)
                
                // Hide the markdown syntax
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: match.range)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: match.range)
            }
            
            // 5. Todo Checkboxes - Checked: - [x] or * [x]
            let checkedRegex = try? NSRegularExpression(pattern: "^(- \\[x\\]|\\* \\[x\\])\\s*", options: [.anchorsMatchLines, .caseInsensitive])
            checkedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Hide the markdown syntax
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: match.range)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: match.range)
            }
            
            // Preserve Selection - CRITICAL: Save before modifying attributedText
            let savedSelection = textView.selectedRange
            let textLength = attributedString.length
            
            // Apply
            textView.attributedText = attributedString
            
            // Restore selection - ensure it's within valid bounds
            let safeLocation = min(savedSelection.location, textLength)
            let safeLength = min(savedSelection.length, textLength - safeLocation)
            textView.selectedRange = NSRange(location: safeLocation, length: safeLength)
            
            // Add visual checkbox overlays
            addCheckboxOverlays(in: textView, text: text)
            
            // Detect and highlight dates with calendar icon
            detectAndShowDateIcons(in: textView, text: text)
        }
        
        // MARK: - Checkbox Overlays for Todos
        private func addCheckboxOverlays(in textView: UITextView, text: String) {
            // Remove existing checkbox buttons
            textView.subviews.filter { $0.tag == 777 }.forEach { $0.removeFromSuperview() }
            
            // Find unchecked todos: - [ ]
            let uncheckedPattern = "^- \\[ \\]"
            if let uncheckedRegex = try? NSRegularExpression(pattern: uncheckedPattern, options: .anchorsMatchLines) {
                let matches = uncheckedRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    addCheckboxButton(in: textView, at: match.range, isChecked: false, text: text)
                }
            }
            
            // Find checked todos: - [x]
            let checkedPattern = "^- \\[x\\]"
            if let checkedRegex = try? NSRegularExpression(pattern: checkedPattern, options: [.anchorsMatchLines, .caseInsensitive]) {
                let matches = checkedRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    addCheckboxButton(in: textView, at: match.range, isChecked: true, text: text)
                }
            }
        }
        
        private func addCheckboxButton(in textView: UITextView, at range: NSRange, isChecked: Bool, text: String) {
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            
            let checkboxButton = UIButton(type: .system)
            let imageName = isChecked ? "checkmark.square.fill" : "square"
            let imageColor = isChecked ? UIColor.systemGreen : UIColor.secondaryLabel
            checkboxButton.setImage(UIImage(systemName: imageName)?.withTintColor(imageColor, renderingMode: .alwaysOriginal), for: .normal)
            checkboxButton.frame = CGRect(x: rect.origin.x, y: rect.origin.y + textView.textContainerInset.top, width: 22, height: 22)
            checkboxButton.tag = 777
            checkboxButton.accessibilityLabel = "\(range.location)|\(isChecked ? "checked" : "unchecked")"
            checkboxButton.addTarget(self, action: #selector(checkboxTapped(_:)), for: .touchUpInside)
            
            textView.addSubview(checkboxButton)
        }
        
        @objc private func checkboxTapped(_ sender: UIButton) {
            guard let info = sender.accessibilityLabel?.components(separatedBy: "|"),
                  info.count >= 2,
                  let location = Int(info[0]) else { return }
            
            let isCurrentlyChecked = info[1] == "checked"
            
            // Toggle the checkbox in the text
            var text = parent.text
            let nsText = text as NSString
            
            if isCurrentlyChecked {
                // Change [x] to [ ]
                let range = NSRange(location: location, length: 5) // "- [x]"
                text = nsText.replacingCharacters(in: range, with: "- [ ]")
            } else {
                // Change [ ] to [x]
                let range = NSRange(location: location, length: 5) // "- [ ]"
                text = nsText.replacingCharacters(in: range, with: "- [x]")
            }
            
            parent.text = text
        }
        
        // MARK: - Date Detection with Highlighted Tappable Text
        private func detectAndShowDateIcons(in textView: UITextView, text: String) {
            // Always remove existing date buttons first (cleanup from old implementation)
            textView.subviews.filter { $0.tag == 888 }.forEach { $0.removeFromSuperview() }
            
            // Skip date highlighting for receipt notes
            if parent.isReceiptNote {
                return
            }
            
            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return }
            let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            
            guard !matches.isEmpty else { return }
            
            // Apply highlighting to date ranges in the attributed text
            let attributedString = NSMutableAttributedString(attributedString: textView.attributedText)
            
            for match in matches {
                guard let date = match.date,
                      date >= Calendar.current.startOfDay(for: Date()) else { continue }
                
                guard let textRange = Range(match.range, in: text) else { continue }
                
                // Extract context (full line containing the date)
                let lineStart = text[..<textRange.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
                let lineEnd = text[textRange.upperBound...].firstIndex(of: "\n") ?? text.endIndex
                let fullLine = String(text[lineStart..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Create a custom link URL with date info
                let linkInfo = "\(date.timeIntervalSince1970)|\(fullLine)"
                if let linkURL = URL(string: "datelink://\(linkInfo.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "")") {
                    // Add link attribute for tap detection
                    attributedString.addAttribute(.link, value: linkURL, range: match.range)
                    
                    // Light blue background to indicate tappability
                    attributedString.addAttribute(.backgroundColor, value: UIColor.systemBlue.withAlphaComponent(0.15), range: match.range)
                }
            }
            
            // Save selection and apply
            let savedSelection = textView.selectedRange
            textView.attributedText = attributedString
            textView.selectedRange = savedSelection
            
            // Configure link tap handling - no underline, just background color
            textView.linkTextAttributes = [
                .foregroundColor: UIColor.label,
                .backgroundColor: UIColor.systemBlue.withAlphaComponent(0.15)
            ]
        }
        
        // Handle taps on date links - show confirmation popup
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if URL.scheme == "datelink", let host = URL.host?.removingPercentEncoding {
                let parts = host.components(separatedBy: "|")
                if parts.count >= 2, let timestamp = Double(parts[0]) {
                    let date = Date(timeIntervalSince1970: timestamp)
                    let context = parts[1]
                    
                    // Show confirmation alert
                    DispatchQueue.main.async {
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
                            
                            alert.addAction(UIAlertAction(title: "Create Event", style: .default) { _ in
                                self.parent.onDateDetected?(date, context)
                            })
                            
                            // Cancel option removed as user can dismiss by tapping elsewhere
                            
                            rootViewController.present(alert, animated: true)
                        }
                    }
                }
                return false // Don't open in Safari
            }
            return true
        }
    }
}

// MARK: - Custom TextView to intercept Menu Commands
class MarkdownTextView: UITextView {
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupMenuItems()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMenuItems()
    }
    
    private func setupMenuItems() {
        // Add custom menu items - Format group first (H1, H2, H3), then standard B/I
        let h1Item = UIMenuItem(title: "Heading 1", action: #selector(makeH1))
        let h2Item = UIMenuItem(title: "Heading 2", action: #selector(makeH2))
        let h3Item = UIMenuItem(title: "Heading 3", action: #selector(makeH3))
        // Note: UIMenuController items appear AFTER system items, so we can't move them before Bold/Italic
        // But we can use clearer names
        UIMenuController.shared.menuItems = [h1Item, h2Item, h3Item]
    }
    
    // Intercept "Bold" command
    override func toggleBoldface(_ sender: Any?) {
        wrapSelection(with: "**")
    }
    
    // Intercept "Italic" command
    override func toggleItalics(_ sender: Any?) {
        wrapSelection(with: "*")
    }
    
    @objc func makeH1() {
        wrapLineWithHeading("# ")
    }
    
    @objc func makeH2() {
        wrapLineWithHeading("## ")
    }
    
    @objc func makeH3() {
        wrapLineWithHeading("### ")
    }
    
    private func wrapLineWithHeading(_ prefix: String) {
        let range = self.selectedRange
        guard let text = self.text, range.length > 0 else { return }
        
        let nsString = text as NSString
        let selectedText = nsString.substring(with: range)
        
        // Remove existing heading prefix if any
        var cleanText = selectedText
        if cleanText.hasPrefix("### ") {
            cleanText = String(cleanText.dropFirst(4))
        } else if cleanText.hasPrefix("## ") {
            cleanText = String(cleanText.dropFirst(3))
        } else if cleanText.hasPrefix("# ") {
            cleanText = String(cleanText.dropFirst(2))
        }
        
        let newText = "\(prefix)\(cleanText)"
        
        if let textRange = self.textRange(from: self.position(from: beginningOfDocument, offset: range.location)!,
                                          to: self.position(from: beginningOfDocument, offset: range.location + range.length)!) {
            self.replace(textRange, withText: newText)
        }
    }
    
    private func wrapSelection(with syntax: String) {
        let range = self.selectedRange
        guard let text = self.text, range.length > 0 else { return }
        
        let nsString = text as NSString
        let selectedText = nsString.substring(with: range)
        let newText = "\(syntax)\(selectedText)\(syntax)"
        
        if let textRange = self.textRange(from: self.position(from: beginningOfDocument, offset: range.location)!,
                                          to: self.position(from: beginningOfDocument, offset: range.location + range.length)!) {
            self.replace(textRange, withText: newText)
        }
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleBoldface(_:)) || 
           action == #selector(toggleItalics(_:)) ||
           action == #selector(makeH1) ||
           action == #selector(makeH2) ||
           action == #selector(makeH3) {
            return selectedRange.length > 0
        }
        return super.canPerformAction(action, withSender: sender)
    }
}
