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
    var isFocused: Binding<Bool>? = nil
    
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

        // CRITICAL FIX: Enable text wrapping - prevent horizontal expansion
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.maximumNumberOfLines = 0 // Allow unlimited lines

        // Placeholder removed - user knows where to type

        textView.text = text
        context.coordinator.updatePlaceholder(textView: textView)
        context.coordinator.applyStyling(to: textView)

        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return textView
    }
    
    func updateUIView(_ uiView: MarkdownTextView, context: Context) {
        // Check if we have a pending cursor position from todo insertion
        if let pendingPosition = context.coordinator.pendingCursorPosition {
            // Use the pending position and clear it
            context.coordinator.pendingCursorPosition = nil
            
            // Only update if text matches (prevents race conditions)
            if uiView.text == text {
                let safePosition = min(pendingPosition, text.count)
                uiView.selectedRange = NSRange(location: safePosition, length: 0)
            }
            return
        }
        
        // Update if there's an actual difference
        let currentText = uiView.text ?? ""
        if currentText != text {
            // Save cursor position before update
            let savedSelection = uiView.selectedRange
            let wasFirstResponder = uiView.isFirstResponder
            
            // Update text
            uiView.text = text
            context.coordinator.applyStyling(to: uiView)
            context.coordinator.updatePlaceholder(textView: uiView)
            
            // For programmatic insertions (like todo button), move cursor to end of new text
            // This is detected when new text is longer and contains the insertion
            if text.count > currentText.count && wasFirstResponder {
                // Check if this is an insertion at the end (todo button case)
                if text.hasPrefix(currentText) || currentText.isEmpty {
                    // Move cursor to end
                    let newPosition = text.count
                    uiView.selectedRange = NSRange(location: newPosition, length: 0)
                } else {
                    // Restore selection if within bounds
                    let safeLocation = min(savedSelection.location, text.count)
                    uiView.selectedRange = NSRange(location: safeLocation, length: 0)
                }
            } else if savedSelection.location <= text.count {
                uiView.selectedRange = savedSelection
            }
        }

        // Handle Focus - only become first responder when explicitly requested
        // Do NOT auto-resign to prevent keyboard flicker during focus transitions
        if let isFocused = isFocused {
            if isFocused.wrappedValue && !uiView.isFirstResponder {
                // Try immediately first for faster response
                uiView.becomeFirstResponder()
                // Backup async call in case immediate fails
                if !uiView.isFirstResponder {
                    DispatchQueue.main.async { [weak uiView] in
                        uiView?.becomeFirstResponder()
                    }
                }
            }
            // Note: We intentionally don't resignFirstResponder when isFocused becomes false
            // This prevents keyboard from disappearing during title → body transitions
            // The keyboard will dismiss naturally when user taps outside or navigates away
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: UnifiedNoteEditor
        var dismissedContexts: Set<String> = [] // Track dismissed chips by their line context
        var pendingCursorPosition: Int? = nil // Track cursor position after todo insertion
        private var focusDebounceTask: DispatchWorkItem? // Debounce focus changes
        var isInsertingTodo = false // Flag to prevent duplicate overlay updates during todo insertion

        init(_ parent: UnifiedNoteEditor) {
            self.parent = parent
        }

        
        func textViewDidChange(_ textView: UITextView) {
            // CRITICAL: Save text immediately to preserve newlines and all characters
            let currentText = textView.text ?? ""
            parent.text = currentText

            // Skip full styling if we're in the middle of programmatic todo insertion
            // This prevents race conditions with overlay placement
            if isInsertingTodo {
                updatePlaceholder(textView: textView)
                parent.onEditingChanged?()
                textView.invalidateIntrinsicContentSize()
                return
            }

            // Save cursor position before styling
            let cursorPosition = textView.selectedRange

            // Apply styling (this sets attributedText which can affect cursor)
            // Optimized for smooth typing - styling happens synchronously but efficiently
            applyStyling(to: textView)

            // CRITICAL: Restore cursor position after styling
            if cursorPosition.location <= (textView.text?.count ?? 0) {
                textView.selectedRange = cursorPosition
            }

            updatePlaceholder(textView: textView)
            parent.onEditingChanged?()
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            // Cancel any pending unfocus to prevent keyboard flicker
            focusDebounceTask?.cancel()
            focusDebounceTask = nil

            // Set focus immediately - no delay needed for begin editing
            parent.isFocused?.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            // Debounce unfocus to allow rapid focus transitions without keyboard flicker
            // This gives time for another field to grab focus before we set isFocused=false
            focusDebounceTask?.cancel()

            let task = DispatchWorkItem { [weak self] in
                self?.parent.isFocused?.wrappedValue = false
            }
            focusDebounceTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
        }
        
        // MARK: - Auto-continue List Items on Enter + Smart Cleanup on Backspace
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            let currentText = textView.text ?? ""
            let nsText = currentText as NSString
            let lineRange = nsText.lineRange(for: range)
            let lineWithNewline = nsText.substring(with: lineRange)
            let currentLine = lineWithNewline.trimmingCharacters(in: .newlines)

            // Smart backspace: remove empty list/todo markers as a unit.
            if text.isEmpty && range.length == 1 {
                let emptyPatterns = [
                    "^- \\[ \\]\\s*$",
                    "^- \\[x\\]\\s*$",
                    "^\\s*-\\s*$",
                    "^\\s*\\d+\\.\\s*$"
                ]

                let shouldDeleteLine = emptyPatterns.contains {
                    lineMatches(currentLine, pattern: $0, options: .caseInsensitive)
                }

                if shouldDeleteLine {
                    let newText = nsText.replacingCharacters(in: lineRange, with: "")
                    applyProgrammaticEdit(
                        newText,
                        in: textView,
                        cursorPosition: min(max(0, lineRange.location), newText.count)
                    )
                    return false
                }
            }

            // Check if Enter was pressed.
            guard text == "\n" else { return true }

            // Dismiss any date chips when user presses Enter (moving to next line).
            if let markdownTextView = textView as? MarkdownTextView {
                dismissAllDateChips(in: markdownTextView)
            }

            // Continue list formats only when pressing Enter at end of current line.
            let lineEndsWithNewline = lineWithNewline.hasSuffix("\n")
            let lineContentLength = lineRange.length - (lineEndsWithNewline ? 1 : 0)
            let lineContentEnd = lineRange.location + max(0, lineContentLength)
            guard range.location == lineContentEnd else { return true }

            // Todo continuation.
            if let todoMatch = firstMatch(
                in: currentLine,
                pattern: #"^(\s*)- \[( |x)\]\s*(.*)$"#,
                options: .caseInsensitive
            ) {
                let indent = capturedText(from: currentLine, match: todoMatch, at: 1)
                let todoContent = capturedText(from: currentLine, match: todoMatch, at: 3)
                let replacement = todoContent.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "\n\(indent)"
                    : "\n\(indent)- [ ] "
                let newText = nsText.replacingCharacters(in: range, with: replacement)
                applyProgrammaticEdit(newText, in: textView, cursorPosition: range.location + replacement.count)
                return false
            }

            // Bullet continuation.
            if let bulletMatch = firstMatch(in: currentLine, pattern: #"^(\s*)-\s+(.*)$"#) {
                let indent = capturedText(from: currentLine, match: bulletMatch, at: 1)
                let bulletContent = capturedText(from: currentLine, match: bulletMatch, at: 2)
                let replacement = bulletContent.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "\n\(indent)"
                    : "\n\(indent)- "
                let newText = nsText.replacingCharacters(in: range, with: replacement)
                applyProgrammaticEdit(newText, in: textView, cursorPosition: range.location + replacement.count)
                return false
            }

            // Numbered list continuation.
            if let numberedMatch = firstMatch(in: currentLine, pattern: #"^(\s*)(\d+)\.\s+(.*)$"#) {
                let indent = capturedText(from: currentLine, match: numberedMatch, at: 1)
                let listIndex = Int(capturedText(from: currentLine, match: numberedMatch, at: 2)) ?? 1
                let listContent = capturedText(from: currentLine, match: numberedMatch, at: 3)
                let replacement = listContent.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "\n\(indent)"
                    : "\n\(indent)\(listIndex + 1). "
                let newText = nsText.replacingCharacters(in: range, with: replacement)
                applyProgrammaticEdit(newText, in: textView, cursorPosition: range.location + replacement.count)
                return false
            }

            return true
        }

        private func applyProgrammaticEdit(_ newText: String, in textView: UITextView, cursorPosition: Int) {
            isInsertingTodo = true
            textView.text = newText
            parent.text = newText
            isInsertingTodo = false

            let safePosition = min(max(0, cursorPosition), newText.count)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            pendingCursorPosition = safePosition

            applyTextStylingOnly(to: textView)
            parent.onEditingChanged?()
            textView.invalidateIntrinsicContentSize()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak textView] in
                guard let self = self, let textView = textView else { return }
                self.addAllOverlays(to: textView, text: newText)
            }
        }

        private func firstMatch(in text: String, pattern: String, options: NSRegularExpression.Options = []) -> NSTextCheckingResult? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            return regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        }

        private func capturedText(from text: String, match: NSTextCheckingResult, at index: Int) -> String {
            guard match.numberOfRanges > index else { return "" }
            let nsText = text as NSString
            return nsText.substring(with: match.range(at: index))
        }

        private func lineMatches(_ text: String, pattern: String, options: NSRegularExpression.Options = []) -> Bool {
            firstMatch(in: text, pattern: pattern, options: options) != nil
        }
        
        func updatePlaceholder(textView: UITextView) {
            // Placeholder removed
        }
        
        // MARK: - Markdown Styling Engine
        func applyStyling(to textView: UITextView) {
            guard let text = textView.text else { return }
            // Clear any stale bullet overlays from previous render cycles.
            textView.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }
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
            
            // 3. Bold (**bold**) - Track ranges to avoid double-processing for italic
            var boldRanges: [NSRange] = []
            let boldRegex = try? NSRegularExpression(pattern: "(\\*\\*)(.+?)(\\*\\*)", options: [])
            boldRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let leadingSyntax = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let trailingSyntax = match.range(at: 3)
                
                // Track the full bold range including markers
                boldRanges.append(match.range(at: 0))
                
                // Hide Syntax
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: leadingSyntax)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: trailingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: leadingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: trailingSyntax)
                
                // Style Content
                attributedString.addAttribute(.font, value: parent.boldFont, range: contentRange)
            }
            
            // 4. Italic (*italic*) - Simple single asterisk pattern, skip if inside a bold range
            let italicRegex = try? NSRegularExpression(pattern: "(\\*)([^*]+)(\\*)", options: [])
            italicRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let matchFullRange = match.range(at: 0)
                
                // Skip if this range overlaps with any bold range
                let overlapsWithBold = boldRanges.contains { boldRange in
                    NSIntersectionRange(matchFullRange, boldRange).length > 0
                }
                if overlapsWithBold { return }
                
                let leadingSyntax = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let trailingSyntax = match.range(at: 3)
                
                // Hide Syntax
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: leadingSyntax)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: trailingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: leadingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: trailingSyntax)
                
                // Style Content with Italic
                attributedString.addAttribute(.font, value: parent.italicFont, range: contentRange)
            }
            
            // 5. Strikethrough (~~text~~)
            let strikeRegex = try? NSRegularExpression(pattern: "(~~)(.+?)(~~)", options: [])
            strikeRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let leadingSyntax = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let trailingSyntax = match.range(at: 3)
                
                // Hide Syntax
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: leadingSyntax)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: trailingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: leadingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: trailingSyntax)
                
                // Style Content with Strikethrough
                attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                attributedString.addAttribute(.strikethroughColor, value: UIColor.label, range: contentRange)
            }
            
            // 4. Todo Checkboxes - Unchecked: - [ ] or * [ ]
            // Add extra line spacing for todo lines
            // Add extra line spacing for todo lines and hanging indent
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = 8 // Space between todo items
            paragraphStyle.lineSpacing = 4
            paragraphStyle.headIndent = 28 // Hanging indent for wrapped lines (align with text)
            paragraphStyle.firstLineHeadIndent = 0 // First line starts at margin (checkbox position)

            
            let uncheckedRegex = try? NSRegularExpression(pattern: "^(- \\[ \\]|\\* \\[ \\])\\s*", options: .anchorsMatchLines)
            uncheckedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Hide the markdown syntax
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: match.range)
                
                // Apply paragraph spacing to the entire line
                let lineRange = (text as NSString).lineRange(for: match.range)
                attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }
            
            // 5. Todo Checkboxes - Checked: - [x] or * [x]
            let checkedRegex = try? NSRegularExpression(pattern: "^(- \\[x\\]|\\* \\[x\\])\\s*", options: [.anchorsMatchLines, .caseInsensitive])
            checkedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Hide the markdown syntax
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: match.range)
                
                // Apply paragraph spacing to the entire line
                let lineRange = (text as NSString).lineRange(for: match.range)
                attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }
            
            // 6. Bullet Lists (- text without checkbox brackets) - Show bullet character
            // Match "- " at start of line but NOT followed by [ (which would be a checkbox)
            let bulletRegex = try? NSRegularExpression(pattern: "^(- )(?!\\[)", options: .anchorsMatchLines)
            bulletRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Keep markdown marker visible to avoid overlay artifacts while typing.
                let lineRange = (text as NSString).lineRange(for: match.range)
                attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }
            
            // 7. Numbered Lists (1. text, 2. text, etc)
            let numberedRegex = try? NSRegularExpression(pattern: "^(\\d+\\.\\s)", options: .anchorsMatchLines)
            numberedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Keep the number visible but style it
                attributedString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: match.range)
                
                // Apply paragraph spacing
                let lineRange = (text as NSString).lineRange(for: match.range)
                attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
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

            // CRITICAL: Force layout update BEFORE adding overlays
            // This ensures glyph positions are correct for checkbox/bullet placement
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            textView.layoutIfNeeded()

            // Add visual checkbox overlays (after layout is complete)
            addCheckboxOverlays(in: textView, text: text)

            // Detect and highlight dates with calendar icon
            detectAndShowDateIcons(in: textView, text: text)
        }

        // MARK: - Text Styling Without Overlays (for deferred overlay placement)
        func applyTextStylingOnly(to textView: UITextView) {
            guard let text = textView.text else { return }
            // Clear any stale bullet overlays from previous render cycles.
            textView.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }
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

            // Bold (**bold**)
            var boldRanges: [NSRange] = []
            let boldRegex = try? NSRegularExpression(pattern: "(\\*\\*)(.+?)(\\*\\*)", options: [])
            boldRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let leadingSyntax = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let trailingSyntax = match.range(at: 3)
                boldRanges.append(match.range)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: leadingSyntax)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: trailingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: leadingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: trailingSyntax)
                attributedString.addAttribute(.font, value: parent.boldFont, range: contentRange)
            }

            // Italic (*italic*) - skip ranges already processed as bold
            let italicRegex = try? NSRegularExpression(pattern: "(\\*)([^*]+?)(\\*)", options: [])
            italicRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let isInsideBold = boldRanges.contains { NSIntersectionRange($0, match.range).length > 0 }
                if isInsideBold { return }
                let leadingSyntax = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let trailingSyntax = match.range(at: 3)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: leadingSyntax)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: trailingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: leadingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: trailingSyntax)
                attributedString.addAttribute(.font, value: parent.italicFont, range: contentRange)
            }

            // Strikethrough (~~text~~)
            let strikeRegex = try? NSRegularExpression(pattern: "(~~)(.+?)(~~)", options: [])
            strikeRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let leadingSyntax = match.range(at: 1)
                let contentRange = match.range(at: 2)
                let trailingSyntax = match.range(at: 3)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: leadingSyntax)
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: trailingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: leadingSyntax)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: trailingSyntax)
                attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
                attributedString.addAttribute(.strikethroughColor, value: UIColor.label, range: contentRange)
            }

            // Todo checkbox paragraph styling
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = 8
            paragraphStyle.lineSpacing = 4
            paragraphStyle.headIndent = 28
            paragraphStyle.firstLineHeadIndent = 0

            let uncheckedRegex = try? NSRegularExpression(pattern: "^(- \\[ \\]|\\* \\[ \\])\\s*", options: .anchorsMatchLines)
            uncheckedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: match.range)
                let lineRange = (text as NSString).lineRange(for: match.range)
                attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }

            let checkedRegex = try? NSRegularExpression(pattern: "^(- \\[x\\]|\\* \\[x\\])\\s*", options: [.anchorsMatchLines, .caseInsensitive])
            checkedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: match.range)
                let lineRange = (text as NSString).lineRange(for: match.range)
                attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }

            let bulletRegex = try? NSRegularExpression(pattern: "^(- )(?!\\[)", options: .anchorsMatchLines)
            bulletRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let lineRange = (text as NSString).lineRange(for: match.range)
                attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }

            let numberedRegex = try? NSRegularExpression(pattern: "^(\\d+\\.\\s)", options: .anchorsMatchLines)
            numberedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                attributedString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: match.range)
                let lineRange = (text as NSString).lineRange(for: match.range)
                attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: lineRange)
            }

            // Preserve Selection
            let savedSelection = textView.selectedRange
            let textLength = attributedString.length

            // Apply
            textView.attributedText = attributedString

            // Restore selection
            let safeLocation = min(savedSelection.location, textLength)
            let safeLength = min(savedSelection.length, textLength - safeLocation)
            textView.selectedRange = NSRange(location: safeLocation, length: safeLength)
        }

        // MARK: - Add All Overlays (deferred call after layout)
        func addAllOverlays(to textView: UITextView, text: String) {
            // Force layout before positioning overlays
            textView.layoutManager.ensureLayout(for: textView.textContainer)
            textView.setNeedsLayout()
            textView.layoutIfNeeded()

            // Add visual overlays
            addCheckboxOverlays(in: textView, text: text)
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
            // Use circular checkboxes with theme-appropriate colors
            let imageName = isChecked ? "checkmark.circle.fill" : "circle"
            // Use label color (white in dark mode, black in light mode) instead of green
            let imageColor = UIColor.label
            checkboxButton.setImage(UIImage(systemName: imageName)?.withTintColor(imageColor, renderingMode: .alwaysOriginal), for: .normal)
            
            // Center vertically relative to the line height
            // rect gives the glyph bounding box. We want to center 22x22 button in this height.
            let buttonSize: CGFloat = 22
            let centeredY = rect.midY - (buttonSize / 2) + textView.textContainerInset.top
            
            checkboxButton.frame = CGRect(x: rect.origin.x, y: centeredY, width: buttonSize, height: buttonSize)
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
        
        // MARK: - Bullet Point Overlays
        private func addBulletOverlays(in textView: UITextView, text: String) {
            // Remove existing bullet labels
            textView.subviews.filter { $0.tag == 999 }.forEach { $0.removeFromSuperview() }
            
            // Find bullet points: "- " not followed by [ (which would be a checkbox)
            let bulletPattern = "^- (?!\\[)"
            if let bulletRegex = try? NSRegularExpression(pattern: bulletPattern, options: .anchorsMatchLines) {
                let matches = bulletRegex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    addBulletLabel(in: textView, at: match.range)
                }
            }
        }
        
        private func addBulletLabel(in textView: UITextView, at range: NSRange) {
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            
            let bulletLabel = UILabel()
            bulletLabel.text = "•"
            bulletLabel.font = UIFont.systemFont(ofSize: 18, weight: .regular)
            bulletLabel.textColor = UIColor.label
            bulletLabel.textAlignment = .center
            
            // Position at the start of the line
            let labelSize: CGFloat = 20
            let centeredY = rect.midY - (labelSize / 2) + textView.textContainerInset.top
            
            bulletLabel.frame = CGRect(x: rect.origin.x, y: centeredY, width: labelSize, height: labelSize)
            bulletLabel.tag = 999 // Unique tag for bullet overlays
            
            textView.addSubview(bulletLabel)
        }
        
        // MARK: - Date Detection with Smart Chip/Pill Overlay
        private func detectAndShowDateIcons(in textView: UITextView, text: String) {
            // Remove existing date chips
            textView.subviews.filter { $0.tag == 888 }.forEach { $0.removeFromSuperview() }
            
            // Skip date highlighting for receipt notes
            if parent.isReceiptNote {
                return
            }
            
            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return }
            let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            
            guard !matches.isEmpty else { return }
            
            // Group matches by line to merge adjacent date+time detections
            var lineMatches: [String: [(match: NSTextCheckingResult, date: Date)]] = [:]
            
            for match in matches {
                guard let date = match.date,
                      date >= Calendar.current.startOfDay(for: Date()) else { continue }
                
                guard let textRange = Range(match.range, in: text) else { continue }
                
                // Get the matched text
                let matchedText = String(text[textRange]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Skip generic weekday names alone - they're too vague for event creation
                let weekdayOnlyPatterns = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                                           "mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                if weekdayOnlyPatterns.contains(matchedText) {
                    continue
                }
                
                // Also skip if it's just "today", "tomorrow", "next week" without a time
                let vaguePatterns = ["today", "tomorrow", "next week", "this week"]
                if vaguePatterns.contains(matchedText) {
                    continue
                }
                
                // Extract context (full line containing the date)
                let lineStart = text[..<textRange.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
                let lineEnd = text[textRange.upperBound...].firstIndex(of: "\n") ?? text.endIndex
                let fullLine = String(text[lineStart..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Group by line
                if lineMatches[fullLine] == nil {
                    lineMatches[fullLine] = []
                }
                lineMatches[fullLine]?.append((match: match, date: date))
            }
            
            // Create one chip per line, using the best date (prefer one with time info)
            for (fullLine, matchesOnLine) in lineMatches {
                // Skip if this context was already dismissed
                if dismissedContexts.contains(fullLine) { continue }
                
                guard let firstMatch = matchesOnLine.first else { continue }
                
                // Find the best date - prefer later matches as they often have time info
                // Or prefer the date that has a more specific time (not 12:00 PM noon)
                var bestMatch = firstMatch
                for matchInfo in matchesOnLine {
                    let calendar = Calendar.current
                    let hour = calendar.component(.hour, from: matchInfo.date)
                    let minute = calendar.component(.minute, from: matchInfo.date)
                    
                    // If this match has a non-noon time, prefer it
                    if hour != 12 || minute != 0 {
                        bestMatch = matchInfo
                        break
                    }
                    // Or if this is a later match (likely time portion), update the first match's date with this time
                    if matchInfo.match.range.location > firstMatch.match.range.location {
                        // Combine dates: use first match's date with this match's time
                        let firstComponents = calendar.dateComponents([.year, .month, .day], from: firstMatch.date)
                        let timeComponents = calendar.dateComponents([.hour, .minute], from: matchInfo.date)
                        
                        if let combinedDate = calendar.date(from: DateComponents(
                            year: firstComponents.year,
                            month: firstComponents.month,
                            day: firstComponents.day,
                            hour: timeComponents.hour,
                            minute: timeComponents.minute
                        )) {
                            bestMatch = (match: firstMatch.match, date: combinedDate)
                        }
                    }
                }
                
                // Get position for the chip (at the start of first match on line)
                let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: firstMatch.match.range, actualCharacterRange: nil)
                let rect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
                
                // Create the Smart Chip container
                let chipView = createDateChip(date: bestMatch.date, context: fullLine, rect: rect, textView: textView)
                chipView.tag = 888
                textView.addSubview(chipView)
            }
            
            // Also apply BLUE underline to the date text to indicate it's interactive (more noticeable)
            let attributedString = NSMutableAttributedString(attributedString: textView.attributedText)
            
            for match in matches {
                guard let date = match.date,
                      date >= Calendar.current.startOfDay(for: Date()) else { continue }
                
                guard let textRange = Range(match.range, in: text) else { continue }
                
                // Get the matched text and apply same filters as chip creation
                let matchedText = String(text[textRange]).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                let weekdayOnlyPatterns = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                                           "mon", "tue", "wed", "thu", "fri", "sat", "sun"]
                if weekdayOnlyPatterns.contains(matchedText) { continue }
                
                let vaguePatterns = ["today", "tomorrow", "next week", "this week"]
                if vaguePatterns.contains(matchedText) { continue }
                
                // Get the full line for context
                let lineStart = text[..<textRange.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
                let lineEnd = text[textRange.upperBound...].firstIndex(of: "\n") ?? text.endIndex
                let fullLine = String(text[lineStart..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Add BLUE underline and color to make dates noticeable
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
                attributedString.addAttribute(.underlineColor, value: UIColor.systemBlue, range: match.range)
                attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: match.range)
                
                // Add a tappable link to toggle chip visibility
                let toggleURL = URL(string: "datetoggle://\(date.timeIntervalSince1970)?\(fullLine.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
                attributedString.addAttribute(.link, value: toggleURL, range: match.range)
            }
            
            // Apply with saved selection
            let savedSelection = textView.selectedRange
            textView.attributedText = attributedString
            textView.selectedRange = savedSelection
        }
        
        private func createDateChip(date: Date, context: String, rect: CGRect, textView: UITextView) -> UIView {
            // Format the date nicely
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            let dateString = formatter.string(from: date)
            
            // Create container view with pill shape - NEUTRAL COLORS
            let chipContainer = UIView()
            chipContainer.backgroundColor = UIColor.systemGray6
            chipContainer.layer.cornerRadius = 16
            chipContainer.layer.borderWidth = 1
            chipContainer.layer.borderColor = UIColor.systemGray3.cgColor
            chipContainer.clipsToBounds = false // Allow X button to be visible outside bounds
            
            // Stack for horizontal layout
            let stackView = UIStackView()
            stackView.axis = .horizontal
            stackView.spacing = 6
            stackView.alignment = .center
            stackView.translatesAutoresizingMaskIntoConstraints = false
            chipContainer.addSubview(stackView)
            
            // Calendar icon - neutral color
            let calendarIcon = UIImageView(image: UIImage(systemName: "calendar"))
            calendarIcon.tintColor = UIColor.systemBlue
            calendarIcon.contentMode = .scaleAspectFit
            calendarIcon.translatesAutoresizingMaskIntoConstraints = false
            calendarIcon.widthAnchor.constraint(equalToConstant: 16).isActive = true
            calendarIcon.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stackView.addArrangedSubview(calendarIcon)
            
            // Date label
            let dateLabel = UILabel()
            dateLabel.text = dateString
            dateLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            dateLabel.textColor = UIColor.label
            stackView.addArrangedSubview(dateLabel)
            
            // Separator
            let separator = UIView()
            separator.backgroundColor = UIColor.systemGray3
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
            separator.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stackView.addArrangedSubview(separator)
            
            // "+ Add" button
            let addButton = UIButton(type: .system)
            addButton.setTitle("+ Add", for: .normal)
            addButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            addButton.setTitleColor(UIColor.systemBlue, for: .normal)
            addButton.accessibilityLabel = "\(date.timeIntervalSince1970)|\(context)"
            addButton.addTarget(self, action: #selector(dateChipTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(addButton)
            
            // Second separator before X
            let separator2 = UIView()
            separator2.backgroundColor = UIColor.systemGray3
            separator2.translatesAutoresizingMaskIntoConstraints = false
            separator2.widthAnchor.constraint(equalToConstant: 1).isActive = true
            separator2.heightAnchor.constraint(equalToConstant: 16).isActive = true
            stackView.addArrangedSubview(separator2)
            
            // Dismiss X button - inside the stack
            let dismissButton = UIButton(type: .system)
            dismissButton.setImage(UIImage(systemName: "xmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)), for: .normal)
            dismissButton.tintColor = UIColor.systemGray
            dismissButton.addTarget(self, action: #selector(dismissChipTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(dismissButton)
            
            // Layout constraints for stack
            NSLayoutConstraint.activate([
                stackView.leadingAnchor.constraint(equalTo: chipContainer.leadingAnchor, constant: 10),
                stackView.trailingAnchor.constraint(equalTo: chipContainer.trailingAnchor, constant: -8),
                stackView.topAnchor.constraint(equalTo: chipContainer.topAnchor, constant: 6),
                stackView.bottomAnchor.constraint(equalTo: chipContainer.bottomAnchor, constant: -6)
            ])
            
            // Size the container
            let chipSize = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            let chipWidth = chipSize.width + 18
            let chipHeight: CGFloat = 32
            
            // Position below the detected date line
            chipContainer.frame = CGRect(
                x: rect.origin.x,
                y: rect.origin.y + rect.height + textView.textContainerInset.top + 4,
                width: chipWidth,
                height: chipHeight
            )
            
            // Add tap gesture to entire chip (for + Add action)
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(chipContainerTapped(_:)))
            chipContainer.addGestureRecognizer(tapGesture)
            chipContainer.isUserInteractionEnabled = true
            chipContainer.accessibilityLabel = "\(date.timeIntervalSince1970)|\(context)"
            
            // Add SUBTLE GLOW effect
            chipContainer.layer.shadowColor = UIColor.white.cgColor
            chipContainer.layer.shadowOpacity = 0.6
            chipContainer.layer.shadowOffset = CGSize(width: 0, height: 0)
            chipContainer.layer.shadowRadius = 8
            
            return chipContainer
        }
        
        @objc private func dismissChipTapped(_ sender: UIButton) {
            // The button is inside stackView, which is inside chipContainer
            // So we need to go up two levels: button -> stackView -> chipContainer
            guard let stackView = sender.superview,
                  let chipContainer = stackView.superview else { return }
            
            // Record dismissal
            if let label = chipContainer.accessibilityLabel {
                let parts = label.components(separatedBy: "|")
                if parts.count >= 2 {
                    let context = parts.dropFirst().joined(separator: "|")
                    dismissedContexts.insert(context)
                }
            }
            
            // Remove with animation
            UIView.animate(withDuration: 0.2, animations: {
                chipContainer.alpha = 0
                chipContainer.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            }) { _ in
                chipContainer.removeFromSuperview()
            }
        }
        
        /// Dismiss all date chips from the text view
        private func dismissAllDateChips(in textView: UITextView) {
            textView.subviews.filter { $0.tag == 888 }.forEach { chip in
                UIView.animate(withDuration: 0.15, animations: {
                    chip.alpha = 0
                }) { _ in
                    chip.removeFromSuperview()
                }
            }
        }
        
        @objc private func dateChipTapped(_ sender: UIButton) {
            handleDateChipInteraction(accessibilityLabel: sender.accessibilityLabel)
        }
        
        @objc private func chipContainerTapped(_ gesture: UITapGestureRecognizer) {
            handleDateChipInteraction(accessibilityLabel: gesture.view?.accessibilityLabel)
        }
        
        private func handleDateChipInteraction(accessibilityLabel: String?) {
            guard let info = accessibilityLabel else { return }
            let parts = info.components(separatedBy: "|")
            if parts.count >= 2, let timestamp = Double(parts[0]) {
                let date = Date(timeIntervalSince1970: timestamp)
                let context = parts.dropFirst().joined(separator: "|") // Rejoin in case context had pipes
                
                // Directly call the callback - no need for confirmation since the button is clear
                DispatchQueue.main.async {
                    self.parent.onDateDetected?(date, context)
                }
            }
        }
        
        // Handle taps on date links (backup for old implementation)
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            // Handle date toggle (tapping on blue date text)
            if URL.scheme == "datetoggle" {
                guard let host = URL.host,
                      let timestamp = Double(host) else { return false }
                
                let date = Date(timeIntervalSince1970: timestamp)
                let context = URL.query?.removingPercentEncoding ?? ""
                
                // Check if chip for this line is already visible
                let existingChips = textView.subviews.filter { $0.tag == 888 }
                var chipWasVisible = false
                
                for chip in existingChips {
                    // Check if this chip matches the tapped date (by checking accessibility label)
                    if let label = chip.accessibilityLabel, label.contains(host) {
                        // Chip is visible - dismiss it
                        UIView.animate(withDuration: 0.2, animations: {
                            chip.alpha = 0
                            chip.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                        }) { _ in
                            chip.removeFromSuperview()
                        }
                        chipWasVisible = true
                        
                        // Add to dismissed contexts
                        dismissedContexts.insert(context)
                    }
                }
                
                // If no chip was visible, trigger event creation
                if !chipWasVisible {
                    DispatchQueue.main.async {
                        self.parent.onDateDetected?(date, context)
                    }
                }
                
                return false
            }
            
            // Legacy datelink handler (from older implementation)
            if URL.scheme == "datelink", let host = URL.host?.removingPercentEncoding {
                let parts = host.components(separatedBy: "|")
                if parts.count >= 2, let timestamp = Double(parts[0]) {
                    let date = Date(timeIntervalSince1970: timestamp)
                    let context = parts[1]
                    
                    DispatchQueue.main.async {
                        self.parent.onDateDetected?(date, context)
                    }
                }
                return false
            }
            return true
        }
    }
}

enum NoteFormattingAction: String {
    case bold
    case italic
    case strikethrough
    case heading1
    case heading2
    case heading3
    case body
    case bulletPoint
    case numberedList
}

extension Notification.Name {
    static let noteFormattingAction = Notification.Name("noteFormattingAction")
}

// MARK: - Custom TextView to intercept Menu Commands
class MarkdownTextView: UITextView {
    
    private var formattingObserver: NSObjectProtocol?
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupMenuItems()
        setupFormattingObserver()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMenuItems()
        setupFormattingObserver()
    }
    
    deinit {
        if let observer = formattingObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
    
    private func setupFormattingObserver() {
        formattingObserver = NotificationCenter.default.addObserver(
            forName: .noteFormattingAction,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard self.isFirstResponder else { return }
            guard let actionRaw = notification.userInfo?["action"] as? String,
                  let action = NoteFormattingAction(rawValue: actionRaw) else { return }
            self.applyFormattingAction(action)
        }
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

    @objc func makeBody() {
        removeHeadingFromSelection()
    }
    
    private func wrapLineWithHeading(_ prefix: String) {
        guard let text = self.text else { return }
        let nsString = text as NSString
        let range = self.selectedRange
        
        // Get the line range at cursor/selection
        let lineRange: NSRange
        if range.length > 0 {
            lineRange = range
        } else {
            // No selection - get the current line
            lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        }
        
        let lineText = nsString.substring(with: lineRange)
        
        // Remove existing heading prefix if any
        var cleanText = lineText.trimmingCharacters(in: .newlines)
        if cleanText.hasPrefix("### ") {
            cleanText = String(cleanText.dropFirst(4))
        } else if cleanText.hasPrefix("## ") {
            cleanText = String(cleanText.dropFirst(3))
        } else if cleanText.hasPrefix("# ") {
            cleanText = String(cleanText.dropFirst(2))
        }
        
        // Add trailing newline back if original had it
        let newText = "\(prefix)\(cleanText)" + (lineText.hasSuffix("\n") ? "\n" : "")
        
        if let textRange = self.textRange(from: self.position(from: beginningOfDocument, offset: lineRange.location)!,
                                          to: self.position(from: beginningOfDocument, offset: lineRange.location + lineRange.length)!) {
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
           action == #selector(makeH3) ||
           action == #selector(makeBody) {
            return selectedRange.length > 0
        }
        return super.canPerformAction(action, withSender: sender)
    }

    private func applyFormattingAction(_ action: NoteFormattingAction) {
        switch action {
        case .bold:
            guard selectedRange.length > 0 else { return }
            wrapSelection(with: "**")
        case .italic:
            guard selectedRange.length > 0 else { return }
            wrapSelection(with: "*")
        case .strikethrough:
            guard selectedRange.length > 0 else { return }
            wrapSelection(with: "~~")
        case .heading1:
            // Headings work on current line even without selection
            wrapLineWithHeading("# ")
        case .heading2:
            wrapLineWithHeading("## ")
        case .heading3:
            wrapLineWithHeading("### ")
        case .body:
            // Body also works on current line
            removeHeadingFromSelection()
        case .bulletPoint:
            insertListPrefix("- ")
        case .numberedList:
            insertListPrefix("1. ")
        }
    }
    
    private func insertListPrefix(_ prefix: String) {
        guard let text = self.text else { return }
        let nsString = text as NSString
        let range = self.selectedRange

        // Get the current line at cursor.
        let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let hasTrailingNewline = lineText.hasSuffix("\n")
        let lineCore = hasTrailingNewline ? String(lineText.dropLast()) : lineText

        // Preserve existing indentation.
        let indentation = String(lineCore.prefix { $0 == " " || $0 == "\t" })
        let lineWithoutIndent = String(lineCore.dropFirst(indentation.count))

        let hasBulletPrefix = lineWithoutIndent.hasPrefix("- ")
        let numberedPattern = "^\\d+\\.\\s"
        let hasNumberedPrefix = (try? NSRegularExpression(pattern: numberedPattern, options: []))?
            .firstMatch(
                in: lineWithoutIndent,
                options: [],
                range: NSRange(location: 0, length: lineWithoutIndent.utf16.count)
            ) != nil

        let isSamePrefixType = (prefix == "- " && hasBulletPrefix) || (prefix == "1. " && hasNumberedPrefix)

        var contentWithoutPrefix = lineWithoutIndent
        if hasBulletPrefix {
            contentWithoutPrefix = String(lineWithoutIndent.dropFirst(2))
        } else if hasNumberedPrefix,
                  let regex = try? NSRegularExpression(pattern: numberedPattern, options: []),
                  let match = regex.firstMatch(
                    in: lineWithoutIndent,
                    options: [],
                    range: NSRange(location: 0, length: lineWithoutIndent.utf16.count)
                  ),
                  let matchRange = Range(match.range, in: lineWithoutIndent) {
            contentWithoutPrefix = String(lineWithoutIndent[matchRange.upperBound...])
        }

        let updatedLineCore: String
        let newCursorOffsetInLine: Int
        if isSamePrefixType {
            // Toggle off if user taps the same list style again.
            updatedLineCore = indentation + contentWithoutPrefix
            newCursorOffsetInLine = min(max(0, range.location - lineRange.location), updatedLineCore.count)
        } else {
            // Add or switch list style while keeping indentation.
            updatedLineCore = indentation + prefix + contentWithoutPrefix
            newCursorOffsetInLine = min(updatedLineCore.count, indentation.count + prefix.count)
        }

        let replacementText = hasTrailingNewline ? updatedLineCore + "\n" : updatedLineCore
        if let textRange = self.textRange(
            from: self.position(from: beginningOfDocument, offset: lineRange.location)!,
            to: self.position(from: beginningOfDocument, offset: lineRange.location + lineRange.length)!
        ) {
            self.replace(textRange, withText: replacementText)

            // Keep cursor near the line start content to prevent jumpy behavior.
            let maxCursor = (self.text ?? "").utf16.count
            let cursorLocation = min(maxCursor, lineRange.location + newCursorOffsetInLine)
            self.selectedRange = NSRange(location: cursorLocation, length: 0)
        }
    }

    private func removeHeadingFromSelection() {
        guard let text = self.text else { return }
        let nsString = text as NSString
        let range = self.selectedRange
        
        // Get the line range at cursor/selection
        let lineRange: NSRange
        if range.length > 0 {
            lineRange = range
        } else {
            // No selection - get the current line
            lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        }
        
        let selectedText = nsString.substring(with: lineRange)
        let lines = selectedText
            .components(separatedBy: "\n")
            .map { line -> String in
                if line.hasPrefix("### ") {
                    return String(line.dropFirst(4))
                }
                if line.hasPrefix("## ") {
                    return String(line.dropFirst(3))
                }
                if line.hasPrefix("# ") {
                    return String(line.dropFirst(2))
                }
                return line
            }
        
        let newText = lines.joined(separator: "\n")
        
        if let textRange = self.textRange(from: self.position(from: beginningOfDocument, offset: lineRange.location)!,
                                          to: self.position(from: beginningOfDocument, offset: lineRange.location + lineRange.length)!) {
            self.replace(textRange, withText: newText)
        }
    }
}
