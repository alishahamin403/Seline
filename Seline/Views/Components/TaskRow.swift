import SwiftUI

struct TaskRow: View {
    let task: TaskItem
    let date: Date? // Date this task is being displayed for (used for recurring tasks)
    let onToggleCompletion: () -> Void
    let onDelete: () -> Void
    let onDeleteRecurringSeries: () -> Void
    let onMakeRecurring: () -> Void
    let onView: (() -> Void)?
    let onEdit: (() -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @State private var dragOffset: CGSize = .zero

    private var blueColor: Color {
        colorScheme == .dark ?
            Color.white :
            Color.black
    }

    // Check if task is completed on the specific date (for recurring tasks)
    private var isTaskCompleted: Bool {
        if let date = date {
            return task.isCompletedOn(date: date)
        }
        return task.isCompleted
    }

    private var checkboxColor: Color {
        if isTaskCompleted {
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
                Image(systemName: isTaskCompleted ? "checkmark.square.fill" : "square")
                    .foregroundColor(checkboxColor)
                    .font(.system(size: 18, weight: .medium))
            }
            .buttonStyle(PlainButtonStyle())

            // Task title with recurring indicator - tappable to view details
            Button(action: {
                onView?()
            }) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .strikethrough(isTaskCompleted, color: blueColor)
                        .animation(.easeInOut(duration: 0.2), value: isTaskCompleted)

                    // Recurring indicator
                    if task.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(blueColor.opacity(0.7))
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

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
        .contentShape(Rectangle()) // Makes entire row area tappable
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
            date: Date(),
            onToggleCompletion: {},
            onDelete: {},
            onDeleteRecurringSeries: {},
            onMakeRecurring: {},
            onView: {},
            onEdit: {}
        )

        TaskRow(
            task: TaskItem(title: "Sample incomplete task", weekday: .monday),
            date: Date(),
            onToggleCompletion: {},
            onDelete: {},
            onDeleteRecurringSeries: {},
            onMakeRecurring: {},
            onView: {},
            onEdit: {}
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}