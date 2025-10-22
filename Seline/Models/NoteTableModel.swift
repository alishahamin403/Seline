import Foundation
import SwiftUI

// MARK: - Note Table Models

/// Represents a table embedded in a note
struct NoteTable: Identifiable, Codable, Hashable {
    var id: UUID
    var rows: Int
    var columns: Int
    var cells: [[String]] // 2D array of cell content [row][column]
    var headerRow: Bool // Whether first row is a header
    var dateCreated: Date
    var dateModified: Date

    init(rows: Int, columns: Int, headerRow: Bool = true) {
        self.id = UUID()
        self.rows = rows
        self.columns = columns
        self.headerRow = headerRow
        self.dateCreated = Date()
        self.dateModified = Date()

        // Initialize cells with empty strings
        self.cells = Array(repeating: Array(repeating: "", count: columns), count: rows)
    }

    /// Get content of a specific cell
    func cellContent(row: Int, column: Int) -> String {
        guard row < rows && column < columns else { return "" }
        return cells[row][column]
    }

    /// Update content of a specific cell
    mutating func updateCell(row: Int, column: Int, content: String) {
        guard row < rows && column < columns else { return }
        cells[row][column] = content
        dateModified = Date()
    }

    /// Add a new row at the end
    mutating func addRow() {
        let newRow = Array(repeating: "", count: columns)
        cells.append(newRow)
        rows += 1
        dateModified = Date()
    }

    /// Add a new column at the end
    mutating func addColumn() {
        for i in 0..<rows {
            cells[i].append("")
        }
        columns += 1
        dateModified = Date()
    }

    /// Remove a row at specified index
    mutating func removeRow(at index: Int) {
        guard index < rows && rows > 1 else { return }
        cells.remove(at: index)
        rows -= 1
        dateModified = Date()
    }

    /// Remove a column at specified index
    mutating func removeColumn(at index: Int) {
        guard index < columns && columns > 1 else { return }
        for i in 0..<rows {
            cells[i].remove(at: index)
        }
        columns -= 1
        dateModified = Date()
    }

    /// Convert table to markdown format
    func toMarkdown() -> String {
        var markdown = ""

        for (rowIndex, row) in cells.enumerated() {
            markdown += "| " + row.joined(separator: " | ") + " |\n"

            // Add separator after header row
            if rowIndex == 0 && headerRow {
                markdown += "| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |\n"
            }
        }

        return markdown
    }

    /// Convert table to CSV format
    func toCSV() -> String {
        cells.map { row in
            row.map { cell in
                // Escape quotes and wrap in quotes if contains comma
                let escaped = cell.replacingOccurrences(of: "\"", with: "\"\"")
                return escaped.contains(",") || escaped.contains("\n") ? "\"\(escaped)\"" : escaped
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    /// Create table from markdown string
    static func fromMarkdown(_ markdown: String) -> NoteTable? {
        let lines = markdown.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !lines.isEmpty else { return nil }

        var rows: [[String]] = []
        var hasHeader = false

        for (_, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip separator line (|---|---|)
            if trimmed.contains("---") {
                hasHeader = true
                continue
            }

            // Parse cells from markdown table row
            let cells = trimmed.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if !cells.isEmpty {
                rows.append(cells)
            }
        }

        guard !rows.isEmpty else { return nil }

        // Normalize column count
        let maxColumns = rows.map { $0.count }.max() ?? 0
        for i in 0..<rows.count {
            while rows[i].count < maxColumns {
                rows[i].append("")
            }
        }

        var table = NoteTable(rows: rows.count, columns: maxColumns, headerRow: hasHeader)
        table.cells = rows

        return table
    }
}

// MARK: - Table Marker

/// Helper to insert table markers in note content
struct TableMarker {
    static func marker(for tableId: UUID) -> String {
        return "[TABLE:\(tableId.uuidString)]"
    }

    static func extractTableId(from marker: String) -> UUID? {
        let pattern = "\\[TABLE:([0-9A-F-]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: marker, range: NSRange(marker.startIndex..., in: marker)),
              let range = Range(match.range(at: 1), in: marker) else {
            return nil
        }
        return UUID(uuidString: String(marker[range]))
    }

    static func hasTableMarker(_ text: String) -> Bool {
        let pattern = "\\[TABLE:[0-9A-F-]+\\]"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func extractAllTableIds(from text: String) -> [UUID] {
        let pattern = "\\[TABLE:([0-9A-F-]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.compactMap { match -> UUID? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return UUID(uuidString: String(text[range]))
        }
    }
}
