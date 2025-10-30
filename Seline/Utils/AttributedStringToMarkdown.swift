import Foundation
import UIKit

class AttributedStringToMarkdown {
    static let shared = AttributedStringToMarkdown()

    private init() {}

    /// Converts NSAttributedString back to Markdown format with preserved formatting
    /// Detects and converts: **bold**, *italic*, # headings, and other markdown structures
    func convertToMarkdown(_ attributedString: NSAttributedString, baseFontSize: CGFloat = 15) -> String {
        let text = attributedString.string
        var result = ""
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            // Create attributed substring for this line to preserve formatting
            let lineRange = (text as NSString).range(of: line)
            if lineRange.location == NSNotFound {
                result += line + "\n"
                continue
            }

            let lineAttributedString = attributedString.attributedSubstring(from: lineRange)
            let processedLine = convertLineToMarkdown(lineAttributedString, baseFontSize: baseFontSize)
            result += processedLine + "\n"
        }

        // Clean up: remove extra newlines at the end while preserving table/todo markers
        return result.trimmingCharacters(in: .newlines)
    }

    private func convertLineToMarkdown(_ lineAttrString: NSAttributedString, baseFontSize: CGFloat) -> String {
        let text = lineAttrString.string
        let trimmedText = text.trimmingCharacters(in: .whitespaces)

        // Skip empty lines
        if trimmedText.isEmpty {
            return ""
        }

        // Check for heading at start (first character has bold font at specific sizes)
        // Only treat truly larger bold fonts as headings, not body text with bold applied
        if trimmedText.count > 0 {
            if let firstFont = lineAttrString.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
                let fontSize = firstFont.pointSize
                let isBold = firstFont.fontDescriptor.symbolicTraits.contains(.traitBold)

                if isBold {
                    // Detect headings by font size - only H1 (19pt) and H2 (17pt)
                    // DO NOT treat 15pt bold as heading - that's just bold body text
                    if fontSize >= 18.5 {
                        // >= 18.5: H1 (19pt)
                        return "# " + trimmedText
                    } else if fontSize >= 16.5 && fontSize < 18.5 {
                        // 16.5-18.5: H2 (17pt)
                        return "## " + trimmedText
                    }
                    // Skip H3 and below - they're just regular formatting
                }
            }
        }

        // Check for bullet point (starts with bullet symbol)
        if trimmedText.hasPrefix("•") || trimmedText.hasPrefix("-") || trimmedText.hasPrefix("*") {
            // Extract content after bullet
            let bulletRemoved = trimmedText.drop(while: { "•- *".contains($0) }).trimmingCharacters(in: .whitespaces)
            if !bulletRemoved.isEmpty {
                return "- " + bulletRemoved
            }
        }

        // Apply inline formatting - convert bold and italic back to markdown
        return convertInlineFormatting(lineAttrString, baseFontSize: baseFontSize)
    }

    private func convertInlineFormatting(_ attrString: NSAttributedString, baseFontSize: CGFloat) -> String {
        let text = attrString.string
        var result = ""
        var position = 0

        while position < text.count {
            let char = text[text.index(text.startIndex, offsetBy: position)]
            let range = NSRange(location: position, length: 1)

            if let font = attrString.attribute(.font, at: position, effectiveRange: nil) as? UIFont {
                let isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                let isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
                let isUnderlined = attrString.attribute(.underlineStyle, at: position, effectiveRange: nil) != nil

                // For consecutive characters with same formatting, group them
                var endPos = position + 1
                while endPos < text.count {
                    if let nextFont = attrString.attribute(.font, at: endPos, effectiveRange: nil) as? UIFont {
                        let nextBold = nextFont.fontDescriptor.symbolicTraits.contains(.traitBold)
                        let nextItalic = nextFont.fontDescriptor.symbolicTraits.contains(.traitItalic)
                        let nextUnderlined = attrString.attribute(.underlineStyle, at: endPos, effectiveRange: nil) != nil
                        if nextBold == isBold && nextItalic == isItalic && nextUnderlined == isUnderlined {
                            endPos += 1
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                }

                // Extract the formatted substring
                let startIndex = text.index(text.startIndex, offsetBy: position)
                let endIndex = text.index(text.startIndex, offsetBy: endPos)
                let substring = String(text[startIndex..<endIndex])

                // Build markdown with all formatting attributes
                var formatted = substring
                if isBold {
                    formatted = "**" + formatted + "**"
                }
                if isItalic {
                    formatted = "*" + formatted + "*"
                }
                if isUnderlined {
                    formatted = "__" + formatted + "__"
                }

                result += formatted
                position = endPos
            } else {
                result.append(char)
                position += 1
            }
        }

        return result
    }
}
