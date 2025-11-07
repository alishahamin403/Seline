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
            Text(stripMarkdownFormatting(text))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .heading2(let text):
            Text(stripMarkdownFormatting(text))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .heading3(let text):
            Text(stripMarkdownFormatting(text))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .bold(let text):
            Text(stripMarkdownFormatting(text))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .italic(let text):
            Text(stripMarkdownFormatting(text))
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        case .underline(let text):
            Text(stripMarkdownFormatting(text))
                .font(.system(size: 13, weight: .regular))
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
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(stripMarkdownFormatting(text))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        case .numberedPoint(let number, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(stripMarkdownFormatting(text))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        case .paragraph(let text):
            Text(stripMarkdownFormatting(text))
                .font(.system(size: 13, weight: .regular))
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
                let text = String(trimmed.dropFirst(2))
                elements.append(.heading1(text))
            }
            // Heading 2
            else if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                elements.append(.heading2(text))
            }
            // Heading 3
            else if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4))
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
