import SwiftUI

/// MarkdownFormatter converts markdown strings into SwiftUI-renderable attributed text
struct MarkdownFormatter {
    /// Represents a parsed markdown element
    enum Element {
        case text(String)
        case bold(String)
        case italic(String)
        case code(String)
        case codeBlock(String)
        case heading(level: Int, text: String)
        case bulletPoint(String)
        case numberedItem(Int, String)
        case quote(String)
        case link(text: String, url: String)
    }

    /// Parse markdown string into elements
    static func parse(_ markdown: String) -> [Element] {
        var elements: [Element] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var i = 0
        while i < lines.count {
            let line = lines[i]

            // Code block (triple backticks)
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                var codeContent = ""
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeContent += lines[i] + "\n"
                    i += 1
                }
                elements.append(.codeBlock(codeContent.trimmingCharacters(in: .newlines)))
                i += 1
                continue
            }

            // Headings
            if let headingMatch = line.range(of: "^(#+)\\s+(.+)$", options: .regularExpression) {
                let headingLine = String(line[headingMatch])
                let hashes = headingLine.prefix(while: { $0 == "#" }).count
                let text = String(headingLine.dropFirst(hashes + 1))
                elements.append(.heading(level: hashes, text: text))
                i += 1
                continue
            }

            // Block quote
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                var quoteContent = ""
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let quoteLine = String(lines[i].dropFirst()).trimmingCharacters(in: .whitespaces)
                    quoteContent += quoteLine + "\n"
                    i += 1
                }
                elements.append(.quote(quoteContent.trimmingCharacters(in: .newlines)))
                continue
            }

            // Numbered list
            if let numberedMatch = line.range(of: "^\\d+\\.\\s+(.+)$", options: .regularExpression) {
                let numberedLine = String(line[numberedMatch])
                if let dotIndex = numberedLine.firstIndex(of: ".") {
                    let numberStr = String(numberedLine[..<dotIndex])
                    let text = String(numberedLine[numberedLine.index(after: dotIndex)...]).trimmingCharacters(in: .whitespaces)
                    if let number = Int(numberStr) {
                        elements.append(.numberedItem(number, text))
                    }
                }
                i += 1
                continue
            }

            // Bullet point
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                elements.append(.bulletPoint(text))
                i += 1
                continue
            }

            // Alternative bullet point
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("• ") {
                let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                elements.append(.bulletPoint(text))
                i += 1
                continue
            }

            // Regular paragraph - parse inline markdown
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                elements.append(contentsOf: parseInlineMarkdown(line))
            }

            i += 1
        }

        return elements
    }

    /// Parse inline markdown (bold, italic, code, links)
    private static func parseInlineMarkdown(_ text: String) -> [Element] {
        var elements: [Element] = []
        var remainingText = text

        while !remainingText.isEmpty {
            // Bold **text**
            if let range = remainingText.range(of: "\\*\\*(.+?)\\*\\*", options: .regularExpression) {
                let beforeText = String(remainingText[..<range.lowerBound])
                if !beforeText.isEmpty {
                    elements.append(.text(beforeText))
                }
                let boldText = String(remainingText[range])
                    .dropFirst(2)
                    .dropLast(2)
                elements.append(.bold(String(boldText)))
                remainingText = String(remainingText[range.upperBound...])
                continue
            }

            // Italic *text*
            if let range = remainingText.range(of: "\\*(.+?)\\*", options: .regularExpression) {
                let beforeText = String(remainingText[..<range.lowerBound])
                if !beforeText.isEmpty {
                    elements.append(.text(beforeText))
                }
                let italicText = String(remainingText[range])
                    .dropFirst(1)
                    .dropLast(1)
                elements.append(.italic(String(italicText)))
                remainingText = String(remainingText[range.upperBound...])
                continue
            }

            // Inline code `text`
            if let range = remainingText.range(of: "`(.+?)`", options: .regularExpression) {
                let beforeText = String(remainingText[..<range.lowerBound])
                if !beforeText.isEmpty {
                    elements.append(.text(beforeText))
                }
                let codeText = String(remainingText[range])
                    .dropFirst(1)
                    .dropLast(1)
                elements.append(.code(String(codeText)))
                remainingText = String(remainingText[range.upperBound...])
                continue
            }

            // Link [text](url)
            if let range = remainingText.range(of: "\\[(.+?)\\]\\((.+?)\\)", options: .regularExpression) {
                let beforeText = String(remainingText[..<range.lowerBound])
                if !beforeText.isEmpty {
                    elements.append(.text(beforeText))
                }

                let linkMatch = String(remainingText[range])
                if let textEnd = linkMatch.firstIndex(of: "]"),
                   let urlStart = linkMatch[textEnd...].firstIndex(of: "("),
                   let urlEnd = linkMatch[urlStart...].lastIndex(of: ")") {
                    let linkText = String(linkMatch[linkMatch.index(after: linkMatch.startIndex)..<textEnd])
                    let url = String(linkMatch[linkMatch.index(after: urlStart)..<urlEnd])
                    elements.append(.link(text: linkText, url: url))
                }
                remainingText = String(remainingText[range.upperBound...])
                continue
            }

            // No more special formatting found, add remaining text
            elements.append(.text(remainingText))
            break
        }

        return elements.filter { !($0 == .text("")) }
    }
}

/// Extension to compare Element enum
extension MarkdownFormatter.Element: Equatable {
    static func == (lhs: MarkdownFormatter.Element, rhs: MarkdownFormatter.Element) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            return a == b
        case (.bold(let a), .bold(let b)):
            return a == b
        case (.italic(let a), .italic(let b)):
            return a == b
        case (.code(let a), .code(let b)):
            return a == b
        case (.codeBlock(let a), .codeBlock(let b)):
            return a == b
        case (.heading(let la, let ta), .heading(let lb, let tb)):
            return la == lb && ta == tb
        case (.bulletPoint(let a), .bulletPoint(let b)):
            return a == b
        case (.numberedItem(let na, let ta), .numberedItem(let nb, let tb)):
            return na == nb && ta == tb
        case (.quote(let a), .quote(let b)):
            return a == b
        case (.link(let ta, let ua), .link(let tb, let ub)):
            return ta == tb && ua == ub
        default:
            return false
        }
    }
}

// Note: MarkdownText view is in Seline/Views/Components/MarkdownText.swift
// This formatter service provides the parsing logic used by MarkdownText
