import SwiftUI

struct EventsCardWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @Binding var showingAddEventPopup: Bool

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var todayEvents: [TaskItem] {
        taskManager.getTasksForDate(today).sorted { task1, task2 in
            let time1 = task1.scheduledTime ?? Date()
            let time2 = task2.scheduledTime ?? Date()
            return time1 < time2
        }
    }

    private var nextEvent: TaskItem? {
        let now = Date()
        return todayEvents.first { task in
            if let scheduledTime = task.scheduledTime {
                return scheduledTime >= now
            }
            return true
        }
    }

    private var upcomingEvents: [TaskItem] {
        Array(todayEvents.dropFirst())
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func timeUntilEvent(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let interval = date.timeIntervalSinceNow

        if interval < 0 {
            return "In progress"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "In \(minutes) min"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "In \(hours)h"
        }
        return nil
    }

    private func isEventSoon(_ date: Date?) -> Bool {
        guard let date = date else { return false }
        let interval = date.timeIntervalSinceNow
        return interval > 0 && interval < 1800 // Less than 30 minutes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with count
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("EVENTS TODAY")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Text("(\(todayEvents.count))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }

                Spacer()

                Button(action: { showingAddEventPopup = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)

            if todayEvents.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                    Text("No events today")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        // Next Event (Prominent)
                        if let next = nextEvent {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "clock.fill")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? .white : .black)

                                            Text(next.scheduledTime.map { formatTime($0) } ?? "All Day")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? .white : .black)

                                            if isEventSoon(next.scheduledTime) {
                                                Text("⚠️ \(timeUntilEvent(next.scheduledTime) ?? "")")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
                                            }
                                        }

                                        Text(next.title)
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                                            .lineLimit(1)

                                        if !(next.description?.isEmpty ?? true) {
                                            Text(next.description ?? "")
                                                .font(.system(size: 11, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isEventSoon(next.scheduledTime) ? Color(red: 1, green: 0.4, blue: 0.4).opacity(0.2) : Color.blue.opacity(0.1))
                                )
                            }
                        }

                        // Other events
                        if upcomingEvents.count > 0 {
                            Divider()
                                .opacity(0.3)
                                .padding(.vertical, 4)

                            VStack(spacing: 8) {
                                ForEach(upcomingEvents.prefix(2)) { event in
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(event.scheduledTime.map { formatTime($0) } ?? "All Day")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                            }

                                            Text(event.title)
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                                                .lineLimit(1)
                                        }

                                        Spacer()
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                                    )
                                }

                                if upcomingEvents.count > 2 {
                                    Button(action: { showingAddEventPopup = true }) {
                                        Text("+ \(upcomingEvents.count - 2) more events")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(red: 0.08, green: 0.08, blue: 0.08) : Color(red: 0.97, green: 0.97, blue: 0.97))
        )
        .padding(.horizontal, 12)
    }
}

#Preview {
    EventsCardWidget(showingAddEventPopup: .constant(false))
        .padding()
}
