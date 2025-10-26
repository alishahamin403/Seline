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
        if trimmedText.count > 0 {
            if let firstFont = lineAttrString.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
                let fontSize = firstFont.pointSize
                let isBold = firstFont.fontDescriptor.symbolicTraits.contains(.traitBold)

                if isBold {
                    // Detect headings by font size
                    // RichTextEditor uses: H1=20pt, H2=18pt
                    // MarkdownParser uses: H1=27pt, H2=22.5pt, H3=19.5pt
                    // Identify which one by checking ranges
                    if fontSize >= 24 {
                        // >= 24: Must be MarkdownParser H1 (27pt)
                        return "# " + trimmedText
                    } else if fontSize >= 21 {
                        // 21-24: Must be MarkdownParser H2 (22.5pt) or RichTextEditor H1 (20pt)
                        // Closer to 22.5pt suggests H2 from parser, but could be H1 from editor
                        // Be conservative: treat as H2 if > 21.5, else H1
                        if fontSize > 21.5 {
                            return "## " + trimmedText
                        } else {
                            return "# " + trimmedText
                        }
                    } else if fontSize >= 19 {
                        // 19-21: MarkdownParser H3 (19.5pt) or RichTextEditor H1 (20pt)
                        if fontSize >= 19.7 {
                            return "# " + trimmedText  // Closer to 20pt
                        } else {
                            return "### " + trimmedText  // Closer to 19.5pt
                        }
                    } else if fontSize >= 18 {
                        // 18-19: RichTextEditor H2 (18pt) or MarkdownParser H3 (19.5pt)
                        if fontSize >= 18.7 {
                            return "### " + trimmedText  // Closer to 19.5pt
                        } else {
                            return "## " + trimmedText  // Is 18pt (RichTextEditor H2)
                        }
                    }
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

                // For consecutive characters with same formatting, group them
                var endPos = position + 1
                while endPos < text.count {
                    if let nextFont = attrString.attribute(.font, at: endPos, effectiveRange: nil) as? UIFont {
                        let nextBold = nextFont.fontDescriptor.symbolicTraits.contains(.traitBold)
                        let nextItalic = nextFont.fontDescriptor.symbolicTraits.contains(.traitItalic)
                        if nextBold == isBold && nextItalic == isItalic {
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

                if isBold && isItalic {
                    result += "***" + substring + "***"
                } else if isBold {
                    result += "**" + substring + "**"
                } else if isItalic {
                    result += "*" + substring + "*"
                } else {
                    result += substring
                }

                position = endPos
            } else {
                result.append(char)
                position += 1
            }
        }

        return result
    }
}
