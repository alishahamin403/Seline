import SwiftUI
import UIKit

private struct TodoLineMatch {
    let lineRange: NSRange
    let markerRange: NSRange
    let hiddenMarkerRange: NSRange
    let contentRange: NSRange
    let isChecked: Bool
}

private final class TodoCheckboxButton: UIButton {
    var lineStartLocation: Int = 0
    var isCheckedState: Bool = false
}

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
    private let boldItalicFont: UIFont = {
        let baseFont = UIFont.systemFont(ofSize: 15, weight: .regular)
        if let descriptor = baseFont.fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
            return UIFont(descriptor: descriptor, size: 15)
        }
        return UIFont.boldSystemFont(ofSize: 15)
    }()
    
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
        textView.onBoundsSizeChange = { [weak textView] _ in
            guard let textView else { return }
            context.coordinator.addAllOverlays(to: textView, text: textView.text ?? "")
        }

        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            context.coordinator.addAllOverlays(to: textView, text: textView.text ?? "")
        }

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
        let textDidChange = currentText != text
        if textDidChange {
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

        if !textDidChange {
            DispatchQueue.main.async { [weak uiView] in
                guard let uiView else { return }
                context.coordinator.addAllOverlays(to: uiView, text: uiView.text ?? text)
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
        private var overlayRefreshTask: DispatchWorkItem? // Debounce heavy overlay/date rendering while typing
        private let todoLineRegex = try! NSRegularExpression(
            pattern: #"^(\s*)([-*])\s\[( |x|X)\]"#,
            options: .anchorsMatchLines
        )
        var isInsertingTodo = false // Flag to prevent duplicate overlay updates during todo insertion
        private lazy var todoParagraphStyle: NSParagraphStyle = {
            let paragraphStyle = NSMutableParagraphStyle()
            let minimumLineHeight = max(parent.bodyFont.lineHeight + 8, 28)
            let markerWidth = ("- [ ] " as NSString).size(withAttributes: [.font: parent.bodyFont]).width

            paragraphStyle.minimumLineHeight = minimumLineHeight
            paragraphStyle.maximumLineHeight = minimumLineHeight
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.headIndent = markerWidth
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.paragraphSpacing = 4

            return paragraphStyle
        }()

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

            // Keep keystroke path lightweight for smoother typing.
            // Heavy overlays/date chips are applied on a short debounce.
            applyTextStylingOnly(to: textView)

            // CRITICAL: Restore cursor position after styling
            if cursorPosition.location <= (textView.text?.count ?? 0) {
                textView.selectedRange = cursorPosition
            }

            updatePlaceholder(textView: textView)
            parent.onEditingChanged?()
            textView.invalidateIntrinsicContentSize()
            scheduleOverlayRefresh(for: textView, expectedText: currentText)
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
            overlayRefreshTask?.cancel()

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
                    "^\\s*[-*] \\[ \\]\\s*$",
                    "^\\s*[-*] \\[x\\]\\s*$",
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
                pattern: #"^(\s*)([-*]) \[( |x)\]\s*(.*)$"#,
                options: .caseInsensitive
            ) {
                let indent = capturedText(from: currentLine, match: todoMatch, at: 1)
                let marker = capturedText(from: currentLine, match: todoMatch, at: 2)
                let todoContent = capturedText(from: currentLine, match: todoMatch, at: 4)
                let replacement = todoContent.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "\n\(indent)"
                    : "\n\(indent)\(marker) [ ] "
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
            scheduleOverlayRefresh(for: textView, expectedText: newText)
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

        private func parseTodoLineMatches(in text: String) -> [TodoLineMatch] {
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let matches = todoLineRegex.matches(in: text, options: [], range: fullRange)

            return matches.compactMap { match in
                guard match.numberOfRanges >= 4 else { return nil }

                let fullMatchRange = match.range(at: 0)
                let markerStartRange = match.range(at: 2)
                let stateRange = match.range(at: 3)

                guard fullMatchRange.location != NSNotFound,
                      markerStartRange.location != NSNotFound,
                      stateRange.location != NSNotFound else {
                    return nil
                }

                let markerRange = NSRange(location: markerStartRange.location, length: 5) // "- [ ]" or "* [x]"
                guard NSMaxRange(markerRange) <= nsText.length else { return nil }

                let lineRange = nsText.lineRange(for: fullMatchRange)
                var hiddenMarkerRange = markerRange
                let trailingSpaceLocation = NSMaxRange(markerRange)
                if trailingSpaceLocation < nsText.length, nsText.character(at: trailingSpaceLocation) == 32 {
                    hiddenMarkerRange.length += 1
                }

                var contentEnd = NSMaxRange(lineRange)
                if contentEnd > lineRange.location, nsText.character(at: contentEnd - 1) == 10 {
                    contentEnd -= 1
                }

                let contentStart = min(max(NSMaxRange(hiddenMarkerRange), lineRange.location), contentEnd)
                let contentRange = NSRange(location: contentStart, length: max(0, contentEnd - contentStart))

                let stateText = nsText.substring(with: stateRange).lowercased()
                return TodoLineMatch(
                    lineRange: lineRange,
                    markerRange: markerRange,
                    hiddenMarkerRange: hiddenMarkerRange,
                    contentRange: contentRange,
                    isChecked: stateText == "x"
                )
            }
        }

        private func applyTodoMarkerStyling(to attributedString: NSMutableAttributedString, text: String) {
            for todo in parseTodoLineMatches(in: text) {
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: todo.hiddenMarkerRange)
                attributedString.addAttribute(.paragraphStyle, value: todoParagraphStyle, range: todo.lineRange)
            }
        }

        private func checkboxFrame(for todo: TodoLineMatch, in textView: UITextView) -> CGRect? {
            let textLength = (textView.text as NSString?)?.length ?? 0
            guard textLength > 0 else { return nil }

            let markerLocation = min(todo.markerRange.location, max(0, textLength - 1))
            guard markerLocation >= 0, markerLocation < textLength else { return nil }

            let characterRange = NSRange(location: markerLocation, length: 1)
            let glyphRange = textView.layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return nil }

            let glyphRect = textView.layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer)
            let lineFragmentRect = textView.layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let contentLocation = firstVisibleTodoCharacterLocation(in: todo, textView: textView) ?? markerLocation
            let metricsGlyphRange = textView.layoutManager.glyphRange(
                forCharacterRange: NSRange(location: contentLocation, length: 1),
                actualCharacterRange: nil
            )

            let baselineOffset = metricsGlyphRange.length > 0
                ? textView.layoutManager.location(forGlyphAt: metricsGlyphRange.location).y
                : textView.layoutManager.location(forGlyphAt: glyphRange.location).y

            let lineFont = todoLineFont(for: todo, in: textView)
            let contentMidY = lineFragmentRect.minY + baselineOffset - ((lineFont.ascender + lineFont.descender) / 2)

            let buttonSize: CGFloat = 20
            let x = glyphRect.minX + textView.textContainerInset.left
            let y = contentMidY - (buttonSize / 2) + textView.textContainerInset.top
            return CGRect(x: x, y: y, width: buttonSize, height: buttonSize)
        }

        private func firstVisibleTodoCharacterLocation(in todo: TodoLineMatch, textView: UITextView) -> Int? {
            guard todo.contentRange.length > 0,
                  let attributedText = textView.attributedText else {
                return nil
            }

            let nsString = attributedText.string as NSString
            let contentEnd = NSMaxRange(todo.contentRange)
            guard todo.contentRange.location < contentEnd, contentEnd <= nsString.length else {
                return nil
            }

            var location = todo.contentRange.location
            while location < contentEnd {
                let scalar = nsString.character(at: location)
                if let unicodeScalar = UnicodeScalar(scalar),
                   !CharacterSet.whitespacesAndNewlines.contains(unicodeScalar) {
                    return location
                }
                location += 1
            }

            return nil
        }

        private func todoLineFont(for todo: TodoLineMatch, in textView: UITextView) -> UIFont {
            guard let attributedText = textView.attributedText else {
                return parent.bodyFont
            }

            let contentLocation = firstVisibleTodoCharacterLocation(in: todo, textView: textView)
                ?? min(todo.contentRange.location, max(0, attributedText.length - 1))

            guard contentLocation >= 0,
                  contentLocation < attributedText.length else {
                return parent.bodyFont
            }

            return (attributedText.attribute(.font, at: contentLocation, effectiveRange: nil) as? UIFont)
                ?? parent.bodyFont
        }

        private func configureCheckboxButton(_ button: TodoCheckboxButton, isChecked: Bool) {
            guard button.isCheckedState != isChecked || button.currentImage == nil else { return }
            button.isCheckedState = isChecked

            let imageName = isChecked ? "checkmark.circle.fill" : "circle"
            let imageColor = UIColor.label
            let image = UIImage(systemName: imageName)?
                .withTintColor(imageColor, renderingMode: .alwaysOriginal)
            button.setImage(image, for: .normal)
        }

        private func toggleTodoState(in text: String, lineStart: Int, toChecked checked: Bool) -> String? {
            let nsText = text as NSString
            guard nsText.length > 0 else { return nil }

            let safeLineStart = min(max(0, lineStart), max(0, nsText.length - 1))
            let rawLineRange = nsText.lineRange(for: NSRange(location: safeLineStart, length: 0))
            var lineRange = rawLineRange

            let lineEnd = NSMaxRange(lineRange)
            if lineRange.length > 0, lineEnd > 0, nsText.character(at: lineEnd - 1) == 10 {
                lineRange.length -= 1
            }

            let lineText = nsText.substring(with: lineRange)
            let lineNSString = lineText as NSString
            let fullLineRange = NSRange(location: 0, length: lineNSString.length)

            guard let match = todoLineRegex.firstMatch(in: lineText, options: [], range: fullLineRange),
                  match.numberOfRanges >= 3 else {
                return nil
            }

            let indent = lineNSString.substring(with: match.range(at: 1))
            let marker = lineNSString.substring(with: match.range(at: 2))
            let replacementPrefix = "\(indent)\(marker) [\(checked ? "x" : " ")]"
            let updatedLineText = lineNSString.replacingCharacters(in: match.range(at: 0), with: replacementPrefix)

            return nsText.replacingCharacters(in: lineRange, with: updatedLineText)
        }

        private func hideResidualMarkdownMarkers(in attributedString: NSMutableAttributedString, text: String) {
            let markerConfigs: [(pattern: String, tokenGroup: Int)] = [
                // Opening inline markers near word starts.
                (#"(^|\s)(\*\*|\*|~~)(?=\S)"#, 2),
                // Closing inline markers near word ends.
                (#"(?<=\S)(\*\*|\*|~~)(?=\s|$)"#, 1)
            ]

            for config in markerConfigs {
                guard let regex = try? NSRegularExpression(pattern: config.pattern, options: [.anchorsMatchLines]) else {
                    continue
                }

                let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
                for match in matches {
                    guard match.numberOfRanges > config.tokenGroup else { continue }
                    let tokenRange = match.range(at: config.tokenGroup)
                    guard tokenRange.location != NSNotFound, tokenRange.length > 0 else { continue }
                    attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: tokenRange)
                    attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: tokenRange)
                }
            }
        }

        private func scheduleOverlayRefresh(for textView: UITextView, expectedText: String) {
            overlayRefreshTask?.cancel()

            let task = DispatchWorkItem { [weak self, weak textView] in
                guard let self = self, let textView = textView else { return }
                guard (textView.text ?? "") == expectedText else { return }
                self.addAllOverlays(to: textView, text: expectedText)
            }

            overlayRefreshTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: task)
        }
        
        func updatePlaceholder(textView: UITextView) {
            // Placeholder removed
        }

        private func hideMarkdownSyntax(
            in attributedString: NSMutableAttributedString,
            ranges: [NSRange]
        ) {
            for range in ranges where range.location != NSNotFound && range.length > 0 {
                attributedString.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
                attributedString.addAttribute(.font, value: UIFont.systemFont(ofSize: 1), range: range)
            }
        }

        private func overlapsProcessedRanges(_ range: NSRange, processedRanges: [NSRange]) -> Bool {
            processedRanges.contains { NSIntersectionRange($0, range).length > 0 }
        }

        private func applyInlineMarkdownFormatting(
            to attributedString: NSMutableAttributedString,
            text: String,
            fullRange: NSRange
        ) {
            var processedEmphasisRanges: [NSRange] = []

            let boldItalicRegex = try? NSRegularExpression(
                pattern: #"(?<!\*)(\*\*\*)([^*\n]+?)(\*\*\*)(?!\*)"#,
                options: []
            )
            boldItalicRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let fullMatchRange = match.range(at: 0)
                guard !self.overlapsProcessedRanges(fullMatchRange, processedRanges: processedEmphasisRanges) else { return }

                processedEmphasisRanges.append(fullMatchRange)
                self.hideMarkdownSyntax(
                    in: attributedString,
                    ranges: [match.range(at: 1), match.range(at: 3)]
                )
                attributedString.addAttribute(.font, value: self.parent.boldItalicFont, range: match.range(at: 2))
            }

            let boldRegex = try? NSRegularExpression(
                pattern: #"(?<!\*)(\*\*)(?!\*)([^*\n]+?)(?<!\*)(\*\*)(?!\*)"#,
                options: []
            )
            boldRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let fullMatchRange = match.range(at: 0)
                guard !self.overlapsProcessedRanges(fullMatchRange, processedRanges: processedEmphasisRanges) else { return }

                processedEmphasisRanges.append(fullMatchRange)
                self.hideMarkdownSyntax(
                    in: attributedString,
                    ranges: [match.range(at: 1), match.range(at: 3)]
                )
                attributedString.addAttribute(.font, value: self.parent.boldFont, range: match.range(at: 2))
            }

            let italicRegex = try? NSRegularExpression(
                pattern: #"(?<!\*)(\*)([^*\n]+?)(\*)(?!\*)"#,
                options: []
            )
            italicRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                let fullMatchRange = match.range(at: 0)
                guard !self.overlapsProcessedRanges(fullMatchRange, processedRanges: processedEmphasisRanges) else { return }

                processedEmphasisRanges.append(fullMatchRange)
                self.hideMarkdownSyntax(
                    in: attributedString,
                    ranges: [match.range(at: 1), match.range(at: 3)]
                )
                attributedString.addAttribute(.font, value: self.parent.italicFont, range: match.range(at: 2))
            }

            let strikeRegex = try? NSRegularExpression(pattern: #"(~~)(.+?)(~~)"#, options: [])
            strikeRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                self.hideMarkdownSyntax(
                    in: attributedString,
                    ranges: [match.range(at: 1), match.range(at: 3)]
                )
                attributedString.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: match.range(at: 2)
                )
                attributedString.addAttribute(
                    .strikethroughColor,
                    value: UIColor.label,
                    range: match.range(at: 2)
                )
            }
        }
        
        // MARK: - Markdown Styling Engine
        func applyStyling(to textView: UITextView) {
            guard let text = textView.text else { return }
            // Clear all transient overlays before rebuilding styles.
            textView.subviews
                .filter { $0.tag == 777 || $0.tag == 888 }
                .forEach { $0.removeFromSuperview() }
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

            applyInlineMarkdownFormatting(to: attributedString, text: text, fullRange: fullRange)
            
            // 6. Todos
            applyTodoMarkerStyling(to: attributedString, text: text)
            
            // 7. Numbered Lists (1. text, 2. text, etc)
            let numberedRegex = try? NSRegularExpression(pattern: "^(\\d+\\.\\s)", options: .anchorsMatchLines)
            numberedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                // Keep the number visible but style it
                attributedString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: match.range)
            }

            // Defensive cleanup for malformed/legacy marker stacks.
            hideResidualMarkdownMarkers(in: attributedString, text: text)

            
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

            // Keep date mentions as plain text across notes/journal.
            detectAndShowDateIcons(in: textView, text: text)
        }

        // MARK: - Text Styling Without Overlays (for deferred overlay placement)
        func applyTextStylingOnly(to textView: UITextView) {
            guard let text = textView.text else { return }
            // Keep checklist checkboxes stable while typing.
            // Removing/re-adding checkbox overlays on each keystroke causes visible flicker.
            // Clear any legacy date chips as content shifts.
            textView.subviews
                .filter { $0.tag == 888 }
                .forEach { $0.removeFromSuperview() }
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

            applyInlineMarkdownFormatting(to: attributedString, text: text, fullRange: fullRange)

            applyTodoMarkerStyling(to: attributedString, text: text)

            let numberedRegex = try? NSRegularExpression(pattern: "^(\\d+\\.\\s)", options: .anchorsMatchLines)
            numberedRegex?.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
                guard let match = match else { return }
                attributedString.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: match.range)
            }

            // Defensive cleanup for malformed/legacy marker stacks.
            hideResidualMarkdownMarkers(in: attributedString, text: text)

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
            let todoMatches = parseTodoLineMatches(in: text)
            let existingButtons = textView.subviews.compactMap { $0 as? TodoCheckboxButton }
            var buttonsByLineStart: [Int: TodoCheckboxButton] = [:]
            for button in existingButtons {
                buttonsByLineStart[button.lineStartLocation] = button
            }

            var activeLineStarts = Set<Int>()

            for todo in todoMatches {
                let lineStart = todo.lineRange.location
                activeLineStarts.insert(lineStart)

                let checkboxButton: TodoCheckboxButton
                if let existing = buttonsByLineStart[lineStart] {
                    checkboxButton = existing
                } else {
                    checkboxButton = TodoCheckboxButton(type: .system)
                    checkboxButton.tag = 777
                    checkboxButton.addTarget(self, action: #selector(checkboxTapped(_:)), for: .touchUpInside)
                    textView.addSubview(checkboxButton)
                }

                checkboxButton.lineStartLocation = lineStart
                configureCheckboxButton(checkboxButton, isChecked: todo.isChecked)
                if let frame = checkboxFrame(for: todo, in: textView) {
                    checkboxButton.frame = frame
                    checkboxButton.isHidden = false
                } else {
                    checkboxButton.isHidden = true
                }
            }

            for button in existingButtons where !activeLineStarts.contains(button.lineStartLocation) {
                button.removeFromSuperview()
            }
        }
        
        @objc private func checkboxTapped(_ sender: UIButton) {
            guard let checkboxButton = sender as? TodoCheckboxButton,
                  let textView = checkboxButton.superview as? UITextView else {
                return
            }

            let currentText = textView.text ?? parent.text
            let targetCheckedState = !checkboxButton.isCheckedState
            guard let updatedText = toggleTodoState(
                in: currentText,
                lineStart: checkboxButton.lineStartLocation,
                toChecked: targetCheckedState
            ) else {
                return
            }

            let cursorLocation = min(textView.selectedRange.location, updatedText.count)
            applyProgrammaticEdit(updatedText, in: textView, cursorPosition: cursorLocation)
        }
        
        // MARK: - Date Mentions
        private func detectAndShowDateIcons(in textView: UITextView, text _: String) {
            dismissAllDateChips(in: textView)
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
    case checklist
    case bulletPoint
    case numberedList
}

extension Notification.Name {
    static let noteFormattingAction = Notification.Name("noteFormattingAction")
}

// MARK: - Custom TextView to intercept Menu Commands
class MarkdownTextView: UITextView {
    
    private var formattingObserver: NSObjectProtocol?
    var onBoundsSizeChange: ((MarkdownTextView) -> Void)?
    private var lastBoundsSize: CGSize = .zero
    
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

    override func layoutSubviews() {
        super.layoutSubviews()

        let currentSize = bounds.size
        guard currentSize != .zero, currentSize != lastBoundsSize else { return }
        lastBoundsSize = currentSize
        onBoundsSizeChange?(self)
    }
    
    private func setupMenuItems() {
        // UIEditMenuInteraction is required for custom edit-menu items on iOS 16+.
        // Keep the selector handlers available without registering deprecated UIMenuController items.
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
        toggleWrappedSelection(with: "**")
    }
    
    // Intercept "Italic" command
    override func toggleItalics(_ sender: Any?) {
        toggleWrappedSelection(with: "*")
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

    private func expandedLineRange(for selection: NSRange, in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }

        let safeLocation = min(selection.location, text.length - 1)
        if selection.length == 0 {
            return text.lineRange(for: NSRange(location: safeLocation, length: 0))
        }

        let selectionEnd = min(selection.location + selection.length, text.length)
        let safeEndLocation = max(safeLocation, selectionEnd - 1)

        let startLineRange = text.lineRange(for: NSRange(location: safeLocation, length: 0))
        let endLineRange = text.lineRange(for: NSRange(location: safeEndLocation, length: 0))
        let start = startLineRange.location
        let end = endLineRange.location + endLineRange.length
        return NSRange(location: start, length: max(0, end - start))
    }

    private func replaceCharacters(in range: NSRange, with replacement: String) {
        guard let start = self.position(from: beginningOfDocument, offset: range.location),
              let end = self.position(from: beginningOfDocument, offset: range.location + range.length),
              let textRange = self.textRange(from: start, to: end) else {
            return
        }
        self.replace(textRange, withText: replacement)
    }

    private func headingPrefixLength(in line: String) -> Int {
        if line.hasPrefix("### ") { return 4 }
        if line.hasPrefix("## ") { return 3 }
        if line.hasPrefix("# ") { return 2 }
        return 0
    }

    private func removeAllHeadingPrefixes(from line: String) -> (text: String, removedLength: Int) {
        var current = line
        var removed = 0

        while true {
            let prefixLength = headingPrefixLength(in: current)
            guard prefixLength > 0 else { break }
            current = String(current.dropFirst(prefixLength))
            removed += prefixLength
        }

        return (current, removed)
    }

    private func splitOuterWhitespace(_ text: String) -> (leading: String, core: String, trailing: String) {
        guard !text.isEmpty else { return ("", "", "") }

        let chars = Array(text)
        var start = 0
        var end = chars.count

        while start < end && chars[start].isWhitespace {
            start += 1
        }

        while end > start && chars[end - 1].isWhitespace {
            end -= 1
        }

        let leading = String(chars[0..<start])
        let core = String(chars[start..<end])
        let trailing = String(chars[end..<chars.count])
        return (leading, core, trailing)
    }

    private enum InlineStyleKind {
        case bold
        case italic
        case strikethrough
    }

    private struct InlineStyleState {
        var isBold = false
        var isItalic = false
        var isStrikethrough = false
    }

    private struct InlineStyleResult {
        let text: String
        let selectionStart: Int
        let selectionLength: Int
    }

    private func isWrapped(_ text: String, with syntax: String) -> Bool {
        guard !text.isEmpty else { return false }

        switch syntax {
        case "**":
            return text.count >= 4 && text.hasPrefix("**") && text.hasSuffix("**")
        case "~~":
            return text.count >= 4 && text.hasPrefix("~~") && text.hasSuffix("~~")
        case "*":
            // Avoid treating bold markers as italic wrappers.
            return text.count >= 2 &&
                text.hasPrefix("*") &&
                text.hasSuffix("*") &&
                !(text.hasPrefix("**") && text.hasSuffix("**"))
        default:
            return false
        }
    }

    private func normalizedInlineStyle(from text: String) -> (core: String, state: InlineStyleState) {
        var current = text
        var state = InlineStyleState()

        while true {
            if isWrapped(current, with: "~~") {
                current = String(current.dropFirst(2).dropLast(2))
                state.isStrikethrough = true
                continue
            }

            if state.isStrikethrough && current.hasPrefix("~") && current.hasSuffix("~") && current.count >= 2 {
                current = String(current.dropFirst().dropLast())
                continue
            }

            if isWrapped(current, with: "**") {
                current = String(current.dropFirst(2).dropLast(2))
                state.isBold = true
                continue
            }

            if isWrapped(current, with: "*") {
                current = String(current.dropFirst().dropLast())
                state.isItalic = true
                continue
            }

            break
        }

        return (current, state)
    }

    private func inlineMarkerLength(for state: InlineStyleState) -> Int {
        let emphasisLength: Int
        if state.isBold && state.isItalic {
            emphasisLength = 3
        } else if state.isBold {
            emphasisLength = 2
        } else if state.isItalic {
            emphasisLength = 1
        } else {
            emphasisLength = 0
        }

        return emphasisLength + (state.isStrikethrough ? 2 : 0)
    }

    private func buildInlineStyleResult(
        for text: String,
        style: InlineStyleKind,
        forcedState: Bool? = nil
    ) -> InlineStyleResult {
        let whitespaceParts = splitOuterWhitespace(text)
        let normalized = normalizedInlineStyle(from: whitespaceParts.core)
        var state = normalized.state

        switch style {
        case .bold:
            state.isBold = forcedState ?? !state.isBold
        case .italic:
            state.isItalic = forcedState ?? !state.isItalic
        case .strikethrough:
            state.isStrikethrough = forcedState ?? !state.isStrikethrough
        }

        var styledCore = normalized.core
        if state.isBold && state.isItalic {
            styledCore = "***\(styledCore)***"
        } else if state.isBold {
            styledCore = "**\(styledCore)**"
        } else if state.isItalic {
            styledCore = "*\(styledCore)*"
        }

        if state.isStrikethrough {
            styledCore = "~~\(styledCore)~~"
        }

        let replacement = whitespaceParts.leading + styledCore + whitespaceParts.trailing
        let selectionStart = (whitespaceParts.leading as NSString).length + inlineMarkerLength(for: state)
        let selectionLength = (normalized.core as NSString).length

        return InlineStyleResult(
            text: replacement,
            selectionStart: selectionStart,
            selectionLength: selectionLength
        )
    }

    private func lineHasInlineStyle(_ line: String, style: InlineStyleKind) -> Bool {
        let parts = splitOuterWhitespace(line)
        let normalized = normalizedInlineStyle(from: parts.core)

        switch style {
        case .bold:
            return normalized.state.isBold
        case .italic:
            return normalized.state.isItalic
        case .strikethrough:
            return normalized.state.isStrikethrough
        }
    }

    private func isInlineMarker(_ character: unichar) -> Bool {
        character == 42 || character == 126
    }

    private func isWordLikeCharacter(_ character: unichar) -> Bool {
        guard let scalar = UnicodeScalar(character) else { return false }
        return !CharacterSet.whitespacesAndNewlines.contains(scalar) && !isInlineMarker(character)
    }

    private func wordRangeNearCursor(in text: NSString, cursorLocation: Int) -> NSRange? {
        guard text.length > 0 else { return nil }

        let boundedCursor = min(max(0, cursorLocation), text.length)
        let anchor: Int
        if boundedCursor < text.length && isWordLikeCharacter(text.character(at: boundedCursor)) {
            anchor = boundedCursor
        } else if boundedCursor > 0 && isWordLikeCharacter(text.character(at: boundedCursor - 1)) {
            anchor = boundedCursor - 1
        } else {
            return nil
        }

        var start = anchor
        var end = anchor + 1

        while start > 0 && isWordLikeCharacter(text.character(at: start - 1)) {
            start -= 1
        }

        while end < text.length && isWordLikeCharacter(text.character(at: end)) {
            end += 1
        }

        return NSRange(location: start, length: max(0, end - start))
    }

    private func expandedInlineRange(_ range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        var end = range.location + range.length

        while start > 0 && isInlineMarker(text.character(at: start - 1)) {
            start -= 1
        }

        while end < text.length && isInlineMarker(text.character(at: end)) {
            end += 1
        }

        return NSRange(location: start, length: max(0, end - start))
    }

    private func resolvedInlineSelectionRange(for selection: NSRange, in text: NSString) -> NSRange? {
        if selection.length > 0 {
            return expandedInlineRange(selection, in: text)
        }

        guard let wordRange = wordRangeNearCursor(in: text, cursorLocation: selection.location) else {
            return nil
        }
        return expandedInlineRange(wordRange, in: text)
    }

    private func emptyInlineInsertion(for style: InlineStyleKind) -> (text: String, cursorOffset: Int) {
        switch style {
        case .bold:
            return ("****", 2)
        case .italic:
            return ("**", 1)
        case .strikethrough:
            return ("~~~~", 2)
        }
    }

    private func toggleInlineStylePerLine(_ selectedText: String, style: InlineStyleKind) -> String {
        var lines = selectedText.components(separatedBy: "\n")
        let hasTrailingNewline = selectedText.hasSuffix("\n")

        let editableLineIndices = lines.indices.filter { index in
            !(hasTrailingNewline && index == lines.count - 1 && lines[index].isEmpty)
        }

        guard !editableLineIndices.isEmpty else { return selectedText }

        let nonEmptyIndices = editableLineIndices.filter {
            !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let targetIndices = nonEmptyIndices.isEmpty ? editableLineIndices : nonEmptyIndices

        let shouldEnableStyle = !targetIndices.allSatisfy { lineHasInlineStyle(lines[$0], style: style) }

        for index in editableLineIndices {
            if lines[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            lines[index] = buildInlineStyleResult(
                for: lines[index],
                style: style,
                forcedState: shouldEnableStyle
            ).text
        }

        return lines.joined(separator: "\n")
    }
    
    private func wrapLineWithHeading(_ prefix: String) {
        guard let text = self.text else { return }
        let nsString = text as NSString
        if nsString.length == 0 {
            replaceCharacters(in: NSRange(location: 0, length: 0), with: prefix)
            self.selectedRange = NSRange(location: (prefix as NSString).length, length: 0)
            return
        }

        let selection = self.selectedRange
        let lineRange = expandedLineRange(for: selection, in: nsString)
        guard lineRange.length > 0 else { return }

        let selectedBlock = nsString.substring(with: lineRange)
        let lines = selectedBlock.components(separatedBy: "\n")
        let hasTrailingNewline = selectedBlock.hasSuffix("\n")

        var transformedLines: [String] = []
        var firstLineDelta = 0

        for (index, line) in lines.enumerated() {
            let isTrailingSentinel = hasTrailingNewline && index == lines.count - 1 && line.isEmpty
            if isTrailingSentinel {
                transformedLines.append(line)
                continue
            }

            let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
            let core = String(line.dropFirst(indentation.count))
            let normalized = removeAllHeadingPrefixes(from: core)
            if index == 0 {
                firstLineDelta = (prefix as NSString).length - normalized.removedLength
            }

            transformedLines.append(indentation + prefix + normalized.text)
        }

        let replacement = transformedLines.joined(separator: "\n")
        replaceCharacters(in: lineRange, with: replacement)

        let totalLength = (self.text as NSString?)?.length ?? 0
        if selection.length > 0 {
            let replacementLength = (replacement as NSString).length
            let safeLength = min(replacementLength, max(0, totalLength - lineRange.location))
            self.selectedRange = NSRange(location: min(lineRange.location, totalLength), length: safeLength)
        } else {
            let originalOffset = max(0, selection.location - lineRange.location)
            let cursorOffset = max(0, originalOffset + firstLineDelta)
            let cursorLocation = min(lineRange.location + cursorOffset, totalLength)
            self.selectedRange = NSRange(location: cursorLocation, length: 0)
        }
    }
    
    private func toggleWrappedSelection(with syntax: String) {
        guard let text = self.text else { return }
        let nsString = text as NSString
        let originalRange = self.selectedRange

        let style: InlineStyleKind
        switch syntax {
        case "**":
            style = .bold
        case "*":
            style = .italic
        case "~~":
            style = .strikethrough
        default:
            return
        }

        guard let range = resolvedInlineSelectionRange(for: originalRange, in: nsString) else {
            let insertion = emptyInlineInsertion(for: style)
            replaceCharacters(in: originalRange, with: insertion.text)
            let totalLength = (self.text as NSString?)?.length ?? 0
            let cursorLocation = min(originalRange.location + insertion.cursorOffset, totalLength)
            self.selectedRange = NSRange(location: cursorLocation, length: 0)
            return
        }

        let selectedText = nsString.substring(with: range)

        // Inline markdown markers should not span multiple lines in this editor model.
        // Apply style per line to avoid malformed marker stacks and visible syntax artifacts.
        if selectedText.contains("\n") {
            let replacement = toggleInlineStylePerLine(selectedText, style: style)
            replaceCharacters(in: range, with: replacement)
            let replacementLength = (replacement as NSString).length
            self.selectedRange = NSRange(location: range.location, length: replacementLength)
            return
        }

        let replacement = buildInlineStyleResult(for: selectedText, style: style)
        replaceCharacters(in: range, with: replacement.text)
        self.selectedRange = NSRange(
            location: range.location + replacement.selectionStart,
            length: replacement.selectionLength
        )
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleBoldface(_:)) || 
           action == #selector(toggleItalics(_:)) ||
           action == #selector(makeH1) ||
           action == #selector(makeH2) ||
           action == #selector(makeH3) ||
           action == #selector(makeBody) {
            return isFirstResponder
        }
        return super.canPerformAction(action, withSender: sender)
    }

    private func applyFormattingAction(_ action: NoteFormattingAction) {
        switch action {
        case .bold:
            toggleWrappedSelection(with: "**")
        case .italic:
            toggleWrappedSelection(with: "*")
        case .strikethrough:
            toggleWrappedSelection(with: "~~")
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
        case .checklist:
            insertChecklistPrefix()
        case .bulletPoint:
            insertListPrefix("- ")
        case .numberedList:
            insertListPrefix("1. ")
        }
    }

    private func insertChecklistPrefix() {
        guard let text = self.text else { return }
        let nsString = text as NSString
        let range = self.selectedRange
        let checklistPrefix = "- [ ] "
        let checklistPrefixLength = (checklistPrefix as NSString).length

        if range.length > 0 {
            let blockRange = expandedLineRange(for: range, in: nsString)
            guard blockRange.length > 0 else { return }

            let selectedBlock = nsString.substring(with: blockRange)
            let hasTrailingNewline = selectedBlock.hasSuffix("\n")
            var lines = selectedBlock.components(separatedBy: "\n")
            let editableLineIndices = lines.indices.filter { index in
                !(hasTrailingNewline && index == lines.count - 1 && lines[index].isEmpty)
            }
            guard !editableLineIndices.isEmpty else { return }

            let candidateIndices = editableLineIndices.filter {
                !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let indicesForModeCheck = candidateIndices.isEmpty ? [editableLineIndices[0]] : candidateIndices

            let shouldToggleOff = indicesForModeCheck.allSatisfy { index in
                listPrefixInfo(for: lines[index]).hasChecklistPrefix
            }

            for index in editableLineIndices {
                let info = listPrefixInfo(for: lines[index])
                if shouldToggleOff {
                    lines[index] = info.indentation + info.contentWithoutPrefix
                } else {
                    lines[index] = info.indentation + checklistPrefix + info.contentWithoutPrefix
                }
            }

            let replacement = lines.joined(separator: "\n")
            replaceCharacters(in: blockRange, with: replacement)
            let totalLength = (self.text as NSString?)?.length ?? 0
            let replacementLength = (replacement as NSString).length
            let safeLength = min(replacementLength, max(0, totalLength - blockRange.location))
            self.selectedRange = NSRange(location: min(blockRange.location, totalLength), length: safeLength)
            return
        }

        let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let hasTrailingNewline = lineText.hasSuffix("\n")
        let lineCore = hasTrailingNewline ? String(lineText.dropLast()) : lineText

        let info = listPrefixInfo(for: lineCore)
        let updatedLineCore: String
        let newCursorOffsetInLine: Int
        if info.hasChecklistPrefix {
            updatedLineCore = info.indentation + info.contentWithoutPrefix
            newCursorOffsetInLine = min(max(0, range.location - lineRange.location), updatedLineCore.count)
        } else {
            updatedLineCore = info.indentation + checklistPrefix + info.contentWithoutPrefix
            newCursorOffsetInLine = min(updatedLineCore.count, info.indentation.count + checklistPrefixLength)
        }

        let replacementText = hasTrailingNewline ? updatedLineCore + "\n" : updatedLineCore
        if let textRange = self.textRange(
            from: self.position(from: beginningOfDocument, offset: lineRange.location)!,
            to: self.position(from: beginningOfDocument, offset: lineRange.location + lineRange.length)!
        ) {
            self.replace(textRange, withText: replacementText)

            let maxCursor = (self.text ?? "").utf16.count
            let cursorLocation = min(maxCursor, lineRange.location + newCursorOffsetInLine)
            self.selectedRange = NSRange(location: cursorLocation, length: 0)
        }
    }
    
    private func insertListPrefix(_ prefix: String) {
        guard let text = self.text else { return }
        let nsString = text as NSString
        let range = self.selectedRange

        if range.length > 0 {
            let blockRange = expandedLineRange(for: range, in: nsString)
            guard blockRange.length > 0 else { return }

            let selectedBlock = nsString.substring(with: blockRange)
            let hasTrailingNewline = selectedBlock.hasSuffix("\n")
            var lines = selectedBlock.components(separatedBy: "\n")
            let editableLineIndices = lines.indices.filter { index in
                !(hasTrailingNewline && index == lines.count - 1 && lines[index].isEmpty)
            }
            guard !editableLineIndices.isEmpty else { return }

            let candidateIndices = editableLineIndices.filter {
                !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let indicesForModeCheck = candidateIndices.isEmpty ? [editableLineIndices[0]] : candidateIndices

            let shouldToggleOff = indicesForModeCheck.allSatisfy { index in
                let info = listPrefixInfo(for: lines[index])
                return prefix == "- " ? info.hasBulletPrefix : info.hasNumberedPrefix
            }

            var numbering = 1
            for index in editableLineIndices {
                let info = listPrefixInfo(for: lines[index])
                if shouldToggleOff {
                    lines[index] = info.indentation + info.contentWithoutPrefix
                } else if prefix == "- " {
                    lines[index] = info.indentation + "- " + info.contentWithoutPrefix
                } else {
                    lines[index] = info.indentation + "\(numbering). " + info.contentWithoutPrefix
                    numbering += 1
                }
            }

            let replacement = lines.joined(separator: "\n")
            replaceCharacters(in: blockRange, with: replacement)
            let totalLength = (self.text as NSString?)?.length ?? 0
            let replacementLength = (replacement as NSString).length
            let safeLength = min(replacementLength, max(0, totalLength - blockRange.location))
            self.selectedRange = NSRange(location: min(blockRange.location, totalLength), length: safeLength)
            return
        }

        // Get the current line at cursor.
        let lineRange = nsString.lineRange(for: NSRange(location: range.location, length: 0))
        let lineText = nsString.substring(with: lineRange)
        let hasTrailingNewline = lineText.hasSuffix("\n")
        let lineCore = hasTrailingNewline ? String(lineText.dropLast()) : lineText

        let info = listPrefixInfo(for: lineCore)
        let isSamePrefixType = (prefix == "- " && info.hasBulletPrefix && !info.hasChecklistPrefix) ||
            (prefix == "1. " && info.hasNumberedPrefix)

        let updatedLineCore: String
        let newCursorOffsetInLine: Int
        if isSamePrefixType {
            // Toggle off if user taps the same list style again.
            updatedLineCore = info.indentation + info.contentWithoutPrefix
            newCursorOffsetInLine = min(max(0, range.location - lineRange.location), updatedLineCore.count)
        } else {
            // Add or switch list style while keeping indentation.
            updatedLineCore = info.indentation + prefix + info.contentWithoutPrefix
            newCursorOffsetInLine = min(updatedLineCore.count, info.indentation.count + prefix.count)
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
        let selection = self.selectedRange
        let lineRange = expandedLineRange(for: selection, in: nsString)
        guard lineRange.length > 0 else { return }

        let selectedBlock = nsString.substring(with: lineRange)
        let lines = selectedBlock.components(separatedBy: "\n")
        let hasTrailingNewline = selectedBlock.hasSuffix("\n")

        var transformedLines: [String] = []
        var firstLineDelta = 0

        for (index, line) in lines.enumerated() {
            let isTrailingSentinel = hasTrailingNewline && index == lines.count - 1 && line.isEmpty
            if isTrailingSentinel {
                transformedLines.append(line)
                continue
            }

            let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
            let core = String(line.dropFirst(indentation.count))
            let normalized = removeAllHeadingPrefixes(from: core)
            if index == 0 {
                firstLineDelta = -normalized.removedLength
            }
            transformedLines.append(indentation + normalized.text)
        }

        let replacement = transformedLines.joined(separator: "\n")
        replaceCharacters(in: lineRange, with: replacement)

        let totalLength = (self.text as NSString?)?.length ?? 0
        if selection.length > 0 {
            let replacementLength = (replacement as NSString).length
            let safeLength = min(replacementLength, max(0, totalLength - lineRange.location))
            self.selectedRange = NSRange(location: min(lineRange.location, totalLength), length: safeLength)
        } else {
            let originalOffset = max(0, selection.location - lineRange.location)
            let cursorOffset = max(0, originalOffset + firstLineDelta)
            let cursorLocation = min(lineRange.location + cursorOffset, totalLength)
            self.selectedRange = NSRange(location: cursorLocation, length: 0)
        }
    }

    private func listPrefixInfo(for line: String) -> (indentation: String, contentWithoutPrefix: String, hasBulletPrefix: Bool, hasNumberedPrefix: Bool, hasChecklistPrefix: Bool) {
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let lineWithoutIndent = String(line.dropFirst(indentation.count))
        let hasBulletPrefix = lineWithoutIndent.hasPrefix("- ")
        let hasNumberedPrefix = numberedPrefixLength(in: lineWithoutIndent) != nil
        let hasChecklistPrefix = checklistPrefixLength(in: lineWithoutIndent) != nil

        var core = lineWithoutIndent

        // Normalize malformed stacked prefixes like "- 1. - text" before applying style changes.
        while true {
            if let checklistLength = checklistPrefixLength(in: core) {
                core = String(core.dropFirst(checklistLength))
                continue
            }
            if core.hasPrefix("- ") {
                core = String(core.dropFirst(2))
                continue
            }
            if let prefixLength = numberedPrefixLength(in: core) {
                core = String(core.dropFirst(prefixLength))
                continue
            }
            break
        }

        return (indentation, core, hasBulletPrefix, hasNumberedPrefix, hasChecklistPrefix)
    }

    private func numberedPrefixLength(in line: String) -> Int? {
        guard !line.isEmpty else { return nil }

        var index = line.startIndex
        while index < line.endIndex && line[index].isNumber {
            index = line.index(after: index)
        }

        guard index > line.startIndex, index < line.endIndex, line[index] == "." else {
            return nil
        }

        let afterDot = line.index(after: index)
        guard afterDot < line.endIndex, line[afterDot] == " " else {
            return nil
        }

        let prefixEnd = line.index(after: afterDot)
        return line.distance(from: line.startIndex, to: prefixEnd)
    }

    private func checklistPrefixLength(in line: String) -> Int? {
        let chars = Array(line)
        guard chars.count >= 5 else { return nil }
        guard (chars[0] == "-" || chars[0] == "*"),
              chars[1] == " ",
              chars[2] == "[",
              (chars[3] == " " || chars[3] == "x" || chars[3] == "X"),
              chars[4] == "]" else {
            return nil
        }

        if chars.count > 5, chars[5] == " " {
            return 6
        }
        return 5
    }
}
