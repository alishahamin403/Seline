import SwiftUI

struct BlockEditorView: View {
    let block: AnyBlock
    @Binding var isFocused: Bool
    let onContentChange: (String) -> Void
    let onReturn: () -> Void
    let onBackspace: () -> Void
    let onTab: () -> Void
    let onShiftTab: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var content: String

    init(
        block: AnyBlock,
        isFocused: Binding<Bool>,
        onContentChange: @escaping (String) -> Void,
        onReturn: @escaping () -> Void,
        onBackspace: @escaping () -> Void,
        onTab: @escaping () -> Void,
        onShiftTab: @escaping () -> Void
    ) {
        self.block = block
        self._isFocused = isFocused
        self.onContentChange = onContentChange
        self.onReturn = onReturn
        self.onBackspace = onBackspace
        self.onTab = onTab
        self.onShiftTab = onShiftTab
        self._content = State(initialValue: block.content)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Block icon/prefix
            blockPrefix
                .animation(.easeInOut(duration: 0.2), value: block.blockType)

            // Content editor
            BlockTextField(
                text: $content,
                placeholder: block.blockType.placeholder,
                isFocused: $isFocused,
                font: blockFont,
                onSubmit: {
                    onReturn()
                },
                onBackspace: {
                    if content.isEmpty {
                        onBackspace()
                    }
                },
                onTab: {
                    onTab()
                },
                onShiftTab: {
                    onShiftTab()
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: content) { newValue in
                // Prevent feedback loop - only notify if content actually changed
                if newValue != block.content {
                    onContentChange(newValue)
                }
            }
            .foregroundColor(textColor)
            .animation(.easeInOut(duration: 0.15), value: textColor)
        }
        .padding(.leading, CGFloat(block.metadata.indentLevel) * 24)
        .padding(.trailing, 0)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: block.metadata.indentLevel)
        .clipped()
        .onChange(of: block.content) { newValue in
            // Update local state when block content changes externally (e.g., from markdown shortcuts)
            if content != newValue {
                content = newValue
            }
        }
        .onChange(of: block.id) { _ in
            // When block type changes, the ID stays the same but we need to sync content
            content = block.content
        }
    }

    @ViewBuilder
    private var blockPrefix: some View {
        switch block {
        case .bulletList:
            Text("•")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                .frame(width: 20)

        case .numberedList(let numbered):
            Text("\(numbered.number).")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                .frame(minWidth: 24, alignment: .trailing)

        case .checkbox(let checkbox):
            Button(action: {
                // Checkbox toggle handled by parent
            }) {
                Image(systemName: checkbox.metadata.isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundColor(checkbox.metadata.isChecked ? .blue : (colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7)))
            }
            .frame(width: 20)

        case .quote:
            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 3)
                .cornerRadius(1.5)

        case .divider:
            EmptyView()

        default:
            EmptyView()
        }
    }

    private var blockFont: Font {
        switch block.blockType {
        case .heading1:
            return .system(size: 28, weight: .bold)
        case .heading2:
            return .system(size: 22, weight: .bold)
        case .heading3:
            return .system(size: 18, weight: .semibold)
        case .code:
            return .system(size: 14, design: .monospaced)
        default:
            return .system(size: 16)
        }
    }

    private var textColor: Color {
        switch block.blockType {
        case .heading1, .heading2, .heading3:
            return colorScheme == .dark ? .white : .black
        case .quote:
            return colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8)
        case .code:
            return .green
        default:
            return colorScheme == .dark ? .white : .black
        }
    }
}

// MARK: - Custom TextView with Key Handling

struct BlockTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var isFocused: Bool
    let font: Font
    let onSubmit: () -> Void
    let onBackspace: () -> Void
    let onTab: () -> Void
    let onShiftTab: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = BlockCustomTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(from: font)
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.size = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isScrollEnabled = false
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.keyboardType = .default
        textView.returnKeyType = .default
        textView.clipsToBounds = true

        // Set consistent line height
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.2
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 2
        textView.typingAttributes = [
            .font: UIFont.preferredFont(from: font),
            .paragraphStyle: paragraphStyle
        ]

        // Set content compression resistance for proper layout
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Key handling
        textView.onBackspaceEmpty = onBackspace
        textView.onTab = onTab
        textView.onShiftTab = onShiftTab
        textView.onReturn = onSubmit

        // Setup placeholder
        textView.placeholderText = placeholder
        textView.placeholderColor = UIColor.placeholderText

        // Set initial text
        textView.text = text

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        guard let customTextView = uiView as? BlockCustomTextView else { return }

        // Update text container width when view updates
        DispatchQueue.main.async {
            uiView.setNeedsLayout()
            uiView.layoutIfNeeded()
            
            // Calculate available width and update text container
            if uiView.bounds.width > 0 {
                let availableWidth = uiView.bounds.width - uiView.textContainerInset.left - uiView.textContainerInset.right
                uiView.textContainer.size = CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
                uiView.textContainer.widthTracksTextView = true
            }
        }

        // Only update if we're not currently editing
        if !uiView.isFirstResponder {
            // Update text if it's different
            if uiView.text != text {
                uiView.text = text
            }
        }

        // Update font if changed
        let newFont = UIFont.preferredFont(from: font)
        if uiView.font != newFont {
            uiView.font = newFont

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineHeightMultiple = 1.2
            paragraphStyle.lineBreakMode = .byWordWrapping
            paragraphStyle.lineSpacing = 2
            uiView.typingAttributes = [
                .font: newFont,
                .paragraphStyle: paragraphStyle
            ]
        }

        // Update placeholder if changed
        if customTextView.placeholderText != placeholder {
            customTextView.placeholderText = placeholder
            customTextView.setNeedsDisplay()
        }

        // Handle focus changes
        if isFocused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        let parent: BlockTextField

        init(_ parent: BlockTextField) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // Only update if text actually changed
            if parent.text != textView.text {
                parent.text = textView.text
            }
            // Trigger placeholder update
            textView.setNeedsDisplay()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }
    }
}

// MARK: - Custom TextView for Key Interception

class BlockCustomTextView: UITextView {
    var onBackspaceEmpty: (() -> Void)?
    var onTab: (() -> Void)?
    var onShiftTab: (() -> Void)?
    var onReturn: (() -> Void)?

    var placeholderText: String = ""
    var placeholderColor: UIColor = .placeholderText

    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update text container width when layout changes
        if bounds.width > 0 {
            let availableWidth = bounds.width - textContainerInset.left - textContainerInset.right
            textContainer.size = CGSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
            textContainer.widthTracksTextView = true
        }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        // Draw placeholder if needed
        if text.isEmpty && !placeholderText.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font ?? UIFont.systemFont(ofSize: 16),
                .foregroundColor: placeholderColor
            ]
            let placeholderRect = CGRect(x: 0, y: 0, width: rect.width, height: rect.height)
            placeholderText.draw(in: placeholderRect, withAttributes: attributes)
        }
    }

    override func deleteBackward() {
        let wasEmpty = text.isEmpty
        super.deleteBackward()

        if wasEmpty {
            onBackspaceEmpty?()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false

        for press in presses {
            if press.key?.keyCode == .keyboardTab {
                if press.key?.modifierFlags.contains(.shift) == true {
                    onShiftTab?()
                } else {
                    onTab?()
                }
                handled = true
            } else if press.key?.keyCode == .keyboardReturnOrEnter {
                onReturn?()
                handled = true
            }
        }

        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
}

// MARK: - Helper Extension

extension UIFont {
    static func preferredFont(from font: Font) -> UIFont {
        // Convert SwiftUI Font to UIFont
        switch font {
        case .largeTitle:
            return .preferredFont(forTextStyle: .largeTitle)
        case .title:
            return .preferredFont(forTextStyle: .title1)
        case .title2:
            return .preferredFont(forTextStyle: .title2)
        case .title3:
            return .preferredFont(forTextStyle: .title3)
        case .headline:
            return .preferredFont(forTextStyle: .headline)
        case .subheadline:
            return .preferredFont(forTextStyle: .subheadline)
        case .body:
            return .preferredFont(forTextStyle: .body)
        case .callout:
            return .preferredFont(forTextStyle: .callout)
        case .caption:
            return .preferredFont(forTextStyle: .caption1)
        case .caption2:
            return .preferredFont(forTextStyle: .caption2)
        case .footnote:
            return .preferredFont(forTextStyle: .footnote)
        default:
            return .systemFont(ofSize: 16)
        }
    }
}

// MARK: - Divider Block View

struct DividerBlockView: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2))
            .frame(height: 1)
            .padding(.vertical, 12)
    }
}
