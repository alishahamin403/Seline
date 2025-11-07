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
            Text(text)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .heading2(let text):
            Text(text)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .heading3(let text):
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .bold(let text):
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .italic(let text):
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .italic()
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .underline(let text):
            Text(text)
                .font(.system(size: 14, weight: .regular))
                .underline()
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .code(let text):
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(.orange)
                .padding(4)
                .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
                .cornerRadius(4)
        case .bulletPoint(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        case .numberedPoint(let number, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(text)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        case .paragraph(let text):
            Text(parseInlineFormatting(text))
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(nil)
        case .empty:
            Spacer()
                .frame(height: 4)
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
                let text = parseInlineFormatting(String(trimmed.dropFirst(2)))
                elements.append(.heading1(text))
            }
            // Heading 2
            else if trimmed.hasPrefix("## ") {
                let text = parseInlineFormatting(String(trimmed.dropFirst(3)))
                elements.append(.heading2(text))
            }
            // Heading 3
            else if trimmed.hasPrefix("### ") {
                let text = parseInlineFormatting(String(trimmed.dropFirst(4)))
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

    // Parse inline formatting like **bold**, *italic*, __underline__
    private func parseInlineFormatting(_ text: String) -> String {
        var result = ""
        var i = text.startIndex

        while i < text.endIndex {
            // Check for underline (__text__)
            if i < text.index(text.endIndex, offsetBy: -2) {
                let nextTwo = String(text[i..<text.index(i, offsetBy: 2)])
                if nextTwo == "__" {
                    // Find closing __
                    var searchIdx = text.index(i, offsetBy: 2)
                    var found = false
                    while searchIdx < text.index(text.endIndex, offsetBy: -1) {
                        if text[searchIdx] == "_" && text[text.index(after: searchIdx)] == "_" {
                            let content = String(text[text.index(i, offsetBy: 2)..<searchIdx])
                            result += content // Remove markdown syntax
                            i = text.index(after: text.index(after: searchIdx))
                            found = true
                            break
                        }
                        searchIdx = text.index(after: searchIdx)
                    }
                    if found { continue }
                }
            }

            // Check for bold (**text**)
            if i < text.index(text.endIndex, offsetBy: -2) {
                let nextTwo = String(text[i..<text.index(i, offsetBy: 2)])
                if nextTwo == "**" {
                    // Find closing **
                    var searchIdx = text.index(i, offsetBy: 2)
                    var found = false
                    while searchIdx < text.index(text.endIndex, offsetBy: -1) {
                        if text[searchIdx] == "*" && text[text.index(after: searchIdx)] == "*" {
                            let content = String(text[text.index(i, offsetBy: 2)..<searchIdx])
                            result += content // Remove markdown syntax
                            i = text.index(after: text.index(after: searchIdx))
                            found = true
                            break
                        }
                        searchIdx = text.index(after: searchIdx)
                    }
                    if found { continue }
                }
            }

            // Check for italic (*text*)
            if text[i] == "*" {
                if i < text.index(text.endIndex, offsetBy: -1) {
                    let nextChar = text[text.index(after: i)]
                    if nextChar != "*" { // Make sure it's not ** (bold)
                        if let closeIndex = text[text.index(after: i)...].firstIndex(of: "*") {
                            let content = String(text[text.index(after: i)..<closeIndex])
                            result += content // Remove markdown syntax
                            i = text.index(after: closeIndex)
                            continue
                        }
                    }
                }
            }

            result.append(text[i])
            i = text.index(after: i)
        }

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
