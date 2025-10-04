import SwiftUI

struct TaskRow: View {
    let task: TaskItem
    let onToggleCompletion: () -> Void
    let onDelete: () -> Void
    let onDeleteRecurringSeries: () -> Void
    let onMakeRecurring: () -> Void
    let onEdit: (() -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @State private var dragOffset: CGSize = .zero

    private var blueColor: Color {
        colorScheme == .dark ?
            Color(red: 0.518, green: 0.792, blue: 0.914) : // #84cae9 (light blue for dark mode)
            Color(red: 0.20, green: 0.34, blue: 0.40)     // #345766 (dark blue for light mode)
    }

    private var checkboxColor: Color {
        if task.isCompleted {
            return blueColor
        }
        return colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
    }

    private var grayTimeColor: Color {
        colorScheme == .dark ?
            Color.white.opacity(0.6) :
            Color.black.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggleCompletion()
                }
            }) {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .foregroundColor(checkboxColor)
                    .font(.system(size: 18, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())

            // Task title with recurring indicator
            HStack(spacing: 6) {
                Text(task.title)
                    .font(.shadcnTextSm)
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .strikethrough(task.isCompleted, color: blueColor)
                    .animation(.easeInOut(duration: 0.2), value: task.isCompleted)

                // Recurring indicator
                if task.isRecurring {
                    Image(systemName: "repeat")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(blueColor.opacity(0.7))
                }
            }

            Spacer()

            // Time display
            if !task.formattedTime.isEmpty {
                Text(task.formattedTime)
                    .font(.shadcnTextXs)
                    .foregroundColor(grayTimeColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.clear)
        .offset(x: dragOffset.width)
        .contextMenu {
            // Show edit option for all tasks
            if let onEdit = onEdit {
                Button(action: onEdit) {
                    if task.isRecurring {
                        Label("Edit Recurring Event", systemImage: "pencil")
                    } else if task.parentRecurringTaskId != nil {
                        Label("Edit This Instance", systemImage: "pencil")
                    } else {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }

            // Show different delete options based on task type
            if task.isRecurring || task.parentRecurringTaskId != nil {
                // For recurring tasks, show both options
                Button(action: onDelete) {
                    Label("Delete This Task", systemImage: "trash")
                }

                Button(action: onDeleteRecurringSeries) {
                    Label("Delete All Recurring", systemImage: "trash.fill")
                }
            } else {
                // For regular tasks, show single delete option
                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }

            // Only show "Make Recurring" for non-recurring tasks
            if !task.isRecurring && task.parentRecurringTaskId == nil {
                Button(action: onMakeRecurring) {
                    Label("Make Recurring", systemImage: "repeat")
                }
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow left swipe (negative width)
                    dragOffset = CGSize(width: min(0, value.translation.width), height: 0)
                }
                .onEnded { value in
                    withAnimation(.spring()) {
                        if value.translation.width < -100 {
                            // Swipe far enough to delete
                            onDelete()
                        } else {
                            // Reset position
                            dragOffset = .zero
                        }
                    }
                }
        )
        .animation(.spring(), value: dragOffset)
    }
}

#Preview {
    VStack(spacing: 12) {
        TaskRow(
            task: TaskItem(title: "Sample completed task", weekday: .monday),
            onToggleCompletion: {},
            onDelete: {},
            onDeleteRecurringSeries: {},
            onMakeRecurring: {},
            onEdit: {}
        )

        TaskRow(
            task: TaskItem(title: "Sample incomplete task", weekday: .monday),
            onToggleCompletion: {},
            onDelete: {},
            onDeleteRecurringSeries: {},
            onMakeRecurring: {},
            onEdit: {}
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}