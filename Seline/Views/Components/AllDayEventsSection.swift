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

        // Get the actual colorIndex from the tag for consistent colors
        let tagColorIndex: Int?
        if case .tag(let tagId) = filterType {
            tagColorIndex = tagManager.getTag(by: tagId)?.colorIndex
        } else {
            tagColorIndex = nil
        }

        return TimelineEventColorManager.timelineEventAccentColor(
            filterType: filterType,
            colorScheme: colorScheme,
            tagColorIndex: tagColorIndex
        )
    }
    
    private func getTextColor(_ task: TaskItem) -> Color {
        let filterType = TimelineEventColorManager.filterType(from: task)
        let tagColorIndex: Int?
        if case .tag(let tagId) = filterType {
            tagColorIndex = tagManager.getTag(by: tagId)?.colorIndex
        } else {
            tagColorIndex = nil
        }
        
        if case .tag(_) = filterType, let tagColorIndex = tagColorIndex {
            return TimelineEventColorManager.tagColorTextColor(colorIndex: tagColorIndex, colorScheme: colorScheme)
        }
        return TimelineEventColorManager.timelineEventTextColor(
            filterType: filterType,
            colorScheme: colorScheme,
            tagColorIndex: tagColorIndex
        )
    }

    var body: some View {
        if !allDayTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                // Horizontal scrollable event pills - always visible
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(allDayTasks) { task in
                            allDayEventPill(task: task)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - All Day Event Pill
    
    private func allDayEventPill(task: TaskItem) -> some View {
        Button(action: {
            HapticManager.shared.cardTap()
            onTapTask(task)
        }) {
            let taskColor = getTaskColor(task)
            let textColor = getTextColor(task)
            let isCompleted = task.isCompletedOn(date: date)

            HStack(spacing: 6) {
                // Completion checkbox (hidden for calendar events)
                if !task.isFromCalendar {
                    Button(action: {
                        HapticManager.shared.selection()
                        onToggleCompletion(task)
                    }) {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(textColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Task title
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(textColor)
                    .strikethrough(isCompleted, color: textColor.opacity(0.5))
                    .lineLimit(1)

                // Indicators
                HStack(spacing: 3) {
                    if task.hasEmailAttachment {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 9))
                            .foregroundColor(textColor.opacity(0.7))
                    }

                    if task.isRecurring {
                        Image(systemName: "repeat")
                            .font(.system(size: 9))
                            .foregroundColor(textColor.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(taskColor)
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
    .background(Color.shadcnBackground(.dark))
    .preferredColorScheme(.dark)
}
