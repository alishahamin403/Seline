import SwiftUI

struct TodoListEditorView: View {
    @Binding var todoList: NoteTodoList
    @Environment(\.colorScheme) var colorScheme

    @State private var editingItemIndex: Int? = nil
    @State private var editingText: String = ""
    @FocusState private var isEditingFocused: Bool
    @State private var isTodoListActive: Bool = false

    var onTodoUpdate: (NoteTodoList) -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Todo list toolbar - only show when active
            if isTodoListActive {
                todoToolbar
            }

            // Todo items
            VStack(spacing: 8) {
                ForEach(Array(todoList.items.enumerated()), id: \.element.id) { index, item in
                    todoItemView(index: index, item: item)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3), lineWidth: 1)
        )
        .padding(.vertical, 8)
        .onTapGesture {
            // Activate todo list on tap
            withAnimation {
                isTodoListActive = true
            }
        }
    }

    // MARK: - Toolbar

    private var todoToolbar: some View {
        HStack(spacing: 8) {
            // Add item button
            Button(action: {
                HapticManager.shared.buttonTap()
                todoList.addItem("")
                onTodoUpdate(todoList)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                    Text("Add")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                )
            }
            .disabled(todoList.items.count >= 50)

            // Progress indicator
            Text("\(todoList.completionPercentage)% Complete")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

            Spacer()

            // Delete button
            if let onDelete = onDelete {
                Button(action: {
                    HapticManager.shared.delete()
                    onDelete()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.red.opacity(0.1))
                        )
                }
            }

            // Done button
            Button(action: {
                // Save current edit before closing
                saveCurrentEdit()

                withAnimation {
                    isTodoListActive = false
                }
                isEditingFocused = false
            }) {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
        )
    }

    // MARK: - Helper Functions

    private func saveCurrentEdit() {
        // Only save if we have an item being edited
        guard let currentIndex = editingItemIndex else { return }

        // Update the item with the current text
        todoList.updateItem(at: currentIndex, text: editingText)
        onTodoUpdate(todoList)

        // Clear editing state
        editingItemIndex = nil
    }

    // MARK: - Todo Item View

    private func todoItemView(index: Int, item: TodoItem) -> some View {
        HStack(spacing: 12) {
            // Checkbox button
            Button(action: {
                // Save current edit before toggling
                saveCurrentEdit()

                HapticManager.shared.selection()
                todoList.toggleItem(at: index)
                onTodoUpdate(todoList)
            }) {
                ZStack {
                    Circle()
                        .stroke(
                            item.isCompleted ?
                                (colorScheme == .dark ? Color.green : Color.green) :
                                (colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.3)),
                            lineWidth: 1.5
                        )
                        .frame(width: 18, height: 18)

                    if item.isCompleted {
                        Circle()
                            .fill(colorScheme == .dark ? Color.green : Color.green)
                            .frame(width: 18, height: 18)

                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Todo text
            if editingItemIndex == index {
                TextField("Enter todo...", text: $editingText, onCommit: {
                    saveCurrentEdit()
                })
                .focused($isEditingFocused)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .onAppear {
                    editingText = item.text
                    isEditingFocused = true
                }
            } else {
                Text(item.text.isEmpty ? "Tap to edit" : item.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(
                        item.isCompleted ?
                            (colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4)) :
                            (colorScheme == .dark ? .white : .black)
                    )
                    .onTapGesture {
                        // Save current edit before switching to new item
                        saveCurrentEdit()

                        // Start editing new item
                        editingItemIndex = index
                        editingText = item.text
                    }
            }

            Spacer()

            // Delete item button (only show when editing or active)
            if isTodoListActive && todoList.items.count > 1 {
                Button(action: {
                    // Save current edit before deleting
                    saveCurrentEdit()

                    HapticManager.shared.delete()
                    todoList.removeItem(at: index)
                    onTodoUpdate(todoList)
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        TodoListEditorView(
            todoList: .constant(NoteTodoList(items: [
                TodoItem(text: "Buy groceries", isCompleted: false),
                TodoItem(text: "Call mom", isCompleted: true),
                TodoItem(text: "Finish project", isCompleted: false)
            ])),
            onTodoUpdate: { _ in }
        )
        .padding()
    }
    .background(Color.black)
}
