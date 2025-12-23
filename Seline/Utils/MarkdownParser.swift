import Foundation
import UIKit

class MarkdownParser {
    static let shared = MarkdownParser()

    // Cache for parsed markdown results
    private var parseCache: [String: NSAttributedString] = [:]
    private let maxCacheSize = 100
    private var cacheAccessOrder: [String] = []

    private init() {}

    /// Converts markdown text to NSAttributedString with proper formatting
    /// Supports: **bold**, *italic*, bullet points, numbered lists, headings
    /// Tables are converted to bullet points. No syntax symbols are shown to user.
    func parseMarkdown(_ text: String, fontSize: CGFloat = 15, textColor: UIColor = .label) -> NSAttributedString {
        // Create a cache key that includes text, fontSize, and textColor
        let cacheKey = "\(text)|\(fontSize)|\(textColor.hashValue)"

        // Check if we have a cached result
        if let cachedResult = parseCache[cacheKey] {
            // Update access order for LRU eviction
            if let index = cacheAccessOrder.firstIndex(of: cacheKey) {
                cacheAccessOrder.remove(at: index)
            }
            cacheAccessOrder.append(cacheKey)
            return cachedResult
        }
        let attributedString = NSMutableAttributedString()

        // Process each line individually to handle headings, bullets, and inline formatting
        let originalLines = text.components(separatedBy: .newlines)

        for line in originalLines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines between elements
            if trimmedLine.isEmpty {
                attributedString.append(NSAttributedString(string: "\n"))
                continue
            }

            // Check for headings first (before cleaning markdown symbols)
            if trimmedLine.range(of: "^#{1,6}\\s+", options: .regularExpression) != nil {
                let headingAttr = parseHeading(trimmedLine, fontSize: fontSize, textColor: textColor)
                attributedString.append(headingAttr)
                attributedString.append(NSAttributedString(string: "\n"))
                continue
            }

            // Clean markdown syntax for non-heading lines
            var cleanedLine = trimmedLine

            // Convert table pipes to bullet points
            cleanedLine = convertTableLineToBulletPoints(cleanedLine)

            // Handle bullet points (•, -, *)
            if cleanedLine.hasPrefix("• ") || cleanedLine.hasPrefix("- ") || cleanedLine.hasPrefix("* ") {
                let bulletAttr = parseBulletPoint(cleanedLine, fontSize: fontSize, textColor: textColor)
                attributedString.append(bulletAttr)
                attributedString.append(NSAttributedString(string: "\n"))
                continue
            }

            // Handle numbered items (1., 2., etc.)
            if let range = cleanedLine.range(of: "^(\\d+)\\.\\s+", options: .regularExpression) {
                let number = String(cleanedLine[range])
                let content = String(cleanedLine[range.upperBound...])
                let numberedAttr = parseNumberedItem(number: number, content: content, fontSize: fontSize, textColor: textColor)
                attributedString.append(numberedAttr)
                attributedString.append(NSAttributedString(string: "\n"))
                continue
            }

            // Regular paragraph with inline formatting
            let paragraphAttr = parseInlineFormatting(cleanedLine, fontSize: fontSize, textColor: textColor)
            attributedString.append(paragraphAttr)
            attributedString.append(NSAttributedString(string: "\n"))
        }

        // Store result in cache
        parseCache[cacheKey] = attributedString
        cacheAccessOrder.append(cacheKey)

        // Evict oldest entries if cache is too large (LRU)
        if cacheAccessOrder.count > maxCacheSize {
            let oldestKey = cacheAccessOrder.removeFirst()
            parseCache.removeValue(forKey: oldestKey)
        }

        return attributedString
    }

    /// Clears the parsing cache (useful when memory pressure occurs)
    func clearCache() {
        parseCache.removeAll()
        cacheAccessOrder.removeAll()
    }

    // MARK: - Table to Bullet Points Converter

    private func convertTableLineToBulletPoints(_ line: String) -> String {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // Check if this is a table line (contains pipes)
        if trimmedLine.contains("|") && !trimmedLine.contains("||") {
            // Skip header row and separator rows, convert data rows to bullets
            let cells = trimmedLine.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
            let cellsClean = cells.filter { !$0.isEmpty && !$0.contains("-") }

            // Convert to bullet point format
            if !cellsClean.isEmpty {
                return "- " + cellsClean.joined(separator: " | ")
            }
        }

        return line
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
        // Use exact sizes to match RichTextEditor's heading sizes for consistency
        let headingSize: CGFloat
        switch level {
        case 1: headingSize = 19.0  // H1: 19pt (matches RichTextEditor exactly)
        case 2: headingSize = 17.0  // H2: 17pt (matches RichTextEditor exactly)
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
            .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: textColor
        ]
        attributedString.append(NSAttributedString(string: "• ", attributes: bulletAttrs))

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
            .font: UIFont.systemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: textColor
        ]
        attributedString.append(NSAttributedString(string: "\(number)", attributes: numberAttrs))

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

}
