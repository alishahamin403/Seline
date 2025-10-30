import SwiftUI

struct AllDayEventsSection: View {
    let tasks: [TaskItem]
    let date: Date
    let onTapTask: (TaskItem) -> Void
    let onToggleCompletion: (TaskItem) -> Void

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var tagManager = TagManager.shared

    private var allDayTasks: [TaskItem] {
        let filtered = tasks.filter { $0.scheduledTime == nil }

        // Deduplicate tasks with the same title - keep only the first occurrence
        // This prevents duplicate recurring events from showing on the same date
        var seenTitles = Set<String>()
        var deduplicated: [TaskItem] = []

        for task in filtered {
            let titleKey = task.title.lowercased()
            if !seenTitles.contains(titleKey) {
                deduplicated.append(task)
                seenTitles.insert(titleKey)
            }
        }

        return deduplicated
    }

    private func getTaskColor(_ task: TaskItem) -> Color {
        let filterType = TimelineEventColorManager.filterType(from: task)
        return TimelineEventColorManager.timelineEventAccentColor(
            filterType: filterType,
            colorScheme: colorScheme
        )
    }

    private var accentColor: Color {
        colorScheme == .dark ?
            Color.white : // White in dark mode
            Color.black   // Black in light mode
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
            .padding(.vertical, 4)
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
                        taskColor.opacity(colorScheme == .dark ? 0.2 : 0.15)
                    )
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
