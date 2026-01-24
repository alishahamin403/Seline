import SwiftUI

struct TimelineEventBlock: View {
    let task: TaskItem
    let date: Date
    let onTap: () -> Void
    let onToggleCompletion: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @StateObject private var tagManager = TagManager.shared
    @State private var showActions = false

    // Calculate event duration in minutes
    private var durationMinutes: Int {
        guard let start = task.scheduledTime else { return 60 }
        guard let end = task.endTime, end > start else {
            return 60 // Default 1 hour if no end time OR end time is same as start (common for point-events)
        }
        let duration = Int(end.timeIntervalSince(start) / 60)
        return max(duration, 15) // Minimum 15 minutes for display
    }

    // Height calculation: 60 points per hour
    private var blockHeight: CGFloat {
        CGFloat(durationMinutes) / 60.0 * 60.0
    }

    // Display height matches block height
    private var displayHeight: CGFloat {
        blockHeight
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var timeRange: String {
        if let start = task.scheduledTime, let end = task.endTime {
            return "\(formatTime(start)) - \(formatTime(end))"
        } else if let start = task.scheduledTime {
            return formatTime(start)
        }
        return ""
    }

    private var isCompleted: Bool {
        task.isCompletedOn(date: date)
    }

    private var filterType: TimelineEventColorManager.FilterType {
        TimelineEventColorManager.filterType(from: task)
    }

    private var tagColorIndex: Int? {
        // Get the actual colorIndex from the tag for consistent colors
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
        // Use the color manager to determine appropriate text color
        if case .tag(let tagId) = filterType, let tagColorIndex = tagColorIndex {
            return TimelineEventColorManager.tagColorTextColor(colorIndex: tagColorIndex, colorScheme: colorScheme)
        }
        // For personal/sync events, use white in dark mode, black in light mode
        return TimelineEventColorManager.timelineEventTextColor(
            filterType: filterType,
            colorScheme: colorScheme,
            tagColorIndex: tagColorIndex
        )
    }

    private var circleColor: Color {
        // Use white in both light and dark mode for better visibility
        return Color.white
    }


    var body: some View {
        HStack(spacing: 6) {
            // Completion status indicator (hidden for calendar events)
            if !task.isFromCalendar {
                Button(action: {
                    HapticManager.shared.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        onToggleCompletion()
                    }
                }) {
                    Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(circleColor)
                }
                .buttonStyle(PlainButtonStyle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(textColor)
                    .strikethrough(isCompleted, color: textColor.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            // Email indicator if attached
            if task.hasEmailAttachment {
                Image(systemName: "envelope.fill")
                    .font(FontManager.geist(size: 9, weight: .regular))
                    .foregroundColor(circleColor.opacity(0.7))
            }

            // Recurring indicator
            if task.isRecurring {
                Image(systemName: "repeat")
                    .font(FontManager.geist(size: 9, weight: .regular))
                    .foregroundColor(circleColor.opacity(0.7))
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 11)
        .padding(.vertical, 8)
        .frame(alignment: .topLeading)
        .frame(height: displayHeight)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(backgroundColor) // Solid color, no opacity
        )
        .clipped() // Prevent content from overflowing
        .shadow(
            color: (colorScheme == .dark ? Color.white : Color.black).opacity(0.08),
            radius: 2,
            x: 0,
            y: 1
        )
        .onTapGesture {
            HapticManager.shared.light()
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            HapticManager.shared.cardTap()
            showActions = true
        }
        .confirmationDialog("Event Options", isPresented: $showActions, titleVisibility: .hidden) {
            if let onEdit = onEdit {
                Button("Edit") {
                    onEdit()
                }
            }

            if let onDelete = onDelete {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
            }

            Button("Cancel", role: .cancel) {}
        }
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCompleted)
    }
}

#Preview {
    VStack(spacing: 12) {
        TimelineEventBlock(
            task: TaskItem(
                title: "Team Meeting",
                weekday: .monday,
                scheduledTime: Date(),
                endTime: Calendar.current.date(byAdding: .hour, value: 1, to: Date())
            ),
            date: Date(),
            onTap: {},
            onToggleCompletion: {},
            onEdit: {},
            onDelete: {}
        )
        .frame(width: 300)

        TimelineEventBlock(
            task: TaskItem(
                title: "Quick standup call with design team",
                weekday: .monday,
                scheduledTime: Date(),
                endTime: Calendar.current.date(byAdding: .minute, value: 15, to: Date())
            ),
            date: Date(),
            onTap: {},
            onToggleCompletion: {},
            onEdit: {},
            onDelete: {}
        )
        .frame(width: 300)
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}
