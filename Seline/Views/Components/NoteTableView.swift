import SwiftUI
import UIKit

// MARK: - Table Cell TextField for NoteTableView
// UIKit wrapper for proper single-tap cell switching

struct NoteTableCellTextField: UIViewRepresentable {
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
        if textField.text != text {
            textField.text = text
        }

        // More aggressive focus management to prevent keyboard dismissal
        if isEditing.wrappedValue && !textField.isFirstResponder {
            // Try immediately first, then with a slight delay as backup
            textField.becomeFirstResponder()
            if !textField.isFirstResponder {
                DispatchQueue.main.async {
                    textField.becomeFirstResponder()
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NoteTableCellTextField
        
        init(_ parent: NoteTableCellTextField) {
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
    }
}

// MARK: - Table Template Picker Sheet

struct TableTemplatePickerSheet: View {
    @Binding var isPresented: Bool
    var onSelectTemplate: (TableTemplate) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Header description
                    Text("Choose a template to get started quickly, or create a blank table")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    
                    // Template grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {
                        ForEach(TableTemplate.allTemplates) { template in
                            templateCard(template)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationTitle("Insert Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(primaryTextColor)
                }
            }
        }
    }
    
    private func templateCard(_ template: TableTemplate) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            onSelectTemplate(template)
            isPresented = false
        }) {
            VStack(alignment: .leading, spacing: 10) {
                // Icon and name
                HStack(spacing: 10) {
                    Image(systemName: template.icon)
                        .font(FontManager.geist(size: 18, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(FontManager.geist(size: 14, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                        
                        Text(template.description)
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                    }
                    
                    Spacer()
                }
                
                // Mini preview
                tablePreview(template)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(cardBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func tablePreview(_ template: TableTemplate) -> some View {
        let maxRows = min(template.rows.count, 3)
        let maxCols = min(template.rows.first?.count ?? 0, 4)
        
        return VStack(spacing: 1) {
            ForEach(0..<maxRows, id: \.self) { rowIndex in
                previewRow(template: template, rowIndex: rowIndex, maxCols: maxCols)
            }
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 0.5)
        )
    }
    
    private func previewRow(template: TableTemplate, rowIndex: Int, maxCols: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<maxCols, id: \.self) { colIndex in
                previewCell(content: template.rows[rowIndex][colIndex], isHeader: rowIndex == 0)
            }
        }
    }
    
    private func previewCell(content: String, isHeader: Bool) -> some View {
        Text(content.isEmpty ? " " : content)
            .font(FontManager.geist(size: 8, weight: isHeader ? .semibold : .regular))
            .foregroundColor(primaryTextColor.opacity(isHeader ? 0.9 : 0.6))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(
                isHeader
                    ? (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                    : Color.clear
            )
    }
}

// MARK: - Note Table View (Editable Table Block)
// Uses single-tap cell switching like Apple Notes

struct NoteTableView: View {
    @Binding var tableBlock: TableBlock
    var onUpdate: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var editingCell: (row: Int, col: Int)? = nil
    @State private var editingText: String = ""
    @FocusState private var isEditing: Bool
    @State private var showingDeleteMenu = false
    @State private var deleteMenuRow: Int? = nil
    @State private var deleteMenuCol: Int? = nil
    
    private let cellWidth: CGFloat = 100
    private let cellHeight: CGFloat = 44
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }
    
    private var headerBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }
    
    private var cellBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
    }
    
    // Calculate max table width (screen width minus padding)
    private var maxTableWidth: CGFloat {
        UIScreen.main.bounds.width - 48 // Account for padding
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(Array(tableBlock.rows.enumerated()), id: \.offset) { rowIndex, row in
                    tableRow(rowIndex: rowIndex, row: row)
                }
                
                // Add row button
                addRowButton
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .frame(maxWidth: maxTableWidth)
        .padding(.vertical, 8)
    }
    
    private func tableRow(rowIndex: Int, row: [TableCell]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                cellView(rowIndex: rowIndex, colIndex: colIndex, cell: cell)
            }
            
            // Add column button (only show on first row)
            if rowIndex == 0 {
                addColumnButton
            } else {
                // Spacer to align with add column button
                Color.clear
                    .frame(width: 36, height: cellHeight)
            }
        }
    }
    
    private func cellView(rowIndex: Int, colIndex: Int, cell: TableCell) -> some View {
        let isHeader = rowIndex == 0
        let isEditingThis = editingCell?.row == rowIndex && editingCell?.col == colIndex
        
        return ZStack {
            // Background (always visible)
            Rectangle()
                .fill(isHeader ? headerBackgroundColor : cellBackgroundColor)
                .frame(width: cellWidth, height: cellHeight)
            
            if isEditingThis {
                // Editing mode - show TextField
                NoteTableCellTextField(
                    text: $editingText,
                    isEditing: $isEditing,
                    placeholder: isHeader ? "Header" : "",
                    font: .systemFont(ofSize: 14, weight: isHeader ? .semibold : .regular),
                    textColor: colorScheme == .dark ? .white : .black,
                    onCommit: { moveToNextCell() },
                    onTextChange: { commitEdit(keepEditing: true) }
                )
                .frame(width: cellWidth - 20, height: cellHeight - 10)
            } else {
                // Display mode - show Text
                Text(cell.content.isEmpty ? (isHeader ? "Header" : " ") : cell.content)
                    .font(FontManager.geist(size: 14, weight: isHeader ? .semibold : .regular))
                    .foregroundColor(cell.content.isEmpty ? secondaryTextColor : primaryTextColor)
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
            switchToCell(row: rowIndex, col: colIndex, content: cell.content)
        }
        .onLongPressGesture {
            // Long press - show delete menu
            showDeleteMenu(rowIndex: rowIndex, colIndex: colIndex)
        }
        .contextMenu {
            if rowIndex > 0 {
                Button(role: .destructive) {
                    deleteRow(at: rowIndex)
                } label: {
                    Label("Delete Row", systemImage: "trash")
                }
            }
            
            if tableBlock.columnCount > 1 {
                Button(role: .destructive) {
                    deleteColumn(at: colIndex)
                } label: {
                    Label("Delete Column", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete", isPresented: $showingDeleteMenu, titleVisibility: .hidden) {
            if let rowIndex = deleteMenuRow {
                Button("Delete Row", role: .destructive) {
                    deleteRow(at: rowIndex)
                }
            }
            if let colIndex = deleteMenuCol, tableBlock.columnCount > 1 {
                Button("Delete Column", role: .destructive) {
                    deleteColumn(at: colIndex)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    private var addRowButton: some View {
        Button(action: {
            // Removed haptic - too frequent
            tableBlock.addRow()
            onUpdate()
        }) {
            HStack {
                Image(systemName: "plus")
                    .font(FontManager.geist(size: 12, weight: .medium))
                Text("Add Row")
                    .font(FontManager.geist(size: 12, weight: .medium))
            }
            .foregroundColor(secondaryTextColor)
            .frame(width: CGFloat(tableBlock.columnCount) * cellWidth, height: 36)
            .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var addColumnButton: some View {
        Button(action: {
            // Removed haptic - too frequent
            tableBlock.addColumn()
            onUpdate()
        }) {
            Image(systemName: "plus")
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(secondaryTextColor)
                .frame(width: 36, height: cellHeight)
                .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    /// Switch to a cell - handles both starting fresh and switching from another cell
    /// CRITICAL: Keep keyboard visible during cell switching (like Apple Notes)
    private func switchToCell(row: Int, col: Int, content: String) {
        // If clicking the same cell that's already being edited, do nothing
        if let current = editingCell, current.row == row, current.col == col {
            return
        }

        // Save current content if we were editing another cell
        // IMPORTANT: Don't clear editingCell to nil - this causes keyboard to dismiss
        if let current = editingCell {
            tableBlock.updateCell(row: current.row, column: current.col, content: editingText)
            onUpdate()
        }

        // Switch to the new cell atomically - never set editingCell to nil
        editingCell = (row, col)
        editingText = content

        // Ensure keyboard stays visible - set immediately without delay
        if !isEditing {
            isEditing = true
        }

        // Removed haptic - too frequent during cell navigation
    }
    
    /// Commit current edit but keep keyboard visible for seamless cell switching
    private func commitEditKeepingKeyboard() {
        guard let cell = editingCell else { return }
        tableBlock.updateCell(row: cell.row, column: cell.col, content: editingText)
        
        // Clear cell reference but DON'T set isEditing = false
        editingCell = nil
        editingText = ""
        // isEditing stays true to keep keyboard visible
        onUpdate()
    }
    
    private func commitEdit(keepEditing: Bool = false) {
        guard let cell = editingCell else { return }
        tableBlock.updateCell(row: cell.row, column: cell.col, content: editingText)
        
        if !keepEditing {
            editingCell = nil
            editingText = ""
            isEditing = false
        }
        onUpdate()
    }
    
    private func moveToNextCell() {
        guard let currentCell = editingCell else { return }

        // Save current cell content first
        tableBlock.updateCell(row: currentCell.row, column: currentCell.col, content: editingText)
        onUpdate()

        // Move to next cell below (same column, next row)
        let nextRow = currentCell.row + 1
        var nextContent: String

        if nextRow < tableBlock.rows.count {
            nextContent = tableBlock.rows[nextRow][currentCell.col].content
        } else {
            // No more rows, add a new one and move there
            tableBlock.addRow()
            onUpdate()
            nextContent = ""
        }

        // Switch to next cell atomically - keyboard stays visible
        let targetRow = nextRow < tableBlock.rows.count ? nextRow : tableBlock.rows.count - 1
        editingCell = (targetRow, currentCell.col)
        editingText = nextContent
        // isEditing is already true, no need to change it
    }
    
    private func showDeleteMenu(rowIndex: Int, colIndex: Int) {
        // Removed haptic - menu provides visual feedback
        deleteMenuRow = rowIndex
        deleteMenuCol = colIndex
        showingDeleteMenu = true
    }
    
    private func deleteRow(at index: Int) {
        tableBlock.deleteRow(at: index)
        // Clear editing cell if it was in the deleted row
        if let editing = editingCell, editing.row == index {
            editingCell = nil
            isEditing = false
        } else if let editing = editingCell, editing.row > index {
            // Adjust row index if editing a row after the deleted one
            editingCell = (editing.row - 1, editing.col)
        }
        onUpdate()
    }
    
    private func deleteColumn(at index: Int) {
        tableBlock.deleteColumn(at: index)
        // Clear editing cell if it was in the deleted column
        if let editing = editingCell, editing.col == index {
            editingCell = nil
            isEditing = false
        } else if let editing = editingCell, editing.col > index {
            // Adjust column index if editing a column after the deleted one
            editingCell = (editing.row, editing.col - 1)
        }
        onUpdate()
    }
}

#Preview {
    VStack {
        TableTemplatePickerSheet(isPresented: .constant(true)) { template in
            print("Selected: \(template.name)")
        }
    }
    .preferredColorScheme(.dark)
}
