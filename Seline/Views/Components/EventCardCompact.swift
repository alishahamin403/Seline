import SwiftUI

struct EventCardCompact: View {
    let task: TaskItem
    let selectedDate: Date
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var tagManager = TagManager.shared
    let onTap: () -> Void

    private var isCompleted: Bool {
        task.isCompletedOn(date: selectedDate)
    }

    private var filterType: TimelineEventColorManager.FilterType {
        TimelineEventColorManager.filterType(from: task)
    }

    private var tagColorIndex: Int? {
        guard case .tag(let tagId) = filterType else { return nil }
        return tagManager.getTag(by: tagId)?.colorIndex
    }

    private var accentColor: Color {
        TimelineEventColorManager.timelineEventAccentColor(
            filterType: filterType,
            colorScheme: colorScheme,
            tagColorIndex: tagColorIndex
        )
    }

    private var backgroundColor: Color {
        TimelineEventColorManager.timelineEventBackgroundColor(
            filterType: filterType,
            colorScheme: colorScheme,
            isCompleted: isCompleted,
            tagColorIndex: tagColorIndex
        )
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var timeDisplay: String {
        if let start = task.scheduledTime, let end = task.endTime {
            return "\(formatTime(start)) - \(formatTime(end))"
        } else if let start = task.scheduledTime {
            return formatTime(start)
        }
        return "All day"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                // Title and time
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(textColor)
                        .strikethrough(isCompleted, color: textColor.opacity(0.5))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(accentColor)

                        Text(timeDisplay)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(textColor.opacity(0.7))
                    }
                }

                Spacer()

                // Accent color indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(accentColor)
                    .frame(width: 3, height: 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
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
    EventCardCompact(
        task: TaskItem(
            title: "Team Meeting",
            weekday: .monday,
            scheduledTime: Date(),
            endTime: Calendar.current.date(byAdding: .hour, value: 1, to: Date())
        ),
        selectedDate: Date(),
        onTap: {}
    )
    .background(Color.shadcnBackground(.light))
}
