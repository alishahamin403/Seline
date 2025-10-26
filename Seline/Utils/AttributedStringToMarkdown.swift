import Foundation
import UIKit

class AttributedStringToMarkdown {
    static let shared = AttributedStringToMarkdown()

    private init() {}

    /// Converts NSAttributedString back to Markdown format with preserved formatting
    /// Detects and converts: **bold**, *italic*, # headings, and other markdown structures
    func convertToMarkdown(_ attributedString: NSAttributedString, baseFontSize: CGFloat = 15) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attributedString.length)
        var lastWasNewline = true
        var previousAttributes: [NSAttributedString.Key: Any]? = nil

        attributedString.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            let substring = attributedString.attributedSubstring(from: range).string

            // Skip empty substrings
            if substring.isEmpty {
                return
            }

            // Check for newlines and preserve them
            if substring.contains("\n") {
                result += substring
                lastWasNewline = true
                previousAttributes = nil
                return
            }

            // Get font attributes
            let font = attributes[.font] as? UIFont
            let fontDescriptor = font?.fontDescriptor
            let fontSize = font?.pointSize ?? baseFontSize
            let isBold = (fontDescriptor?.symbolicTraits.contains(.traitBold) ?? false)
            let isItalic = (fontDescriptor?.symbolicTraits.contains(.traitItalic) ?? false)

            // Detect headings based on font size
            if lastWasNewline {
                if fontSize > baseFontSize * 1.7 {
                    // H1
                    result += "# " + substring
                    lastWasNewline = false
                    previousAttributes = attributes
                    return
                } else if fontSize > baseFontSize * 1.4 {
                    // H2
                    result += "## " + substring
                    lastWasNewline = false
                    previousAttributes = attributes
                    return
                } else if fontSize > baseFontSize * 1.2 {
                    // H3
                    result += "### " + substring
                    lastWasNewline = false
                    previousAttributes = attributes
                    return
                }
            }

            // Detect bullet points (start with "  •  " or similar patterns)
            if lastWasNewline && substring.hasPrefix("  •  ") {
                let bulletContent = String(substring.dropFirst(6))
                result += "- " + bulletContent
                lastWasNewline = false
                previousAttributes = attributes
                return
            }

            // Apply inline formatting
            var formattedText = substring

            if isBold && isItalic {
                formattedText = "***" + substring + "***"
            } else if isBold {
                formattedText = "**" + substring + "**"
            } else if isItalic {
                formattedText = "*" + substring + "*"
            }

            result += formattedText
            lastWasNewline = false
            previousAttributes = attributes
        }

        // Clean up: remove extra newlines at the end and preserve table/todo markers
        return result.trimmingCharacters(in: .newlines)
    }
}
