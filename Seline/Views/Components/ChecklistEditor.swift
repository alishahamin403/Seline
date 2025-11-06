import SwiftUI

struct ChecklistEditor: View {
    @Binding var checklistItems: [ChecklistItem]
    @FocusState private var focusedItemId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Checklist items
            VStack(spacing: 4) {
                ForEach(checklistItems, id: \.id) { item in
                    ChecklistItemRow(
                        item: .init(
                            get: { checklistItems.first(where: { $0.id == item.id }) ?? item },
                            set: { newItem in
                                if let index = checklistItems.firstIndex(where: { $0.id == item.id }) {
                                    checklistItems[index] = newItem
                                }
                            }
                        ),
                        onReturn: {
                            handleReturn(for: item.id)
                        },
                        onBackspaceEmpty: {
                            handleBackspaceEmpty(for: item.id)
                        },
                        onDelete: {
                            handleDelete(for: item.id)
                        },
                        onToggleCompletion: {
                            handleToggleCompletion(for: item.id)
                        }
                    )
                    .focused($focusedItemId, equals: item.id)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleReturn(for itemId: UUID) {
        let newItem = ChecklistItem()
        checklistItems.append(newItem)

        // Small delay to ensure item is rendered before focusing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedItemId = newItem.id
        }
    }

    private func handleBackspaceEmpty(for itemId: UUID) {
        // Find the index of the item being deleted
        if let index = checklistItems.firstIndex(where: { $0.id == itemId }) {
            checklistItems.remove(at: index)

            // Focus on previous item if it exists
            let previousIndex = index > 0 ? index - 1 : 0
            if previousIndex < checklistItems.count && !checklistItems.isEmpty {
                focusedItemId = checklistItems[previousIndex].id
            }
        }
    }

    private func handleDelete(for itemId: UUID) {
        if let index = checklistItems.firstIndex(where: { $0.id == itemId }) {
            checklistItems.remove(at: index)

            // Focus on next item or previous if we deleted the last one
            let nextIndex = index < checklistItems.count ? index : checklistItems.count - 1
            if nextIndex >= 0 && nextIndex < checklistItems.count {
                focusedItemId = checklistItems[nextIndex].id
            }
        }
    }

    private func handleToggleCompletion(for itemId: UUID) {
        if let index = checklistItems.firstIndex(where: { $0.id == itemId }) {
            checklistItems[index].isCompleted.toggle()
            if checklistItems[index].isCompleted {
                checklistItems[index].completedAt = Date()
            } else {
                checklistItems[index].completedAt = nil
            }
        }
    }

    private func addNewItem() {
        let newItem = ChecklistItem()
        checklistItems.append(newItem)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedItemId = newItem.id
        }
    }
}

#Preview {
    @State var items = [
        ChecklistItem(text: "Buy groceries"),
        ChecklistItem(text: "Call the dentist", isCompleted: true)
    ]

    return ChecklistEditor(checklistItems: $items)
        .padding()
}
