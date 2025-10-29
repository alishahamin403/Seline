import SwiftUI

struct ViewEventView: View {
    let task: TaskItem
    let onEdit: () -> Void
    let onDelete: ((TaskItem) -> Void)?
    let onDeleteRecurringSeries: ((TaskItem) -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var showingDeleteOptions = false
    @State private var isEmailExpanded = false

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
            VStack(spacing: 8) {
                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Event Title")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                    Text(task.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Description (if exists)
                if let description = task.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Text(description)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Date
                VStack(alignment: .leading, spacing: 6) {
                    Text("Date")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                        Text(formattedDate)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                        Spacer()
                    }
                }

                // Time
                if task.scheduledTime != nil || task.endTime != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Time")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        HStack {
                            Image(systemName: "clock")
                                .font(.system(size: 16))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Text(task.formattedTimeRange)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Spacer()
                        }
                    }
                }

                // Recurring
                if task.isRecurring, let frequency = task.recurrenceFrequency {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recurring")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        HStack {
                            Image(systemName: "repeat")
                                .font(.system(size: 16))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Text(frequency.rawValue.capitalized)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Spacer()
                        }
                    }
                }

                // Reminder
                if let reminderTime = task.reminderTime, reminderTime != .none {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reminder")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        HStack {
                            Image(systemName: reminderTime.icon)
                                .font(.system(size: 16))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Text(reminderTime.displayName)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Spacer()
                        }
                    }
                }

                // Attached Email
                if task.hasEmailAttachment {
                    attachedEmailSection
                }

                Spacer()

                // Edit Button
                Button(action: {
                    onEdit()
                }) {
                    Text("Edit Event")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
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

    // MARK: - Attached Email Section

    private var attachedEmailSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attached Email")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEmailExpanded.toggle()
                }
            }) {
                VStack(alignment: .leading, spacing: 12) {
                    // Email header
                    HStack(spacing: 12) {
                        // Email icon
                        ZStack {
                            Circle()
                                .fill(colorScheme == .dark ?
                                    Color.white.opacity(0.2) :
                                    Color.black.opacity(0.1))
                                .frame(width: 40, height: 40)

                            Image(systemName: "envelope.fill")
                                .font(.system(size: 16))
                                .foregroundColor(colorScheme == .dark ?
                                    Color(red: 0.40, green: 0.65, blue: 0.80) :
                                    Color(red: 0.20, green: 0.34, blue: 0.40))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            if let subject = task.emailSubject {
                                Text(subject)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(Color.shadcnForeground(colorScheme))
                                    .lineLimit(isEmailExpanded ? nil : 2)
                                    .multilineTextAlignment(.leading)
                            }

                            if let senderName = task.emailSenderName {
                                HStack(spacing: 4) {
                                    Text("From:")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(Color.gray)

                                    Text(senderName)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ?
                                            Color.white.opacity(0.7) :
                                            Color.black.opacity(0.6))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Expand/collapse indicator
                        Image(systemName: isEmailExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.gray)
                    }

                    // Email snippet (only when collapsed)
                    if !isEmailExpanded, let snippet = task.emailSnippet {
                        Text(snippet)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color.gray)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 4)
                    }

                    // Email timestamp
                    if let timestamp = task.emailTimestamp {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundColor(Color.gray)

                            Text(formatEmailTimestamp(timestamp))
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Color.gray)
                        }
                        .padding(.top, 4)
                    }

                    // AI Summary and Full email body (only when expanded)
                    if isEmailExpanded {
                        Divider()
                            .padding(.vertical, 8)

                        // AI Summary Section
                        if let aiSummary = task.emailAiSummary, !aiSummary.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ?
                                            Color.white :
                                            Color.black)

                                    Text("AI Summary")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ?
                                            Color.white :
                                            Color.black)
                                }

                                Text(aiSummary)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ?
                                                Color.white.opacity(0.05) :
                                                Color.black.opacity(0.03))
                                    )
                            }
                            .padding(.bottom, 12)
                        }

                        // Original Email Body Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Original Email")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))

                            if let emailBody = task.emailBody, !emailBody.isEmpty {
                                ScrollView {
                                    Text(emailBody)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 300)
                            } else if let snippet = task.emailSnippet {
                                Text(snippet)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ?
                            Color.white.opacity(0.05) :
                            Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(colorScheme == .dark ?
                            Color.white.opacity(0.1) :
                            Color.black.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func formatEmailTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
