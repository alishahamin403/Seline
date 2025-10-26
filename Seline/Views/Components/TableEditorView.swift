import SwiftUI

struct TableEditorView: View {
    @Binding var table: NoteTable
    @Environment(\.colorScheme) var colorScheme

    @State private var editingCell: CellPosition? = nil
    @State private var editingText: String = ""
    @FocusState private var isEditingFocused: Bool
    @State private var isTableActive: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @State private var showControlsPopup: Bool = false
    @State private var isHoveringRightEdge: Bool = false
    @State private var isHoveringBottomEdge: Bool = false

    var onTableUpdate: (NoteTable) -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Table content with sticky header and edge controls
            GeometryReader { geometry in
                ZStack(alignment: .top) {
                    // Main scrollable table
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        VStack(spacing: 0) {
                            ForEach(0..<table.rows, id: \.self) { row in
                                HStack(spacing: 0) {
                                    ForEach(0..<table.columns, id: \.self) { column in
                                        cellView(row: row, column: column)
                                    }
                                }
                            }
                        }
                    }
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: scrollGeometry.frame(in: .named("scroll")).origin.y
                            )
                        }
                    )
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        scrollOffset = value
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            // Check if hovering near right edge (last 20px)
                            isHoveringRightEdge = location.x > geometry.size.width - 20
                            // Check if hovering near bottom edge (last 20px)
                            isHoveringBottomEdge = location.y > geometry.size.height - 20
                        case .ended:
                            isHoveringRightEdge = false
                            isHoveringBottomEdge = false
                        }
                    }

                    // Sticky header (only if headerRow is true and scrolled)
                    if table.headerRow && scrollOffset < 0 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(0..<table.columns, id: \.self) { column in
                                    cellView(row: 0, column: column)
                                }
                            }
                        }
                        .background(colorScheme == .dark ? Color.black : Color.white)
                    }

                    // Floating add column button on right edge
                    if isHoveringRightEdge && table.columns < 10 {
                        VStack {
                            Button(action: {
                                showControlsPopup = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                                    .background(
                                        Circle()
                                            .fill(colorScheme == .dark ? Color.black : Color.white)
                                            .frame(width: 28, height: 28)
                                    )
                            }
                            .frame(height: 40, alignment: .center)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 4)
                        .transition(.opacity)
                    }

                    // Floating add row button on bottom edge
                    if isHoveringBottomEdge && table.rows < 20 {
                        VStack {
                            Spacer()
                            Button(action: {
                                showControlsPopup = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                                    .background(
                                        Circle()
                                            .fill(colorScheme == .dark ? Color.black : Color.white)
                                            .frame(width: 28, height: 28)
                                    )
                            }
                            .frame(height: 40, alignment: .center)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                        .transition(.opacity)
                    }
                }
            }
            .frame(height: 400)
        }
        .onTapGesture {
            isTableActive = true
        }
        .overlay(alignment: .topTrailing) {
            if showControlsPopup {
                TableControlsPopup(
                    canAddRow: table.rows < 20,
                    canAddColumn: table.columns < 10,
                    onAddRow: {
                        table.addRow()
                        onTableUpdate(table)
                        showControlsPopup = false
                    },
                    onAddColumn: {
                        table.addColumn()
                        onTableUpdate(table)
                        showControlsPopup = false
                    },
                    onDeleteTable: {
                        showControlsPopup = false
                        if let onDelete = onDelete {
                            onDelete()
                        }
                    }
                )
                .padding(12)
            }
        }
    }

    // MARK: - Cell View

    @ViewBuilder
    private func cellView(row: Int, column: Int) -> some View {
        let isHeader = row == 0 && table.headerRow
        let cellPosition = CellPosition(row: row, column: column)
        let isEditing = editingCell == cellPosition

        ZStack(alignment: .topLeading) {
            // Cell background
            Rectangle()
                .fill(
                    isHeader ?
                        (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)) :
                        Color.clear
                )

            if isEditing {
                // Editing mode - text field auto-saves on focus loss
                TextEditor(text: $editingText)
                    .font(.system(size: isHeader ? 13 : 12, weight: isHeader ? .semibold : .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .scrollContentBackground(.hidden)
                    .background(
                        isHeader ?
                            (colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)) :
                            (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )
                    .frame(minWidth: 100, minHeight: 40)
                    .padding(4)
                    .focused($isEditingFocused)
                    .onAppear {
                        isEditingFocused = true
                    }
                    .onChange(of: editingText) { newValue in
                        // Save text as user types
                        table.updateCell(row: row, column: column, content: newValue)
                        onTableUpdate(table)
                    }
                    .onChange(of: isEditingFocused) { focused in
                        if !focused && isEditing {
                            finishEditing(row: row, column: column)
                        }
                    }
            } else {
                // Display mode
                Text(table.cellContent(row: row, column: column))
                    .font(.system(size: isHeader ? 13 : 12, weight: isHeader ? .semibold : .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .frame(minWidth: 100, minHeight: 40, alignment: .topLeading)
                    .padding(4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isTableActive = true
                        startEditing(row: row, column: column)
                    }
            }
        }
        .frame(minWidth: 100)
        .overlay(
            Rectangle()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2), lineWidth: 0.5)
        )
        .contextMenu {
            Button {
                if table.rows < 20 {
                    table.addRow()
                    onTableUpdate(table)
                }
            } label: {
                Label("Add Row", systemImage: "plus.rectangle")
            }
            .disabled(table.rows >= 20)

            Button {
                if table.columns < 10 {
                    table.addColumn()
                    onTableUpdate(table)
                }
            } label: {
                Label("Add Column", systemImage: "plus.square")
            }
            .disabled(table.columns >= 10)

            Divider()

            Button(role: .destructive) {
                if table.rows > 1 {
                    table.removeRow(at: row)
                    onTableUpdate(table)
                }
            } label: {
                Label("Delete Row", systemImage: "minus.rectangle")
            }
            .disabled(table.rows <= 1)

            Button(role: .destructive) {
                if table.columns > 1 {
                    table.removeColumn(at: column)
                    onTableUpdate(table)
                }
            } label: {
                Label("Delete Column", systemImage: "minus.square")
            }
            .disabled(table.columns <= 1)
        }
    }

    // MARK: - Editing Functions

    private func startEditing(row: Int, column: Int) {
        HapticManager.shared.buttonTap()
        editingCell = CellPosition(row: row, column: column)
        editingText = table.cellContent(row: row, column: column)
        isEditingFocused = true
    }

    private func finishEditing(row: Int, column: Int) {
        // Finish editing and clear state
        HapticManager.shared.buttonTap()
        editingCell = nil
        editingText = ""
        isEditingFocused = false

        // Keep table active so toolbar remains visible
        // User can tap outside the table to deactivate it
    }

}

// MARK: - Cell Position

struct CellPosition: Equatable {
    let row: Int
    let column: Int
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

#Preview {
    TableEditorView(table: .constant(NoteTable(rows: 3, columns: 3, headerRow: true))) { updatedTable in
        print("Table updated: \(updatedTable.rows)x\(updatedTable.columns)")
    } onDelete: {
        print("Table deleted")
    }
    .padding()
}
