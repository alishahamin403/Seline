import SwiftUI
import UIKit

// MARK: - Main Block Editor View
struct BlockEditorView: View {
    let block: AnyBlock
    @Binding var isFocused: Bool
    let onContentChange: (String) -> Void
    let onReturn: () -> Void
    let onBackspace: () -> Void
    let onTab: () -> Void
    let onShiftTab: () -> Void
    var onCheckboxToggle: (() -> Void)? = nil

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            // Checkbox specific handling
            if case .checkbox(let checkbox) = block {
                 Button(action: {
                     // Toggle checkbox state via callback
                     onCheckboxToggle?()
                 }) {
                     Image(systemName: checkbox.metadata.isChecked ? "checkmark.circle.fill" : "circle")
                         .font(.system(size: 20))
                         .foregroundColor(checkbox.metadata.isChecked ? .accentColor : .secondary)
                 }
                 .padding(.top, 2)
            } else if case .bulletList = block {
                Text("•")
                    .font(.system(size: 20))
                    .foregroundColor(.primary)
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 0)
            } else if case .numberedList(let item) = block {
                Text("\(item.number).")
                    .font(.body) // Apple Notes uses body font size for numbers
                    .foregroundColor(.primary)
                    .frame(minWidth: 20, alignment: .trailing)
                    .padding(.top, 2)
            }

            // The Text Editor
            AppleNotesTextView(
                text: Binding(
                    get: { block.content },
                    set: { onContentChange($0) } // Direct binding
                ),
                isFocused: $isFocused,
                font: appleNotesFont,
                textColor: appleNotesColor,
                onReturn: onReturn,
                onBackspace: onBackspace,
                onTab: onTab,
                onShiftTab: onShiftTab
            )
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 30) // Minimum touch target size, but allows expansion
        }
        .padding(.leading, CGFloat(block.metadata.indentLevel) * 20) // Standard indentation
        .padding(.vertical, 1) // Tight vertical spacing like Apple Notes
    }

    // MARK: - Apple Notes Style Typography
    private var appleNotesFont: UIFont {
        switch block.blockType {
        case .heading1:
            return .systemFont(ofSize: 28, weight: .bold) // Title
        case .heading2:
            return .systemFont(ofSize: 22, weight: .bold) // Heading
        case .heading3:
            return .systemFont(ofSize: 20, weight: .semibold) // Subheading
        case .code:
            return .monospacedSystemFont(ofSize: 15, weight: .regular)
        default:
            return .preferredFont(forTextStyle: .body) // roughly 17pt
        }
    }

    private var appleNotesColor: UIColor {
        switch block.blockType {
        case .quote:
            return .secondaryLabel
        case .code:
            return .label // Code blocks in Apple Notes are just monospaced, usually black/white
        default:
            return .label
        }
    }
}

// MARK: - Apple Notes Text View (UIViewRepresentable)
struct AppleNotesTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let font: UIFont
    let textColor: UIColor
    let onReturn: () -> Void
    let onBackspace: () -> Void
    let onTab: () -> Void
    let onShiftTab: () -> Void

    func makeUIView(context: Context) -> CustomUITextView {
        let textView = CustomUITextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.textColor = textColor
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false // Auto-expanding
        textView.textContainerInset = .zero // Remove default padding to align with SwiftUI Text
        textView.textContainer.lineFragmentPadding = 0 // Remove left/right padding
        
        // Input Accessory View for formatting (Apple Notes style)
        // We can add this later if needed, for more advanced formatting toolbar
        
        // Key callbacks
        textView.onReturn = onReturn
        textView.onBackspace = onBackspace
        textView.onTab = onTab
        textView.onShiftTab = onShiftTab
        
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        return textView
    }

    func updateUIView(_ uiView: CustomUITextView, context: Context) {
        // Update basic properties
        if uiView.font != font { uiView.font = font }
        if uiView.textColor != textColor { uiView.textColor = textColor }
        
        // Update Text ONLY if changed (prevents cursor jumping)
        if uiView.text != text {
            // Preserve cursor position if possible? 
            // Usually setting text resets cursor to end. 
            // In a block editor, usually the text update comes from typing, so we are ALREADY consistent.
            // We only force update if the EXTERNAL source changed it (e.g. AI rewrite).
            uiView.text = text
        }

        // Handle Focus
        DispatchQueue.main.async {
            if isFocused && !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !isFocused && uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: AppleNotesTextView

        init(_ parent: AppleNotesTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.isFocused = true
            }
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.isFocused = false
            }
        }
    }
}

// MARK: - Custom UIKit View for Key Handling
class CustomUITextView: UITextView {
    var onReturn: (() -> Void)?
    var onBackspace: (() -> Void)?
    var onTab: (() -> Void)?
    var onShiftTab: (() -> Void)?
    
    // Add Strike-through support via Menu
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(toggleStrikethrough(_:)) { return true }
        return super.canPerformAction(action, withSender: sender)
    }
    
    @objc func toggleStrikethrough(_ sender: Any?) {
        // Core functionality for strike-through would go here
        // For block-based, we often wrap in Markdown "~~"
        // But for "Apple Notes Experience", we might want attributed strings.
        // However, the data model is likely Strings. 
        // So we stick to wrapping selected text in ~~
        guard let range = selectedTextRange, 
              let selectedText = text(in: range), 
              !selectedText.isEmpty else { return }
        
        // Simple toggle logic
        if selectedText.hasPrefix("~~") && selectedText.hasSuffix("~~") {
            let newText = String(selectedText.dropFirst(2).dropLast(2))
            replace(range, withText: newText)
        } else {
            replace(range, withText: "~~\(selectedText)~~")
        }
    }
    
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: [
            UIAction(title: "Strikethrough") { [weak self] _ in
                self?.toggleStrikethrough(nil)
            }
        ]), atEndOfMenu: .format)
    }

    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTab)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(handleShiftTab))
        ]
    }

    @objc func handleTab() {
        onTab?()
    }

    @objc func handleShiftTab() {
        onShiftTab?()
    }

    override func deleteBackward() {
        if text.isEmpty {
            onBackspace?()
        } else {
            super.deleteBackward()
        }
    }
    
    // Intercept Return key
    override func insertText(_ text: String) {
        if text == "\n" {
            onReturn?()
        } else {
            super.insertText(text)
        }
    }
}

// MARK: - Divider Block
struct DividerBlockView: View {
    var body: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(height: 1)
            .padding(.vertical, 8)
    }
}
