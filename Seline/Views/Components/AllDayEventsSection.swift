import SwiftUI

struct AllDayEventsSection: View {
    let tasks: [TaskItem]
    let date: Date
    let onTapTask: (TaskItem) -> Void
    let onToggleCompletion: (TaskItem) -> Void

    @Environment(\.colorScheme) var colorScheme

    private var allDayTasks: [TaskItem] {
        tasks.filter { $0.scheduledTime == nil }
    }

    private var accentColor: Color {
        colorScheme == .dark ?
            Color(red: 0.40, green: 0.65, blue: 0.80) : // #66A5C6
            Color(red: 0.20, green: 0.34, blue: 0.40)   // #345766
    }

    var body: some View {
        if !allDayTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("All Day")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(
                        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)
                    )
                    .padding(.horizontal, 20)

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
            HStack(spacing: 8) {
                // Completion checkbox
                Button(action: {
                    HapticManager.shared.selection()
                    onToggleCompletion(task)
                }) {
                    let isCompleted = task.isCompletedOn(date: date)
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(accentColor)
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
                            .foregroundColor(accentColor.opacity(0.7))
                    }

                    if task.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 9))
                            .foregroundColor(accentColor.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        colorScheme == .dark ?
                            Color.white.opacity(0.08) : Color.black.opacity(0.05)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(accentColor.opacity(0.3), lineWidth: 1)
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
