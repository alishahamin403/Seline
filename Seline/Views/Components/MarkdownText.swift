import SwiftUI

/// Renders markdown text with proper formatting
/// Converts # headings, bold, italics, etc. into styled text
struct MarkdownText: View {
    let markdown: String
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdown(markdown), id: \.self) { element in
                renderElement(element)
            }
        }
    }

    @ViewBuilder
    private func renderElement(_ element: MarkdownElement) -> some View {
        switch element {
        case .heading1(let text):
            renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 20, weight: .bold)
        case .heading2(let text):
            renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 18, weight: .semibold)
        case .heading3(let text):
            renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 16, weight: .semibold)
        case .bold(let text):
            renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .regular)
        case .italic(let text):
            renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .regular)
        case .underline(let text):
            renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .regular)
        case .code(let text):
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.orange)
                .padding(4)
                .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
                .cornerRadius(4)
                .textSelection(.enabled)
        case .bulletPoint(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .textSelection(.enabled)
                renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .regular)
            }
        case .numberedPoint(let number, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .textSelection(.enabled)
                renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .regular)
            }
        case .paragraph(let text):
            renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .regular)
        case .empty:
            Spacer()
                .frame(height: 4)
        }
    }

    @ViewBuilder
    private func renderTextWithPhoneLinks(_ text: String, size: CGFloat, weight: Font.Weight) -> some View {
        let phoneRegex = try! NSRegularExpression(pattern: "\\b(?:\\+?1[-.]?)?\\(?([0-9]{3})\\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})\\b", options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = phoneRegex.matches(in: text, options: [], range: range)

        if matches.isEmpty {
            // No phone numbers found, render as plain text
            Text(text)
                .font(.system(size: size, weight: weight))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(nil)
                .textSelection(.enabled)
        } else {
            // Contains phone numbers, render with interactive links
            let attributedString = createAttributedStringWithPhoneLinks(text)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(attributedString.enumerated()), id: \.offset) { index, component in
                    renderPhoneComponent(component, size: size, weight: weight)
                }
            }
        }
    }

    private struct PhoneComponent {
        let text: String
        let isPhone: Bool
        let phoneNumber: String?
    }

    private func createAttributedStringWithPhoneLinks(_ text: String) -> [PhoneComponent] {
        var components: [PhoneComponent] = []
        let phoneRegex = try! NSRegularExpression(pattern: "\\b(?:\\+?1[-.]?)?\\(?([0-9]{3})\\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})\\b", options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = phoneRegex.matches(in: text, options: [], range: range)

        var lastEnd = 0
        for match in matches {
            if match.range.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                if let beforeString = Range(beforeRange, in: text) {
                    components.append(PhoneComponent(text: String(text[beforeString]), isPhone: false, phoneNumber: nil))
                }
            }
            if let phoneRange = Range(match.range, in: text) {
                let phoneText = String(text[phoneRange])
                let cleanedPhone = phoneText.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                components.append(PhoneComponent(text: phoneText, isPhone: true, phoneNumber: cleanedPhone))
            }
            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < text.count {
            let afterRange = NSRange(location: lastEnd, length: text.count - lastEnd)
            if let afterString = Range(afterRange, in: text) {
                components.append(PhoneComponent(text: String(text[afterString]), isPhone: false, phoneNumber: nil))
            }
        }

        return components
    }

    @ViewBuilder
    private func renderPhoneComponent(_ component: PhoneComponent, size: CGFloat, weight: Font.Weight) -> some View {
        if component.isPhone, let phoneNumber = component.phoneNumber {
            Link(destination: URL(string: "tel:\(phoneNumber)")!) {
                Text(component.text)
                    .font(.system(size: size, weight: weight))
                    .foregroundColor(.blue)
                    .underline()
                    .textSelection(.enabled)
            }
        } else {
            Text(component.text)
                .font(.system(size: size, weight: weight))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(nil)
                .textSelection(.enabled)
        }
    }

    private func parseMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Skip empty lines but track them
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                elements.append(.empty)
                i += 1
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Heading 1
            if trimmed.hasPrefix("# ") {
                let text = String(trimmed.dropFirst(2))
                elements.append(.heading1(text))
            }
            // Heading 2
            else if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                elements.append(.heading2(text))
            }
            // Heading 3 (also handles 4+ hashes by treating as heading 3)
            else if trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") || trimmed.hasPrefix("##### ") || trimmed.hasPrefix("###### ") {
                let text = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                elements.append(.heading3(text))
            }
            // Numbered list
            else if let firstCharIndex = trimmed.firstIndex(where: { $0.isNumber }) {
                let numberPart = String(trimmed[..<firstCharIndex])
                if numberPart.trimmingCharacters(in: .whitespaces).isEmpty {
                    let numberEndIndex = trimmed[firstCharIndex...].firstIndex(where: { !$0.isNumber }) ?? trimmed.endIndex
                    let number = String(trimmed[firstCharIndex..<numberEndIndex])
                    if trimmed[numberEndIndex...].first == "." {
                        let afterDot = trimmed.index(after: numberEndIndex)
                        let text = String(trimmed[afterDot...]).trimmingCharacters(in: .whitespaces)
                        if let num = Int(number) {
                            elements.append(.numberedPoint(num, text))
                        }
                    }
                } else {
                    elements.append(.paragraph(line))
                }
            }
            // Bullet point
            else if trimmed.hasPrefix("- ") {
                let text = String(trimmed.dropFirst(2))
                elements.append(.bulletPoint(text))
            } else if trimmed.hasPrefix("* ") {
                let text = String(trimmed.dropFirst(2))
                elements.append(.bulletPoint(text))
            }
            // Regular paragraph with inline formatting
            else {
                elements.append(.paragraph(line))
            }

            i += 1
        }

        return elements
    }

    // Strip markdown formatting symbols while keeping plain text
    private func stripMarkdownFormatting(_ text: String) -> String {
        var result = text

        // Remove ** bold markers
        result = result.replacingOccurrences(of: "**", with: "")

        // Remove * italic markers
        result = result.replacingOccurrences(of: "*", with: "")

        return result
    }
}

enum MarkdownElement: Hashable {
    case heading1(String)
    case heading2(String)
    case heading3(String)
    case bold(String)
    case italic(String)
    case underline(String)
    case code(String)
    case bulletPoint(String)
    case numberedPoint(Int, String)
    case paragraph(String)
    case empty
}

#Preview {
    MarkdownText(
        markdown: """
        # Main Heading

        ## Subheading

        This is a regular paragraph with some **bold** and *italic* text.

        - Bullet point 1
        - Bullet point 2
        - Bullet point 3

        1. Numbered item 1
        2. Numbered item 2
        3. Numbered item 3
        """,
        colorScheme: .light
    )
    .padding()
}
