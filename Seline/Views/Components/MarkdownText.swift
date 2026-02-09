import SwiftUI

/// Renders markdown text with proper formatting
/// Converts # headings, bold, italics, tables, etc. into styled text
struct MarkdownText: View {
    let markdown: String
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parseMarkdown(markdown)) { element in
                renderElement(element)
                    .padding(.top, topPadding(for: element))
            }
        }
    }

    /// Element-specific top padding for ChatGPT-like visual rhythm
    private func topPadding(for element: MarkdownElement) -> CGFloat {
        switch element {
        case .heading1: return 16
        case .heading2: return 12
        case .heading3: return 10
        case .bulletPoint, .numberedPoint: return 4
        case .paragraph: return 8
        case .table: return 12
        case .empty: return 2
        case .horizontalRule: return 8
        default: return 6
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
            renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .bold)
        case .italic(let text):
            renderItalicText(stripMarkdownFormatting(text), size: 13)
        case .underline(let text):
            renderUnderlinedText(stripMarkdownFormatting(text), size: 13)
        case .code(let text):
            Text(text)
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(.orange)
                .padding(4)
                .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
                .cornerRadius(4)
                .textSelection(.enabled)
        case .bulletPoint(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(FontManager.geist(size: 13, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    .frame(minWidth: 16, alignment: .leading)
                renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .regular)
            }
            .padding(.leading, 8)
        case .numberedPoint(let number, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    .frame(minWidth: 16, alignment: .leading)
                renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .regular)
            }
            .padding(.leading, 8)
        case .table(let headers, let rows):
            renderTable(headers: headers, rows: rows)
        case .horizontalRule:
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 8)
        case .paragraph(let text):
            renderTextWithPhoneLinks(stripMarkdownFormatting(text), size: 13, weight: .regular)
        case .empty:
            Spacer()
                .frame(height: 4)
        }
    }

    // MARK: - Table Rendering
    
    @ViewBuilder
    private func renderTable(headers: [String], rows: [[String]]) -> some View {
        // ChatGPT-style: Clean, minimal, consistent background
        let borderColor = colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        let headerTextColor = colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
        let cellTextColor = colorScheme == .dark ? Color.white : Color.black.opacity(0.9)
        
        // Get pre-calculated column alignments
        let columnAlignments = calculateColumnAlignments(headers: headers, rows: rows)
        
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { i in
                        Text(stripMarkdownFormatting(headers[i]))
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(headerTextColor)
                            .lineLimit(1)
                            .frame(minWidth: columnWidth(for: i, headers: headers, rows: rows), alignment: columnAlignments[safe: i] ?? .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
                
                // Header bottom border
                Rectangle()
                    .fill(borderColor)
                    .frame(height: 1)
                
                // Data Rows
                ForEach(rows.indices, id: \.self) { rowIndex in
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(0..<headers.count, id: \.self) { cellIndex in
                                let cellText = cellIndex < rows[rowIndex].count ? rows[rowIndex][cellIndex] : ""
                                
                                Text(stripMarkdownFormatting(cellText))
                                    .font(FontManager.geist(size: 13, weight: .regular))
                                    .foregroundColor(cellTextColor)
                                    .lineLimit(1)
                                    .frame(minWidth: columnWidth(for: cellIndex, headers: headers, rows: rows), alignment: columnAlignments[safe: cellIndex] ?? .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            }
                        }
                        
                        // Subtle row separator (except after last row)
                        if rowIndex < rows.count - 1 {
                            Rectangle()
                                .fill(borderColor)
                                .frame(height: 0.5)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .padding(.vertical, 4)
    }
    
    /// Calculate appropriate column width based on content
    private func columnWidth(for columnIndex: Int, headers: [String], rows: [[String]]) -> CGFloat {
        // Get all values in this column including header
        var allValues: [String] = []
        if columnIndex < headers.count {
            allValues.append(headers[columnIndex])
        }
        for row in rows {
            if columnIndex < row.count {
                allValues.append(row[columnIndex])
            }
        }
        
        // Find the longest text and estimate width
        let maxLength = allValues.map { $0.count }.max() ?? 5
        
        // Base width calculation: ~7 points per character + padding
        let calculatedWidth = CGFloat(maxLength) * 7.5 + 20
        
        // Clamp between min and max
        return min(max(calculatedWidth, 60), 180)
    }
    
    /// Calculate column alignments based on content (numeric columns right-aligned)
    private func calculateColumnAlignments(headers: [String], rows: [[String]]) -> [Alignment] {
        let columnCount = headers.count
        var alignments: [Alignment] = Array(repeating: .leading, count: columnCount)
        
        for colIndex in 0..<columnCount {
            if colIndex == 0 {
                // First column always left-aligned (usually category/label)
                alignments[colIndex] = .leading
            } else {
                // Check if most values in this column are numeric
                let columnValues = rows.compactMap { row -> String? in
                    guard colIndex < row.count else { return nil }
                    return row[colIndex]
                }
                let numericCount = columnValues.filter { val in
                    val.hasPrefix("$") || val.hasSuffix("%") || 
                    Double(val.replacingOccurrences(of: ",", with: "")
                           .replacingOccurrences(of: "$", with: "")
                           .replacingOccurrences(of: "%", with: "")) != nil
                }.count
                alignments[colIndex] = numericCount > columnValues.count / 2 ? .trailing : .leading
            }
        }
        
        return alignments
    }

    // MARK: - Rich Text Rendering
    
    @ViewBuilder
    private func renderRichText(_ text: String, size: CGFloat, weight: Font.Weight) -> some View {
        // Parse simple markdown: **bold**, *italic*
        // Also handle phone links
        let attributedAsString = createRichText(text)
        
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(attributedAsString.enumerated()), id: \.offset) { index, component in
                renderRichComponent(component, size: size, baseWeight: weight)
            }
        }
    }
    
    private struct RichTextComponent {
        let text: String
        let isBold: Bool
        let isItalic: Bool
        let isPhone: Bool
        let phoneNumber: String?
    }
    
    private func createRichText(_ text: String) -> [RichTextComponent] {
        // 1. First split by phone numbers
        var components: [RichTextComponent] = []
        let phoneComponents = createAttributedStringWithPhoneLinks(text)
        
        // 2. Then process each component for markdown
        for pc in phoneComponents {
            if pc.isPhone {
                components.append(RichTextComponent(text: pc.text, isBold: false, isItalic: false, isPhone: true, phoneNumber: pc.phoneNumber))
            } else {
                components.append(contentsOf: parseMarkdownStyles(pc.text))
            }
        }
        return components
    }
    
    private func parseMarkdownStyles(_ text: String) -> [RichTextComponent] {
        // Simple parser for **bold** and *italic*
        // Note: Regex in Swift for nested groups isn't great, better to scan
        // This is a simplified version handling **...** first then *...*
        
        var results: [RichTextComponent] = []
        
        // Split by **
        let boldParts = text.components(separatedBy: "**")
        for (i, part) in boldParts.enumerated() {
            let isBold = (i % 2 == 1) // Every odd part is inside **
            
            // Now handle * inside this part
            let italicParts = part.components(separatedBy: "*")
            for (j, subPart) in italicParts.enumerated() {
                if subPart.isEmpty { continue }
                let isItalic = (j % 2 == 1) // Every odd part is inside *
                
                results.append(RichTextComponent(
                    text: subPart,
                    isBold: isBold,
                    isItalic: isItalic,
                    isPhone: false,
                    phoneNumber: nil
                ))
            }
        }
        
        return results
    }

    @ViewBuilder
    private func renderRichComponent(_ component: RichTextComponent, size: CGFloat, baseWeight: Font.Weight) -> some View {
        let weight: Font.Weight = component.isBold ? .bold : baseWeight

        if component.isPhone, let phoneNumber = component.phoneNumber {
            Link(destination: URL(string: "tel:\(phoneNumber)")!) {
                Text(component.text)
                    .font(FontManager.geist(size: size, systemWeight: weight))
                    .foregroundColor(.blue)
                    .underline()
            }
        } else if component.isItalic {
            Text(component.text)
                .font(FontManager.geist(size: size, systemWeight: weight))
                .italic()
                .foregroundColor(colorScheme == .dark ? .white : .black)
        } else {
            Text(component.text)
                .font(FontManager.geist(size: size, systemWeight: weight))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }

    // MARK: - Italic Text Rendering

    @ViewBuilder
    private func renderItalicText(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(FontManager.geist(size: size, weight: .regular))
            .italic()
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .textSelection(.enabled)
    }

    // MARK: - Underlined Text Rendering

    @ViewBuilder
    private func renderUnderlinedText(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(FontManager.geist(size: size, weight: .regular))
            .underline()
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .textSelection(.enabled)
    }

    // MARK: - Text Rendering with Phone Links (Legacy Wrapper)
    
    @ViewBuilder
    private func renderTextWithPhoneLinks(_ text: String, size: CGFloat, weight: Font.Weight) -> some View {
        renderRichText(text, size: size, weight: weight)
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
    
    private func renderPhoneComponent(_ component: PhoneComponent, size: CGFloat, systemWeight: Font.Weight) -> some View {
       // This function is now superseded by renderRichText but kept for structure compatibility if needed.
       // We can actually just remove it if we replace the calls.
       EmptyView()
    }

    // MARK: - Markdown Parsing
    
    private func parseMarkdown(_ text: String) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty {
                elements.append(.empty)
                i += 1
                continue
            }
            
            // Horizontal rule
            if trimmed.count >= 3 && (trimmed.allSatisfy { $0 == "-" } || trimmed.allSatisfy { $0 == "*" } || trimmed.allSatisfy { $0 == "_" }) {
                elements.append(.horizontalRule)
                i += 1
                continue
            }

            // Headings
            if trimmed.hasPrefix("# ") {
                elements.append(.heading1(String(trimmed.dropFirst(2))))
                i += 1; continue
            }
            if trimmed.hasPrefix("## ") {
                elements.append(.heading2(String(trimmed.dropFirst(3))))
                i += 1; continue
            }
            if trimmed.hasPrefix("### ") {
                elements.append(.heading3(String(trimmed.dropFirst(4))))
                i += 1; continue
            }

            // Table Detection - Modified for streaming
            if looksLikeTableStart(trimmed, at: i, in: lines) {
                let tableResult = parseTable(startingAt: i, in: lines)
                if let table = tableResult.table {
                    elements.append(table)
                    i = tableResult.nextIndex
                    continue
                }
                // If it looks like a table but parseTable returned nil (legacy check), 
                // in new logic parseTable returns even partial tables, so this branch is less likely 
                // but good for safety.
            }
            
            // Bullets
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("* ") {
                var text: String
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                    text = String(trimmed.dropFirst(2))
                } else {
                    text = String(trimmed.dropFirst(2))
                }
                elements.append(.bulletPoint(text))
                i += 1
                continue
            }
            
            // Numbered list
            if let match = trimmed.range(of: #"^(\d+)\.\s+(.*)$"#, options: .regularExpression) {
                // ... same logic as before ...
                let content = String(trimmed[match])
                if let dotIndex = content.firstIndex(of: ".") {
                    let numStr = String(content[content.startIndex..<dotIndex])
                    let textStart = content.index(after: dotIndex)
                    let text = String(content[textStart...]).trimmingCharacters(in: .whitespaces)
                    if let num = Int(numStr) {
                        elements.append(.numberedPoint(num, text))
                        i += 1
                        continue
                    }
                }
            }

            // Regular paragraph
            elements.append(.paragraph(line))
            i += 1
        }

        return elements
    }
    
    // MARK: - Table Parsing Helpers
    
    /// Check if a line looks like the start of a table
    private func looksLikeTableStart(_ line: String, at index: Int, in lines: [String]) -> Bool {
        let pipeCount = line.filter { $0 == "|" }.count
        return pipeCount >= 2 // Simple heuristic: if it has pipes, try to parse as table
    }
    
    /// Parse a table starting at a given index
    private func parseTable(startingAt startIndex: Int, in lines: [String]) -> (table: MarkdownElement?, nextIndex: Int) {
        var i = startIndex
        var allRows: [[String]] = []
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            // Check if this is a separator line (ignore it visually but consume it)
            if line.contains("|") && line.contains("-") && line.allSatisfy({ "|-:+ ".contains($0) }) {
                i += 1
                continue
            }
            
            // Check if this looks like a table row
            let pipeCount = line.filter { $0 == "|" }.count
            if pipeCount >= 2 {
                let cells = parseTableLine(line)
                if !cells.isEmpty {
                    allRows.append(cells)
                }
                i += 1
            } else {
                break
            }
        }
        
        // Allow even 1 row (header only) to return a table element
        // This fixes the 'raw text' flash during streaming
        guard !allRows.isEmpty else {
            // Only if totally empty do we fail
            return (nil, startIndex + 1)
        }
        
        let headers = allRows[0]
        let dataRows = allRows.count > 1 ? Array(allRows.dropFirst()) : []
        
        return (.table(headers: headers, rows: dataRows), i)
    }
    
    private func parseTableLine(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        
        // Remove leading/trailing pipes
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Formatting Helpers
    
    private func stripMarkdownFormatting(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        result = result.replacingOccurrences(of: "_", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        return result
    }
}

enum MarkdownElement: Hashable, Identifiable {
    case heading1(String)
    case heading2(String)
    case heading3(String)
    case bold(String)
    case italic(String)
    case underline(String)
    case code(String)
    case bulletPoint(String)
    case numberedPoint(Int, String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
    case paragraph(String)
    case empty
    
    // Unique ID for each element to prevent SwiftUI warnings
    var id: String {
        switch self {
        case .heading1(let text): return "h1-\(text.hashValue)"
        case .heading2(let text): return "h2-\(text.hashValue)"
        case .heading3(let text): return "h3-\(text.hashValue)"
        case .bold(let text): return "b-\(text.hashValue)"
        case .italic(let text): return "i-\(text.hashValue)"
        case .underline(let text): return "u-\(text.hashValue)"
        case .code(let text): return "code-\(text.hashValue)"
        case .bulletPoint(let text): return "bullet-\(text.hashValue)"
        case .numberedPoint(let num, let text): return "num-\(num)-\(text.hashValue)"
        case .table(let headers, let rows): return "table-\(headers.hashValue)-\(rows.hashValue)"
        case .horizontalRule: return "hr-\(UUID().uuidString)"
        case .paragraph(let text): return "p-\(text.hashValue)"
        case .empty: return "empty-\(UUID().uuidString)"
        }
    }
}

#Preview {
    ScrollView {
        MarkdownText(
            markdown: """
            # Main Heading
            
            ## Subheading
            
            This is a regular paragraph with some **bold** and *italic* text.
            
            - Bullet point 1
            - Bullet point 2
            • Bullet point 3
            * Bullet point 4
            
            1. Numbered item 1
            2. Numbered item 2
            3. Numbered item 3
            
            ---
            
            | Header 1 | Header 2 | Header 3 |
            |----------|----------|----------|
            | Cell 1   | Cell 2   | Cell 3   |
            | Cell 4   | Cell 5   | Cell 6   |
            
            Another paragraph after the table.
            """,
            colorScheme: .dark
        )
        .padding()
    }
    .background(Color.black)
}
