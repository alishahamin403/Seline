import SwiftUI

struct EventCardCompact: View {
    let task: TaskItem
    let selectedDate: Date
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var tagManager = TagManager.shared
    let onTap: () -> Void
    let onToggleCompletion: (() -> Void)?

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
        HStack(alignment: .center, spacing: 10) {
            // Completion checkbox
            Button(action: {
                onToggleCompletion?()
            }) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(accentColor)
            }
            .buttonStyle(PlainButtonStyle())

            // Title and time
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(textColor)
                    .strikethrough(isCompleted, color: textColor.opacity(0.5))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(FontManager.geist(size: 10, weight: .regular))
                        .foregroundColor(accentColor)

                    Text(timeDisplay)
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(textColor.opacity(0.7))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(Color.shadcnTileBackground(colorScheme))
        )
        .onTapGesture {
            onTap()
        }
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
        onTap: {},
        onToggleCompletion: {}
    )
    .background(Color.shadcnBackground(.light))
}
