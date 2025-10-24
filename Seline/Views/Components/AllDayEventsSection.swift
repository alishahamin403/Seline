import SwiftUI

struct AllDayEventsSection: View {
    let tasks: [TaskItem]
    let date: Date
    let onTapTask: (TaskItem) -> Void
    let onToggleCompletion: (TaskItem) -> Void

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var tagManager = TagManager.shared

    private var allDayTasks: [TaskItem] {
        tasks.filter { $0.scheduledTime == nil }
    }

    private func getTaskColor(_ task: TaskItem) -> Color {
        if let tagId = task.tagId, let tag = tagManager.getTag(by: tagId) {
            return tag.color
        }
        return Color.blue // Personal (default) color
    }

    private var accentColor: Color {
        colorScheme == .dark ?
            Color(red: 0.40, green: 0.65, blue: 0.80) : // #66A5C6
            Color(red: 0.20, green: 0.34, blue: 0.40)   // #345766
    }

    var body: some View {
        if !allDayTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(allDayTasks) { task in
                            allDayEventCard(task: task)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 8)
            .background(Color.clear)
        }
    }

    private func allDayEventCard(task: TaskItem) -> some View {
        Button(action: {
            HapticManager.shared.cardTap()
            onTapTask(task)
        }) {
            let taskColor = getTaskColor(task)
            let circleColor: Color = colorScheme == .dark ? Color.white : Color.black

            HStack(spacing: 8) {
                // Completion checkbox
                Button(action: {
                    HapticManager.shared.selection()
                    onToggleCompletion(task)
                }) {
                    let isCompleted = task.isCompletedOn(date: date)
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(circleColor)
                }
                .buttonStyle(PlainButtonStyle())

                // Task title
                let isCompleted = task.isCompletedOn(date: date)
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(
                        colorScheme == .dark ? Color.white : Color.black
                    )
                    .strikethrough(isCompleted, color: colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .lineLimit(1)

                // Indicators
                HStack(spacing: 4) {
                    if task.hasEmailAttachment {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 9))
                            .foregroundColor(circleColor.opacity(0.7))
                    }

                    if task.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 9))
                            .foregroundColor(circleColor.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        taskColor.opacity(colorScheme == .dark ? 0.7 : 0.65)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(taskColor.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack {
        AllDayEventsSection(
            tasks: [
                TaskItem(title: "Review quarterly reports", weekday: .monday),
                TaskItem(title: "Call mom", weekday: .monday),
                TaskItem(title: "Buy groceries", weekday: .monday)
            ],
            date: Date(),
            onTapTask: { _ in },
            onToggleCompletion: { _ in }
        )
    }
    .background(Color.shadcnBackground(.light))
}
