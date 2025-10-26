import Foundation
import UIKit

class MarkdownParser {
    static let shared = MarkdownParser()

    private init() {}

    /// Converts markdown text to NSAttributedString with proper formatting
    /// Supports: **bold**, *italic*, tables, bullet points, numbered lists, headings
    func parseMarkdown(_ text: String, fontSize: CGFloat = 15, textColor: UIColor = .label) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        let lines = text.components(separatedBy: .newlines)

        var inTable = false
        var tableRows: [String] = []

        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines between elements
            if trimmedLine.isEmpty && index < lines.count - 1 {
                // Add single newline for spacing
                attributedString.append(NSAttributedString(string: "\n"))
                continue
            }

            // Handle markdown tables
            if trimmedLine.contains("|") && !trimmedLine.contains("||") {
                if !inTable {
                    inTable = true
                    tableRows = []
                }
                tableRows.append(trimmedLine)

                // Check if next line is table separator or end of table
                let nextIndex = index + 1
                let isLastLine = nextIndex >= lines.count
                let nextLineIsTable = !isLastLine && lines[nextIndex].trimmingCharacters(in: .whitespaces).contains("|")

                if isLastLine || !nextLineIsTable {
                    // End of table, render it
                    let tableAttr = renderTable(tableRows, fontSize: fontSize, textColor: textColor)
                    attributedString.append(tableAttr)
                    attributedString.append(NSAttributedString(string: "\n"))
                    inTable = false
                    tableRows = []
                }
                continue
            } else {
                inTable = false
                tableRows = []
            }

            // Handle headings (# Heading, ## Heading, etc.)
            if trimmedLine.hasPrefix("#") {
                let headingAttr = parseHeading(trimmedLine, fontSize: fontSize, textColor: textColor)
                attributedString.append(headingAttr)
                attributedString.append(NSAttributedString(string: "\n"))
                continue
            }

            // Handle bullet points (•, -, *)
            if trimmedLine.hasPrefix("• ") || trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                let bulletAttr = parseBulletPoint(trimmedLine, fontSize: fontSize, textColor: textColor)
                attributedString.append(bulletAttr)
                attributedString.append(NSAttributedString(string: "\n"))
                continue
            }

            // Handle numbered items (1., 2., etc.)
            if let range = trimmedLine.range(of: "^(\\d+)\\.\\s+", options: .regularExpression) {
                let number = String(trimmedLine[range])
                let content = String(trimmedLine[range.upperBound...])
                let numberedAttr = parseNumberedItem(number: number, content: content, fontSize: fontSize, textColor: textColor)
                attributedString.append(numberedAttr)
                attributedString.append(NSAttributedString(string: "\n"))
                continue
            }

            // Regular paragraph with inline formatting
            let paragraphAttr = parseInlineFormatting(trimmedLine, fontSize: fontSize, textColor: textColor)
            attributedString.append(paragraphAttr)
            attributedString.append(NSAttributedString(string: "\n"))
        }

        return attributedString
    }

    // MARK: - Heading Parser

    private func parseHeading(_ line: String, fontSize: CGFloat, textColor: UIColor) -> NSAttributedString {
        var level = 0
        var text = line

        // Count number of # symbols
        while text.hasPrefix("#") && level < 6 {
            level += 1
            text = String(text.dropFirst())
        }

        text = text.trimmingCharacters(in: .whitespaces)

        // Calculate font size based on heading level
        // Sizes should not exceed title font (24pt)
        let headingSize: CGFloat
        switch level {
        case 1: headingSize = fontSize * 1.27  // H1 ≈ 19pt (RichTextEditor compatibility)
        case 2: headingSize = fontSize * 1.13  // H2 ≈ 17pt (RichTextEditor compatibility)
        case 3: headingSize = fontSize * 1.0   // H3 ≈ 15pt (body size)
        default: headingSize = fontSize        // H4+ same as body
        }

        // Create bold heading font with .traitBold symbolic trait
        let regularFont = UIFont.systemFont(ofSize: headingSize, weight: .regular)
        let boldHeadingFont: UIFont
        if let descriptor = regularFont.fontDescriptor.withSymbolicTraits(regularFont.fontDescriptor.symbolicTraits.union(.traitBold)) {
            boldHeadingFont = UIFont(descriptor: descriptor, size: headingSize)
        } else {
            boldHeadingFont = UIFont.systemFont(ofSize: headingSize, weight: .bold)
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: boldHeadingFont,
            .foregroundColor: textColor
        ]

        return NSAttributedString(string: text, attributes: attrs)
    }

    // MARK: - Bullet Point Parser

    private func parseBulletPoint(_ line: String, fontSize: CGFloat, textColor: UIColor) -> NSAttributedString {
        // Remove bullet prefix
        var content = line
        if content.hasPrefix("• ") || content.hasPrefix("- ") || content.hasPrefix("* ") {
            content = String(content.dropFirst(2))
        }

        let attributedString = NSMutableAttributedString()

        // Add bullet symbol
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: textColor
        ]
        attributedString.append(NSAttributedString(string: "  •  ", attributes: bulletAttrs))

        // Add content with inline formatting
        let contentAttr = parseInlineFormatting(content, fontSize: fontSize, textColor: textColor)
        attributedString.append(contentAttr)

        return attributedString
    }

    // MARK: - Numbered Item Parser

    private func parseNumberedItem(number: String, content: String, fontSize: CGFloat, textColor: UIColor) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()

        // Add number
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: textColor
        ]
        attributedString.append(NSAttributedString(string: "  \(number) ", attributes: numberAttrs))

        // Add content with inline formatting
        let contentAttr = parseInlineFormatting(content, fontSize: fontSize, textColor: textColor)
        attributedString.append(contentAttr)

        return attributedString
    }

    // MARK: - Inline Formatting Parser

    private func parseInlineFormatting(_ text: String, fontSize: CGFloat, textColor: UIColor) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        let currentText = text

        // Create fonts using symbolic traits for consistency with RichTextEditor
        let regularFont = UIFont.systemFont(ofSize: fontSize, weight: .regular)

        // Create bold font with .traitBold symbolic trait
        let boldFont: UIFont
        if let descriptor = regularFont.fontDescriptor.withSymbolicTraits(regularFont.fontDescriptor.symbolicTraits.union(.traitBold)) {
            boldFont = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            boldFont = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        }

        // Create italic font with .traitItalic symbolic trait
        let italicFont: UIFont
        if let descriptor = regularFont.fontDescriptor.withSymbolicTraits(regularFont.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            italicFont = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            italicFont = UIFont.italicSystemFont(ofSize: fontSize)
        }

        // Create bold+italic font
        let boldItalicFont: UIFont
        if let descriptor = regularFont.fontDescriptor.withSymbolicTraits(regularFont.fontDescriptor.symbolicTraits.union([.traitBold, .traitItalic])) {
            boldItalicFont = UIFont(descriptor: descriptor, size: fontSize)
        } else {
            boldItalicFont = boldFont  // Fallback
        }

        // Helper function to get correct font based on formatting flags
        func getFont(bold: Bool, italic: Bool) -> UIFont {
            if bold && italic {
                return boldItalicFont
            } else if bold {
                return boldFont
            } else if italic {
                return italicFont
            } else {
                return regularFont
            }
        }

        // Process text character by character to handle **bold** and *italic*
        var index = currentText.startIndex
        var buffer = ""
        var isBold = false
        var isItalic = false

        while index < currentText.endIndex {
            let char = currentText[index]

            if char == "*" {
                // Check for ** (bold)
                let nextIndex = currentText.index(after: index)
                if nextIndex < currentText.endIndex && currentText[nextIndex] == "*" {
                    // Found **
                    // Add current buffer with current formatting
                    if !buffer.isEmpty {
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: getFont(bold: isBold, italic: isItalic),
                            .foregroundColor: textColor
                        ]
                        attributedString.append(NSAttributedString(string: buffer, attributes: attrs))
                        buffer = ""
                    }

                    // Toggle bold
                    isBold.toggle()
                    index = currentText.index(after: nextIndex)
                    continue
                } else {
                    // Found single * (italic)
                    // Add current buffer with current formatting
                    if !buffer.isEmpty {
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: getFont(bold: isBold, italic: isItalic),
                            .foregroundColor: textColor
                        ]
                        attributedString.append(NSAttributedString(string: buffer, attributes: attrs))
                        buffer = ""
                    }

                    // Toggle italic
                    isItalic.toggle()
                    index = currentText.index(after: index)
                    continue
                }
            }

            // Add character to buffer
            buffer.append(char)
            index = currentText.index(after: index)
        }

        // Add remaining buffer with current formatting
        if !buffer.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: getFont(bold: isBold, italic: isItalic),
                .foregroundColor: textColor
            ]
            attributedString.append(NSAttributedString(string: buffer, attributes: attrs))
        }

        // If nothing was added, use the original text
        if attributedString.length == 0 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .foregroundColor: textColor
            ]
            return NSAttributedString(string: text, attributes: attrs)
        }

        return attributedString
    }

    // MARK: - Table Renderer

    private func renderTable(_ rows: [String], fontSize: CGFloat, textColor: UIColor) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()

        // Parse table rows
        var parsedRows: [[String]] = []
        var headerRowIndex: Int? = nil

        for (index, row) in rows.enumerated() {
            let trimmed = row.trimmingCharacters(in: .whitespaces)

            // Check if it's a separator row (e.g., |---|---|)
            if trimmed.contains("---") || trimmed.contains("===") {
                // Mark the previous row as header
                if index > 0 {
                    headerRowIndex = parsedRows.count - 1
                }
                continue
            }

            // Split by | and clean up
            var cells = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            // Remove empty first/last cells (from leading/trailing |)
            if let first = cells.first, first.isEmpty {
                cells.removeFirst()
            }
            if let last = cells.last, last.isEmpty {
                cells.removeLast()
            }

            if !cells.isEmpty {
                parsedRows.append(cells)
            }
        }

        // If no separator was found but we have rows, assume first row is header
        if headerRowIndex == nil && !parsedRows.isEmpty {
            headerRowIndex = 0
        }

        // Render table with enhanced formatting
        if !parsedRows.isEmpty {
            // Add top border
            let borderAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize - 2, weight: .regular),
                .foregroundColor: textColor.withAlphaComponent(0.3)
            ]
            attributedString.append(NSAttributedString(string: "─────────────────────────────\n", attributes: borderAttrs))

            for (rowIndex, rowCells) in parsedRows.enumerated() {
                let isHeader = rowIndex == headerRowIndex

                // Find max cell count for alignment
                let maxCells = parsedRows.map { $0.count }.max() ?? rowCells.count

                // Render each cell
                for cellIndex in 0..<maxCells {
                    let cell = cellIndex < rowCells.count ? rowCells[cellIndex] : ""

                    // Parse inline formatting for cell content (bold, italic)
                    let cellAttr = parseInlineFormatting(cell, fontSize: fontSize, textColor: textColor)

                    // Make header bold if not already formatted
                    if isHeader {
                        let mutableCellAttr = NSMutableAttributedString(attributedString: cellAttr)
                        let range = NSRange(location: 0, length: mutableCellAttr.length)
                        mutableCellAttr.addAttribute(.font, value: UIFont.systemFont(ofSize: fontSize, weight: .bold), range: range)
                        attributedString.append(mutableCellAttr)
                    } else {
                        attributedString.append(cellAttr)
                    }

                    // Add separator between cells (not after last cell)
                    if cellIndex < maxCells - 1 {
                        let separatorAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
                            .foregroundColor: textColor.withAlphaComponent(0.5)
                        ]
                        attributedString.append(NSAttributedString(string: "  │  ", attributes: separatorAttrs))
                    }
                }

                // Add newline after each row
                attributedString.append(NSAttributedString(string: "\n"))

                // Add separator line after header
                if isHeader {
                    attributedString.append(NSAttributedString(string: "─────────────────────────────\n", attributes: borderAttrs))
                }
            }

            // Add bottom border
            attributedString.append(NSAttributedString(string: "─────────────────────────────\n", attributes: borderAttrs))
        }

        return attributedString
    }
}
