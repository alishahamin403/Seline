import SwiftUI

struct EditTaskView: View {
    let task: TaskItem
    let onSave: (TaskItem) -> Void
    let onCancel: () -> Void
    let onDelete: ((TaskItem) -> Void)?
    let onDeleteRecurringSeries: ((TaskItem) -> Void)?

    @State private var title: String
    @State private var description: String
    @State private var selectedDate: Date
    @State private var hasTime: Bool
    @State private var selectedTime: Date
    @State private var selectedEndTime: Date
    @State private var isRecurring: Bool
    @State private var recurrenceFrequency: RecurrenceFrequency
    @State private var selectedReminder: ReminderTime
    @State private var selectedTagId: String?
    @State private var showingRecurrenceOptions: Bool = false
    @State private var showingReminderOptions: Bool = false
    @State private var showingTagOptions: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared

    init(task: TaskItem, onSave: @escaping (TaskItem) -> Void, onCancel: @escaping () -> Void, onDelete: ((TaskItem) -> Void)? = nil, onDeleteRecurringSeries: ((TaskItem) -> Void)? = nil) {
        self.task = task
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onDeleteRecurringSeries = onDeleteRecurringSeries

        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description ?? "")
        _selectedDate = State(initialValue: task.targetDate ?? task.weekday.dateForCurrentWeek())
        _hasTime = State(initialValue: task.scheduledTime != nil)
        _selectedTime = State(initialValue: task.scheduledTime ?? Date())
        _selectedEndTime = State(initialValue: task.endTime ?? (task.scheduledTime?.addingTimeInterval(3600) ?? Date().addingTimeInterval(3600)))
        _isRecurring = State(initialValue: task.isRecurring)
        _recurrenceFrequency = State(initialValue: task.recurrenceFrequency ?? .weekly)
        _selectedReminder = State(initialValue: task.reminderTime ?? .none)
        _selectedTagId = State(initialValue: task.tagId)
    }

    private var isValidInput: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Title Input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Event Title")
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnMuted(colorScheme))

                    TextField("Enter event title", text: $title)
                        .font(.shadcnTextBase)
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.shadcnBorder(colorScheme), lineWidth: 1)
                        )
                }

                // Description Input
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (Optional)")
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnMuted(colorScheme))

                    TextField("Add additional details...", text: $description, axis: .vertical)
                        .font(.shadcnTextBase)
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .lineLimit(3...6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.shadcnBorder(colorScheme), lineWidth: 1)
                        )
                }

                // Tag Selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tag (Optional)")
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnMuted(colorScheme))

                    Button(action: {
                        showingTagOptions.toggle()
                    }) {
                        HStack {
                            if let tagId = selectedTagId, let tag = tagManager.getTag(by: tagId) {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 10, height: 10)
                                Text(tag.name)
                            } else {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 10, height: 10)
                                Text("Personal (Default)")
                            }

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(Color.shadcnMuted(colorScheme))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.shadcnBorder(colorScheme), lineWidth: 1)
                        )
                    }
                    .sheet(isPresented: $showingTagOptions) {
                        TagSelectionSheet(
                            selectedTagId: $selectedTagId,
                            colorScheme: colorScheme
                        )
                        .presentationDetents([.height(300)])
                    }
                }

                // Date Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Date")
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnMuted(colorScheme))

                    HStack {
                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(CompactDatePickerStyle())
                            .labelsHidden()

                        Spacer()
                    }
                }

                // Time Toggle and Picker
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle("Include Time", isOn: $hasTime)
                            .font(.shadcnTextSm)
                            .foregroundColor(Color.shadcnForeground(colorScheme))

                        Spacer()
                    }

                    if hasTime {
                        VStack(alignment: .leading, spacing: 12) {
                            // Start Time
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start Time")
                                    .font(.shadcnTextXs)
                                    .foregroundColor(Color.shadcnMuted(colorScheme))

                                DatePicker("Start Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(WheelDatePickerStyle())
                                    .labelsHidden()
                                    .onChange(of: selectedTime) { newStartTime in
                                        // Auto-update end time to be 1 hour after start time
                                        selectedEndTime = newStartTime.addingTimeInterval(3600)
                                    }
                            }

                            // End Time
                            VStack(alignment: .leading, spacing: 4) {
                                Text("End Time")
                                    .font(.shadcnTextXs)
                                    .foregroundColor(Color.shadcnMuted(colorScheme))

                                DatePicker("End Time", selection: $selectedEndTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(WheelDatePickerStyle())
                                    .labelsHidden()
                            }
                        }
                    }
                }

                // Recurring Toggle and Settings
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Toggle("Recurring Event", isOn: $isRecurring)
                            .font(.shadcnTextSm)
                            .foregroundColor(Color.shadcnForeground(colorScheme))

                        Spacer()
                    }

                    if isRecurring {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Repeat")
                                .font(.shadcnTextSm)
                                .foregroundColor(Color.shadcnMuted(colorScheme))

                            // Show frequency as read-only if task was already recurring
                            if task.isRecurring {
                                HStack {
                                    Text(recurrenceFrequency.rawValue.capitalized)
                                        .font(.shadcnTextBase)
                                        .foregroundColor(Color.shadcnMuted(colorScheme))

                                    Spacer()

                                    Text("Cannot change frequency")
                                        .font(.shadcnTextXs)
                                        .foregroundColor(Color.shadcnMuted(colorScheme))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colorScheme == .dark ? Color.black.opacity(0.1) : Color.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.shadcnBorder(colorScheme).opacity(0.5), lineWidth: 1)
                                )
                            } else {
                                // Allow frequency selection for new recurring tasks
                                Button(action: {
                                    showingRecurrenceOptions.toggle()
                                }) {
                                    HStack {
                                        Text(recurrenceFrequency.rawValue.capitalized)
                                            .font(.shadcnTextBase)
                                            .foregroundColor(Color.shadcnForeground(colorScheme))

                                        Spacer()

                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color.shadcnMuted(colorScheme))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.shadcnBorder(colorScheme), lineWidth: 1)
                                    )
                                }
                                .sheet(isPresented: $showingRecurrenceOptions) {
                                    RecurringOptionsSheet(
                                        selectedFrequency: $recurrenceFrequency,
                                        colorScheme: colorScheme
                                    )
                                    .presentationDetents([.height(300)])
                                }
                            }
                        }
                    }
                }

                // Reminder Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reminder")
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnMuted(colorScheme))

                    Button(action: {
                        showingReminderOptions.toggle()
                    }) {
                        HStack {
                            Image(systemName: selectedReminder.icon)
                                .font(.system(size: 16))
                                .foregroundColor(selectedReminder == .none ? Color.shadcnMuted(colorScheme) : Color.shadcnPrimary)

                            Text(selectedReminder.displayName)
                                .font(.shadcnTextBase)
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            Spacer()

                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(Color.shadcnMuted(colorScheme))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.shadcnBorder(colorScheme), lineWidth: 1)
                        )
                    }
                    .sheet(isPresented: $showingReminderOptions) {
                        ReminderOptionsSheet(
                            selectedReminder: $selectedReminder,
                            colorScheme: colorScheme
                        )
                        .presentationDetents([.height(350)])
                    }
                }

                Spacer()

                // Action Buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(.shadcnTextBase)
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )

                    Button("Save") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        let descriptionToSave = trimmedDescription.isEmpty ? nil : trimmedDescription
                        let timeToSave = hasTime ? selectedTime : nil
                        let endTimeToSave = hasTime ? selectedEndTime : nil
                        let reminderToSave = selectedReminder == .none ? nil : selectedReminder

                        var updatedTask = TaskItem(
                            title: trimmedTitle,
                            weekday: task.weekday,
                            description: descriptionToSave,
                            scheduledTime: timeToSave,
                            endTime: endTimeToSave,
                            targetDate: selectedDate,
                            reminderTime: reminderToSave,
                            isRecurring: isRecurring,
                            recurrenceFrequency: isRecurring ? recurrenceFrequency : nil,
                            parentRecurringTaskId: task.parentRecurringTaskId
                        )
                        updatedTask.id = task.id
                        updatedTask.isCompleted = task.isCompleted
                        updatedTask.completedDate = task.completedDate
                        updatedTask.createdAt = task.createdAt
                        updatedTask.tagId = selectedTagId

                        onSave(updatedTask)
                    }
                    .font(.shadcnTextBase)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isValidInput ?
                                (colorScheme == .dark ?
                                    Color(red: 0.518, green: 0.792, blue: 0.914) :
                                    Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                Color.gray)
                    )
                    .disabled(!isValidInput)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(
            colorScheme == .dark ? Color.gmailDarkBackground : Color.white
        )
        .navigationTitle("Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
    }
}

struct RecurringOptionsSheet: View {
    @Binding var selectedFrequency: RecurrenceFrequency
    let colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                    Button(action: {
                        selectedFrequency = frequency
                        dismiss()
                    }) {
                        HStack {
                            Text(frequency.rawValue.capitalized)
                                .font(.shadcnTextBase)
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            Spacer()

                            if selectedFrequency == frequency {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                            Color(red: 0.40, green: 0.65, blue: 0.80) :
                                            Color(red: 0.20, green: 0.34, blue: 0.40)
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            selectedFrequency == frequency ?
                                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)) :
                                Color.clear
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()
            }
            .background(
                colorScheme == .dark ? Color.gmailDarkBackground : Color.white
            )
            .navigationTitle("Repeat Frequency")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color(red: 0.40, green: 0.65, blue: 0.80) :
                            Color(red: 0.20, green: 0.34, blue: 0.40)
                    )
                }
            }
        }
    }
}

struct ReminderOptionsSheet: View {
    @Binding var selectedReminder: ReminderTime
    let colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ForEach(ReminderTime.allCases, id: \.self) { reminder in
                    Button(action: {
                        selectedReminder = reminder
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: reminder.icon)
                                .font(.system(size: 16))
                                .foregroundColor(reminder == .none ? Color.shadcnMuted(colorScheme) : Color.shadcnPrimary)
                                .frame(width: 24)

                            Text(reminder.displayName)
                                .font(.shadcnTextBase)
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            Spacer()

                            if selectedReminder == reminder {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                            Color(red: 0.40, green: 0.65, blue: 0.80) :
                                            Color(red: 0.20, green: 0.34, blue: 0.40)
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            selectedReminder == reminder ?
                                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)) :
                                Color.clear
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()
            }
            .background(
                colorScheme == .dark ? Color.gmailDarkBackground : Color.white
            )
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(
                        colorScheme == .dark ?
                            Color(red: 0.40, green: 0.65, blue: 0.80) :
                            Color(red: 0.20, green: 0.34, blue: 0.40)
                    )
                }
            }
        }
    }
}

#Preview {
    EditTaskView(
        task: TaskItem(title: "Sample Event", weekday: .monday),
        onSave: { updatedTask in
            print("Saving: \(updatedTask.title), \(updatedTask.targetDate?.description ?? "no date")")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}