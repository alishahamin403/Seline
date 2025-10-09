import SwiftUI

struct ViewEventView: View {
    let task: TaskItem
    let onEdit: () -> Void
    let onDelete: ((TaskItem) -> Void)?
    let onDeleteRecurringSeries: ((TaskItem) -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteOptions = false

    private var formattedDate: String {
        guard let targetDate = task.targetDate else {
            return "No date set"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: targetDate)
    }

    private var formattedTime: String {
        guard let scheduledTime = task.scheduledTime else {
            return "No time set"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: scheduledTime)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Event Title")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                    Text(task.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Description (if exists)
                if let description = task.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Text(description)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(Color.shadcnForeground(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Date
                VStack(alignment: .leading, spacing: 8) {
                    Text("Date")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40))

                        Text(formattedDate)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(Color.shadcnForeground(colorScheme))

                        Spacer()
                    }
                }

                // Time
                if task.scheduledTime != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Time")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        HStack {
                            Image(systemName: "clock")
                                .font(.system(size: 16))
                                .foregroundColor(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40))

                            Text(formattedTime)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            Spacer()
                        }
                    }
                }

                // Recurring
                if task.isRecurring, let frequency = task.recurrenceFrequency {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recurring")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        HStack {
                            Image(systemName: "repeat")
                                .font(.system(size: 16))
                                .foregroundColor(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40))

                            Text(frequency.rawValue.capitalized)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            Spacer()
                        }
                    }
                }

                // Reminder
                if let reminderTime = task.reminderTime, reminderTime != .none {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reminder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        HStack {
                            Image(systemName: reminderTime.icon)
                                .font(.system(size: 16))
                                .foregroundColor(colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40))

                            Text(reminderTime.displayName)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            Spacer()
                        }
                    }
                }

                Spacer()

                // Edit Button
                Button(action: {
                    onEdit()
                }) {
                    Text("Edit Event")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    colorScheme == .dark ?
                                        Color(red: 0.518, green: 0.792, blue: 0.914) :
                                        Color(red: 0.20, green: 0.34, blue: 0.40)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 40)
        }
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    if task.isRecurring {
                        showingDeleteOptions = true
                    } else {
                        onDelete?(task)
                        dismiss()
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                }
            }
        }
        .confirmationDialog("Delete Event", isPresented: $showingDeleteOptions, titleVisibility: .visible) {
            Button("Delete This Event Only", role: .destructive) {
                onDelete?(task)
                dismiss()
            }

            Button("Delete All Recurring Events", role: .destructive) {
                onDeleteRecurringSeries?(task)
                dismiss()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is a recurring event. What would you like to delete?")
        }
    }
}

#Preview {
    NavigationView {
        ViewEventView(
            task: TaskItem(
                title: "Team Meeting",
                weekday: .monday,
                description: "Discuss project updates and next steps",
                scheduledTime: Date(),
                targetDate: Date(),
                reminderTime: .oneHour,
                isRecurring: true,
                recurrenceFrequency: .weekly
            ),
            onEdit: { print("Edit tapped") },
            onDelete: { _ in print("Delete tapped") },
            onDeleteRecurringSeries: { _ in print("Delete series tapped") }
        )
    }
}
