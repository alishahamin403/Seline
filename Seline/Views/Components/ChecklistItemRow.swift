import SwiftUI

struct ChecklistItemRow: View {
    @Binding var item: ChecklistItem
    @FocusState private var isFocused: Bool
    var onReturn: () -> Void
    var onBackspaceEmpty: () -> Void
    var onDelete: () -> Void
    var onToggleCompletion: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: {
                onToggleCompletion()
            }) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(item.isCompleted ? .gray : .gray)
            }
            .buttonStyle(.plain)

            // Text input
            TextField("To-do item", text: $item.text)
                .font(.system(.body))
                .strikethrough(item.isCompleted, color: .gray)
                .foregroundColor(item.isCompleted ? .gray : .primary)
                .opacity(1)
                .focused($isFocused)
                .onSubmit {
                    onReturn()
                }
                .onChange(of: item.text) { _ in
                    // Text changes are tracked, empty items will be filtered on save
                }

            Spacer()

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 0)
        .onAppear {
            // Auto-focus if item is newly created and empty
            if item.text.isEmpty {
                isFocused = true
            }
        }
    }
}

#Preview {
    @State var item = ChecklistItem(text: "Sample to-do")
    return ChecklistItemRow(
        item: $item,
        onReturn: {},
        onBackspaceEmpty: {},
        onDelete: {},
        onToggleCompletion: {}
    )
        .padding()
}
