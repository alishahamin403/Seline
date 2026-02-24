import SwiftUI
import UIKit

// MARK: - Table Cell TextField (UIKit wrapper for proper focus handling)
// This ensures single-tap cell switching like Apple Notes

struct TableCellTextField: UIViewRepresentable {
    @Binding var text: String
    var isEditing: FocusState<Bool>.Binding
    var placeholder: String
    var font: UIFont
    var textColor: UIColor
    var onCommit: () -> Void
    var onTextChange: () -> Void
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.font = font
        textField.textColor = textColor
        textField.placeholder = placeholder
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.returnKeyType = .next
        textField.autocorrectionType = .no
        textField.text = text
        return textField
    }
    
    func updateUIView(_ textField: UITextField, context: Context) {
        // Update text if it changed externally
        if textField.text != text {
            textField.text = text
        }
        
        // Handle focus
        if isEditing.wrappedValue && !textField.isFirstResponder {
            DispatchQueue.main.async {
                textField.becomeFirstResponder()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TableCellTextField
        
        init(_ parent: TableCellTextField) {
            self.parent = parent
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            let newText = textField.text ?? ""
            if parent.text != newText {
                parent.text = newText
                parent.onTextChange()
            }
        }
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onCommit()
            return false
        }
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            // Don't reset isEditing here - let the parent view handle it
            // This prevents the double-tap issue
        }
    }
}

// MARK: - Parsed Content Item

enum NoteContentItem: Identifiable {
    case text(String)
    case table(MarkdownTable)
    
    var id: String {
        switch self {
        case .text(let content):
            return "text-\(content.hashValue)"
        case .table(let table):
            return "table-\(table.id)"
        }
    }
}

// MARK: - Markdown Table Model

struct MarkdownTable: Identifiable {
    let id = UUID()
    var headers: [String]
    var rows: [[String]]
    var rawMarkdown: String
    
    init(headers: [String], rows: [[String]], rawMarkdown: String) {
        self.headers = headers
        self.rows = rows
        self.rawMarkdown = rawMarkdown
    }
}

// MARK: - Markdown Table Parser

struct MarkdownTableParser {
    
    /// Parse content and separate into text and table items
    static func parse(_ content: String) -> [NoteContentItem] {
        var items: [NoteContentItem] = []
        let lines = content.components(separatedBy: "\n")
        
        var currentTextLines: [String] = []
        var tableLines: [String] = []
        var isInTable = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this line is a table row (starts with |)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if !isInTable {
                    // End current text section
                    if !currentTextLines.isEmpty {
                        let textContent = currentTextLines.joined(separator: "\n")
                        if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            items.append(.text(textContent))
                        }
                        currentTextLines = []
                    }
                    isInTable = true
                }
                tableLines.append(line)
            } else {
                if isInTable {
                    // End current table section
                    if let table = parseTableFromLines(tableLines) {
                        items.append(.table(table))
                    }
                    tableLines = []
                    isInTable = false
                }
                currentTextLines.append(line)
            }
        }
        
        // Handle remaining content
        if isInTable && !tableLines.isEmpty {
            if let table = parseTableFromLines(tableLines) {
                items.append(.table(table))
            }
        } else if !currentTextLines.isEmpty {
            let textContent = currentTextLines.joined(separator: "\n")
            if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                items.append(.text(textContent))
            }
        }
        
        return items
    }
    
    /// Parse a table from lines
    private static func parseTableFromLines(_ lines: [String]) -> MarkdownTable? {
        guard lines.count >= 2 else { return nil }
        
        var dataLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip separator lines (|---|---|)
            return !trimmed.contains("---")
        }
        
        guard !dataLines.isEmpty else { return nil }
        
        // First line is headers
        let headerLine = dataLines.removeFirst()
        let headers = parseCells(from: headerLine)
        
        // Rest are data rows
        let rows = dataLines.map { parseCells(from: $0) }
        
        return MarkdownTable(
            headers: headers,
            rows: rows,
            rawMarkdown: lines.joined(separator: "\n")
        )
    }
    
    /// Parse cells from a table row line
    private static func parseCells(from line: String) -> [String] {
        var cells = line.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        // Remove empty first/last elements from leading/trailing pipes
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells
    }
    
    /// Convert table back to markdown
    static func tableToMarkdown(_ table: MarkdownTable) -> String {
        var lines: [String] = []
        
        // Header row
        lines.append("| " + table.headers.joined(separator: " | ") + " |")
        
        // Separator row
        lines.append("|" + table.headers.map { _ in "---" }.joined(separator: "|") + "|")
        
        // Data rows
        for row in table.rows {
            // Pad row if needed
            var paddedRow = row
            while paddedRow.count < table.headers.count {
                paddedRow.append("")
            }
            lines.append("| " + paddedRow.prefix(table.headers.count).joined(separator: " | ") + " |")
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Inline Table View (Editable with Floating Controls)
// Uses UIKit TextField wrapper for Apple Notes-like single-tap cell switching

struct InlineTableView: View {
    let table: MarkdownTable
    var onTableUpdated: ((MarkdownTable) -> Void)?
    var onDelete: (() -> Void)?
    
    @Environment(\.colorScheme) var colorScheme
    @State private var editingCell: (row: Int, col: Int)? = nil
    @State private var editingText: String = ""
    @State private var localTable: MarkdownTable
    @FocusState private var isEditing: Bool
    
    private let cellWidth: CGFloat = 100
    private let cellHeight: CGFloat = 44
    
    init(table: MarkdownTable, onTableUpdated: ((MarkdownTable) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.table = table
        self.onTableUpdated = onTableUpdated
        self.onDelete = onDelete
        self._localTable = State(initialValue: table)
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
    }
    
    private var headerBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
    
    private var cellBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.white
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15)
    }
    
    private var addButtonColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }
    
    // Calculate max table width (screen width minus padding)
    private var maxTableWidth: CGFloat {
        UIScreen.main.bounds.width - 48 // Account for padding
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Main table content
                    VStack(spacing: 0) {
                        // Header row
                        headerRow
                        
                        // Data rows
                        ForEach(Array(localTable.rows.enumerated()), id: \.offset) { rowIndex, row in
                            dataRow(rowIndex: rowIndex, row: row)
                        }
                        
                        // Add row button
                        addRowButton
                    }
                    
                    // Add column button (on the right side)
                    addColumnButton
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .frame(maxWidth: maxTableWidth)
        .contextMenu {
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Table", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete", isPresented: $showingDeleteMenu, titleVisibility: .hidden) {
            if let rowIndex = deleteMenuRow {
                Button("Delete Row", role: .destructive) {
                    deleteRow(at: rowIndex)
                }
            }
            if let colIndex = deleteMenuCol, localTable.headers.count > 1 {
                Button("Delete Column", role: .destructive) {
                    deleteColumn(at: colIndex)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(localTable.headers.enumerated()), id: \.offset) { colIndex, header in
                headerCell(colIndex: colIndex, content: header)
            }
        }
    }
    
    private func headerCell(colIndex: Int, content: String) -> some View {
        let isEditingThis = editingCell?.row == -1 && editingCell?.col == colIndex
        
        return ZStack {
            // Background and border (always visible)
            Rectangle()
                .fill(headerBackgroundColor)
                .frame(width: cellWidth, height: cellHeight)
            
            if isEditingThis {
                // Editing mode - show TextField
                TableCellTextField(
                    text: $editingText,
                    isEditing: $isEditing,
                    placeholder: "Header",
                    font: .systemFont(ofSize: 13, weight: .semibold),
                    textColor: colorScheme == .dark ? .white : .black,
                    onCommit: { moveToNextCell() },
                    onTextChange: { commitEdit(keepEditing: true) }
                )
                .frame(width: cellWidth - 20, height: cellHeight - 10)
            } else {
                // Display mode - show Text
                Text(content.isEmpty ? "Header" : content)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(content.isEmpty ? secondaryTextColor : primaryTextColor)
                    .lineLimit(2)
                    .frame(width: cellWidth - 20, height: cellHeight, alignment: .leading)
            }
        }
        .frame(width: cellWidth, height: cellHeight)
        .overlay(Rectangle().stroke(borderColor, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture {
            switchToCell(row: -1, col: colIndex, content: content)
        }
        .onLongPressGesture {
            showDeleteColumnMenu(colIndex: colIndex)
        }
    }
    
    // MARK: - Data Row
    
    private func dataRow(rowIndex: Int, row: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<localTable.headers.count, id: \.self) { colIndex in
                let cellContent = colIndex < row.count ? row[colIndex] : ""
                dataCell(rowIndex: rowIndex, colIndex: colIndex, content: cellContent)
            }
        }
    }
    
    private func dataCell(rowIndex: Int, colIndex: Int, content: String) -> some View {
        let isEditingThis = editingCell?.row == rowIndex && editingCell?.col == colIndex
        
        return ZStack {
            // Background (always visible)
            Rectangle()
                .fill(cellBackgroundColor)
                .frame(width: cellWidth, height: cellHeight)
            
            if isEditingThis {
                // Editing mode - show TextField
                TableCellTextField(
                    text: $editingText,
                    isEditing: $isEditing,
                    placeholder: "",
                    font: .systemFont(ofSize: 13, weight: .regular),
                    textColor: colorScheme == .dark ? .white : .black,
                    onCommit: { moveToNextCell() },
                    onTextChange: { commitEdit(keepEditing: true) }
                )
                .frame(width: cellWidth - 20, height: cellHeight - 10)
            } else {
                // Display mode - show Text
                Text(content.isEmpty ? " " : content)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(content.isEmpty ? secondaryTextColor : primaryTextColor.opacity(0.9))
                    .lineLimit(2)
                    .frame(width: cellWidth - 20, height: cellHeight, alignment: .leading)
            }
        }
        .frame(width: cellWidth, height: cellHeight)
        .overlay(Rectangle().stroke(borderColor, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double tap - show delete menu
            showDeleteMenu(rowIndex: rowIndex, colIndex: colIndex)
        }
        .onTapGesture {
            // Single tap - switch to cell
            switchToCell(row: rowIndex, col: colIndex, content: content)
        }
        .onLongPressGesture {
            // Long press - show delete menu
            showDeleteMenu(rowIndex: rowIndex, colIndex: colIndex)
        }
    }
    
    // MARK: - Add Row Button
    
    private var addRowButton: some View {
        Button(action: addRow) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                Text("Add Row")
                    .font(FontManager.geist(size: 12, weight: .medium))
            }
            .foregroundColor(addButtonColor)
            .frame(width: CGFloat(localTable.headers.count) * cellWidth, height: 36)
            .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Add Column Button
    
    private var addColumnButton: some View {
        Button(action: addColumn) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(addButtonColor)
            .frame(width: 36, height: CGFloat(localTable.rows.count + 1) * cellHeight + 36)
            .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Editing Functions
    
    /// Switch to a cell - handles both starting fresh and switching from another cell
    /// CRITICAL: Keep keyboard visible during cell switching (like Apple Notes)
    private func switchToCell(row: Int, col: Int, content: String) {
        // If clicking the same cell that's already being edited, do nothing
        if let current = editingCell, current.row == row, current.col == col {
            return
        }
        
        // If another cell is being edited, commit it first BUT keep isEditing true
        if editingCell != nil {
            commitEditKeepingKeyboard()
        }
        
        // Start editing the new cell - don't toggle isEditing off
        editingCell = (row, col)
        editingText = content
        
        // Ensure keyboard stays visible
        if !isEditing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isEditing = true
            }
        }
        
        // Removed haptic - too frequent during cell navigation
    }
    
    /// Commit current edit but keep keyboard visible for seamless cell switching
    private func commitEditKeepingKeyboard() {
        guard let cell = editingCell else { return }
        
        if cell.row == -1 {
            // Editing header
            if cell.col < localTable.headers.count {
                localTable.headers[cell.col] = editingText
            }
        } else {
            // Editing data cell
            if cell.row < localTable.rows.count {
                // Ensure row has enough columns
                while localTable.rows[cell.row].count <= cell.col {
                    localTable.rows[cell.row].append("")
                }
                localTable.rows[cell.row][cell.col] = editingText
            }
        }
        
        // Clear cell reference but DON'T set isEditing = false
        editingCell = nil
        editingText = ""
        // isEditing stays true to keep keyboard visible
        updateTableInContent()
    }
    
    private func commitEdit(keepEditing: Bool = false) {
        guard let cell = editingCell else { return }
        
        if cell.row == -1 {
            // Editing header
            if cell.col < localTable.headers.count {
                localTable.headers[cell.col] = editingText
            }
        } else {
            // Editing data cell
            if cell.row < localTable.rows.count {
                // Ensure row has enough columns
                while localTable.rows[cell.row].count <= cell.col {
                    localTable.rows[cell.row].append("")
                }
                localTable.rows[cell.row][cell.col] = editingText
            }
        }
        
        if !keepEditing {
            editingCell = nil
            editingText = ""
            isEditing = false
        }
        updateTableInContent()
    }
    
    private func moveToNextCell() {
        guard let currentCell = editingCell else { return }
        
        // Commit current edit BUT keep keyboard visible
        commitEditKeepingKeyboard()
        
        // Move to next cell below (same column, next row)
        var nextRow: Int
        var nextContent: String
        
        if currentCell.row == -1 {
            // Currently editing header, move to first data row
            if !localTable.rows.isEmpty {
                nextRow = 0
                nextContent = currentCell.col < localTable.rows[0].count ? localTable.rows[0][currentCell.col] : ""
            } else {
                // No rows, add one
                addRow()
                nextRow = 0
                nextContent = ""
            }
        } else {
            // Currently editing data cell, move to next row
            nextRow = currentCell.row + 1
            if nextRow < localTable.rows.count {
                nextContent = currentCell.col < localTable.rows[nextRow].count ? localTable.rows[nextRow][currentCell.col] : ""
            } else {
                // No more rows, add a new one
                addRow()
                nextContent = ""
            }
        }
        
        // Switch to next cell - keyboard stays visible
        editingCell = (nextRow, currentCell.col)
        editingText = nextContent
        // isEditing is already true, no need to change it
    }
    
    private func addRow() {
        // Removed haptic - too frequent
        let newRow = Array(repeating: "", count: localTable.headers.count)
        localTable.rows.append(newRow)
        updateTableInContent()
    }
    
    private func addColumn() {
        // Removed haptic - too frequent
        localTable.headers.append("Header")
        for i in 0..<localTable.rows.count {
            localTable.rows[i].append("")
        }
        updateTableInContent()
    }
    
    // MARK: - Delete Functions
    
    @State private var showingDeleteMenu = false
    @State private var deleteMenuRow: Int? = nil
    @State private var deleteMenuCol: Int? = nil
    
    private func showDeleteMenu(rowIndex: Int, colIndex: Int) {
        // Removed haptic - menu appearance provides visual feedback
        deleteMenuRow = rowIndex
        deleteMenuCol = colIndex
        showingDeleteMenu = true
    }
    
    private func showDeleteColumnMenu(colIndex: Int) {
        // Removed haptic - menu appearance provides visual feedback
        deleteMenuRow = nil
        deleteMenuCol = colIndex
        showingDeleteMenu = true
    }
    
    private func deleteRow(at index: Int) {
        guard index >= 0 && index < localTable.rows.count else { return }
        // Removed haptic - kept only for destructive actions that aren't undoable
        localTable.rows.remove(at: index)
        // Clear editing cell if it was in the deleted row
        if let editing = editingCell, editing.row == index {
            editingCell = nil
            isEditing = false
        } else if let editing = editingCell, editing.row > index {
            // Adjust row index if editing a row after the deleted one
            editingCell = (editing.row - 1, editing.col)
        }
        updateTableInContent()
    }
    
    private func deleteColumn(at index: Int) {
        guard index >= 0 && index < localTable.headers.count && localTable.headers.count > 1 else { return }
        HapticManager.shared.delete()
        localTable.headers.remove(at: index)
        for i in 0..<localTable.rows.count {
            if index < localTable.rows[i].count {
                localTable.rows[i].remove(at: index)
            }
        }
        // Clear editing cell if it was in the deleted column
        if let editing = editingCell, editing.col == index {
            editingCell = nil
            isEditing = false
        } else if let editing = editingCell, editing.col > index {
            // Adjust column index if editing a column after the deleted one
            editingCell = (editing.row, editing.col - 1)
        }
        updateTableInContent()
    }
    
    private func updateTableInContent() {
        // Update raw markdown
        var lines: [String] = []
        lines.append("| " + localTable.headers.joined(separator: " | ") + " |")
        lines.append("|" + localTable.headers.map { _ in "---" }.joined(separator: "|") + "|")
        for row in localTable.rows {
            var paddedRow = row
            while paddedRow.count < localTable.headers.count {
                paddedRow.append("")
            }
            lines.append("| " + paddedRow.prefix(localTable.headers.count).joined(separator: " | ") + " |")
        }
        localTable.rawMarkdown = lines.joined(separator: "\n")
        
        onTableUpdated?(localTable)
    }
}

// MARK: - Trailing Text Editor
// Special editor for typing after tables that properly accumulates text
// The key insight: we maintain a separate text buffer and sync it with content

struct TrailingTextEditor: View {
    @Binding var content: String
    var onEditingChanged: () -> Void
    var onDateDetected: ((Date, String) -> Void)?
    var onTodoInsert: (() -> Void)?
    var isReceiptNote: Bool
    
    @State private var localText: String = ""
    @State private var contentSnapshot: String = ""
    
    var body: some View {
        UnifiedNoteEditor(
            text: $localText,
            onEditingChanged: {
                syncToContent()
                onEditingChanged()
            },
            onDateDetected: onDateDetected,
            onTodoInsert: onTodoInsert,
            isReceiptNote: isReceiptNote
        )
        .onAppear {
            // Take snapshot of content when editor appears
            contentSnapshot = content
        }
    }
    
    private func syncToContent() {
        // Build the new content: original snapshot + properly formatted trailing text
        if localText.isEmpty {
            // No trailing text, keep original content
            content = contentSnapshot
        } else {
            // Add proper spacing before trailing text
            if contentSnapshot.isEmpty {
                content = localText
            } else if contentSnapshot.hasSuffix("\n\n") {
                content = contentSnapshot + localText
            } else if contentSnapshot.hasSuffix("\n") {
                content = contentSnapshot + "\n" + localText
            } else {
                content = contentSnapshot + "\n\n" + localText
            }
        }
    }
}

// MARK: - Hybrid Note Content View

struct HybridNoteContentView: View {
    @Binding var content: String
    var isContentFocused: FocusState<Bool>.Binding?
    var onEditingChanged: () -> Void
    var onDateDetected: ((Date, String) -> Void)?
    var onTodoInsert: (() -> Void)?
    var isReceiptNote: Bool
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let focusBinding: Binding<Bool>? = isContentFocused.map { binding in
                Binding(get: { binding.wrappedValue }, set: { binding.wrappedValue = $0 })
            }
            let items = MarkdownTableParser.parse(content)
            let hasTables = items.contains {
                if case .table = $0 { return true }
                return false
            }
            
            if !hasTables {
                // Plain-text note path: keep one editor instance to avoid cursor jumps/glitches.
                UnifiedNoteEditor(
                    text: $content,
                    onEditingChanged: onEditingChanged,
                    onDateDetected: onDateDetected,
                    onTodoInsert: onTodoInsert,
                    isReceiptNote: isReceiptNote,
                    isFocused: focusBinding
                )
                .frame(minHeight: 100)
            } else {
                // Mixed content
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    switch item {
                    case .text(let text):
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            textSectionView(text: text, index: index)
                        }
                    case .table(let table):
                        InlineTableView(
                            table: table,
                            onTableUpdated: { updatedTable in
                                updateTable(oldTable: table, newTable: updatedTable)
                            },
                            onDelete: {
                                deleteTable(table)
                            }
                        )
                        .padding(.vertical, 4)
                    }
                }
                
                // Always show an empty editor at the end for adding more content
                TrailingTextEditor(
                    content: $content,
                    onEditingChanged: onEditingChanged,
                    onDateDetected: onDateDetected,
                    onTodoInsert: onTodoInsert,
                    isReceiptNote: isReceiptNote
                )
                .frame(minHeight: 50)
            }
        }
    }
    
    private func textSectionView(text: String, index: Int) -> some View {
        // For text sections, we need to track edits
        let binding = Binding<String>(
            get: { text },
            set: { newText in
                updateTextSection(at: index, with: newText)
            }
        )
        
        return UnifiedNoteEditor(
            text: binding,
            onEditingChanged: onEditingChanged,
            onDateDetected: onDateDetected,
            onTodoInsert: onTodoInsert,
            isReceiptNote: isReceiptNote
        )
    }
    
    private func updateTextSection(at index: Int, with newText: String) {
        var items = MarkdownTableParser.parse(content)
        guard index < items.count else { return }
        
        // Rebuild content with updated text section
        var newContent = ""
        for (i, item) in items.enumerated() {
            switch item {
            case .text(let text):
                if i == index {
                    newContent += newText
                } else {
                    newContent += text
                }
            case .table(let table):
                newContent += table.rawMarkdown
            }
            if i < items.count - 1 {
                newContent += "\n"
            }
        }
        content = newContent
    }
    
    private func updateTable(oldTable: MarkdownTable, newTable: MarkdownTable) {
        // Replace old table markdown with new table markdown
        content = content.replacingOccurrences(of: oldTable.rawMarkdown, with: newTable.rawMarkdown)
    }
    
    private func deleteTable(_ table: MarkdownTable) {
        // Remove table markdown from content
        content = content.replacingOccurrences(of: table.rawMarkdown, with: "")
        // Clean up extra newlines
        while content.contains("\n\n\n") {
            content = content.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        HapticManager.shared.success()
    }
}

#Preview {
    let sampleContent = """
    This is some text before the table.
    
    | Name | Age | City |
    |---|---|---|
    | John | 25 | NYC |
    | Jane | 30 | LA |
    
    And this is text after the table.
    """
    
    return HybridNoteContentView(
        content: .constant(sampleContent),
        onEditingChanged: {},
        isReceiptNote: false
    )
    .padding()
    .preferredColorScheme(.dark)
}
