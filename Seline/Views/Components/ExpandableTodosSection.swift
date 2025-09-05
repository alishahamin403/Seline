import SwiftUI

struct ExpandableTodosSection: View {
    let todos: [TodoItem]
    @Binding var isExpanded: Bool
    let onAddTodo: () -> Void
    let onAddTodoWithVoice: () -> Void
    let onViewAll: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            if todos.isEmpty {
                emptyStateView
            } else {
                todosPreviewList
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: colorScheme == .light ? Color.black.opacity(0.06) : Color.clear,
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
        .onTapGesture {
            onViewAll()
        }
    }

    private var headerView: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            IconInBoxView(systemName: "checkmark.circle.fill")
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Todos")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("\(todos.count) todo\(todos.count == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()

            Button(action: onAddTodoWithVoice) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            .padding(.trailing, 8)

            Button(action: onAddTodo) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            .padding(.trailing, 8)
            
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
            
            Text("No todos for today")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
    }

    private var todosPreviewList: some View {
        VStack(spacing: 0) {
            ForEach(todos) { todo in
                TodoPreviewRow(todo: todo)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

struct ExpandableTodosSection_Previews: PreviewProvider {
    static var previews: some View {
        ExpandableTodosSection(
            todos: [],
            isExpanded: .constant(true),
            onAddTodo: {},
            onAddTodoWithVoice: {},
            onViewAll: {}
        )
    }
}