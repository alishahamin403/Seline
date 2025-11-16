import SwiftUI

struct AddEventFromEmailView: View {
    let email: Email
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var taskManager = TaskManager.shared

    @State private var eventTitle: String = ""
    @State private var selectedDate: Date = Date()
    @State private var selectedTime: Date = Date()
    @State private var reminderTime: ReminderTime = .none
    @State private var hasScheduledTime: Bool = false
    @State private var isCreating: Bool = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Email Preview Card
                        emailPreviewCard

                        // Event Details Section
                        eventDetailsSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: createEvent) {
                        if isCreating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                        } else {
                            Text("Create")
                                .fontWeight(.semibold)
                                .foregroundColor(
                                    eventTitle.isEmpty ?
                                        Color.gray :
                                        Color(red: 0.29, green: 0.29, blue: 0.29)
                                )
                        }
                    }
                    .disabled(eventTitle.isEmpty || isCreating)
                }
            }
        }
        .onAppear {
            // Pre-fill event title with email subject
            eventTitle = email.subject
        }
    }

    // MARK: - Email Preview Card

    private var emailPreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color(red: 0.29, green: 0.29, blue: 0.29) :
                            Color(red: 0.29, green: 0.29, blue: 0.29)
                    )

                Text("Attached Email")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(email.subject)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text("From:")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color.gray)

                    Text(email.sender.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))
                }

                Text(email.snippet)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(Color.gray)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
        )
    }

    // MARK: - Event Details Section

    private var eventDetailsSection: some View {
        VStack(spacing: 20) {
            // Event Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Event Title")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                TextField("Enter event title", text: $eventTitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
            }

            // Date Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Date")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(GraphicalDatePickerStyle())
                    .labelsHidden()
                    .accentColor(
                        colorScheme == .dark ?
                            Color(red: 0.29, green: 0.29, blue: 0.29) :
                            Color(red: 0.29, green: 0.29, blue: 0.29)
                    )
            }

            // Time Toggle
            Toggle(isOn: $hasScheduledTime) {
                Text("Add Time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            .tint(Color(red: 0.29, green: 0.29, blue: 0.29))

            // Time Picker (if enabled)
            if hasScheduledTime {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Time")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(WheelDatePickerStyle())
                        .labelsHidden()
                        .accentColor(Color(red: 0.29, green: 0.29, blue: 0.29))
                }

                // Reminder Time
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reminder")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Picker("Reminder", selection: $reminderTime) {
                        ForEach(ReminderTime.allCases, id: \.self) { reminder in
                            HStack(spacing: 6) {
                                Image(systemName: reminder.icon)
                                    .font(.system(size: 12))
                                Text(reminder.displayName)
                            }
                            .tag(reminder)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
                    .accentColor(
                        colorScheme == .dark ?
                            Color(red: 0.29, green: 0.29, blue: 0.29) :
                            Color(red: 0.29, green: 0.29, blue: 0.29)
                    )
                }
            }
        }
    }

    // MARK: - Create Event

    private func createEvent() {
        isCreating = true

        // Determine the weekday from the selected date
        let calendar = Calendar.current
        let weekdayComponent = calendar.component(.weekday, from: selectedDate)
        let weekday: WeekDay

        switch weekdayComponent {
        case 1: weekday = .sunday
        case 2: weekday = .monday
        case 3: weekday = .tuesday
        case 4: weekday = .wednesday
        case 5: weekday = .thursday
        case 6: weekday = .friday
        case 7: weekday = .saturday
        default: weekday = .monday
        }

        // Create the task with email attachment
        let finalReminderTime = hasScheduledTime ? reminderTime : nil
        let finalScheduledTime = hasScheduledTime ? selectedTime : nil

        // Add task to TaskManager
        taskManager.addTask(
            title: eventTitle,
            to: weekday,
            description: nil,
            scheduledTime: finalScheduledTime,
            targetDate: selectedDate,
            reminderTime: finalReminderTime,
            isRecurring: false,
            recurrenceFrequency: nil
        )

        // Get the newly created task and attach email data
        if let newTask = taskManager.tasks[weekday]?.first(where: { $0.title == eventTitle }) {
            var updatedTask = newTask
            updatedTask.emailId = email.id
            updatedTask.emailSubject = email.subject
            updatedTask.emailSenderName = email.sender.name
            updatedTask.emailSenderEmail = email.sender.email
            updatedTask.emailSnippet = email.snippet
            updatedTask.emailTimestamp = email.timestamp
            updatedTask.emailBody = email.body
            updatedTask.emailIsImportant = email.isImportant
            updatedTask.emailAiSummary = email.aiSummary

            // Update the task in TaskManager
            taskManager.editTask(updatedTask)
        }

        // Provide haptic feedback
        HapticManager.shared.success()

        // Delay dismissal slightly for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isCreating = false
            dismiss()
        }
    }
}

#Preview {
    AddEventFromEmailView(email: Email.sampleEmails[0])
}
