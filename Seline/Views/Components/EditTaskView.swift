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
            VStack(spacing: 8) {
                titleInputSection
                descriptionInputSection
                tagSelectorSection
                datePickerSection
                timeToggleSection
                recurringToggleSection
                reminderPickerSection
                Spacer()
                actionButtonsSection
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

    // MARK: - Form Sections

    private var titleInputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Event Title")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

            TextField("Enter event title", text: $title)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
                )
        }
    }

    private var descriptionInputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description (Optional)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

            TextField("Add additional details...", text: $description, axis: .vertical)
                .font(.system(size: 13))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .lineLimit(2...4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
                )
        }
    }

    private var tagSelectorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tag (Optional)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

            Button(action: {
                showingTagOptions.toggle()
            }) {
                HStack {
                    if let tagId = selectedTagId, let tag = tagManager.getTag(by: tagId) {
                        Circle()
                            .fill(tag.color)
                            .frame(width: 8, height: 8)
                        Text(tag.name)
                            .font(.system(size: 13))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    } else {
                        Circle()
                            .fill(Color.gray)
                            .frame(width: 8, height: 8)
                        Text("Personal (Default)")
                            .font(.system(size: 13))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
                )
            }
            .sheet(isPresented: $showingTagOptions) {
                TagSelectionSheet(
                    selectedTagId: $selectedTagId,
                    colorScheme: colorScheme
                )
                .presentationDetents([.height(350)])
            }
        }
    }

    private var datePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date")
                .font(.shadcnTextSm)
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

            HStack {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(CompactDatePickerStyle())
                    .labelsHidden()

                Spacer()
            }
        }
    }

    private var timeToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Include Time", isOn: $hasTime)
                    .font(.shadcnTextSm)
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()
            }

            if hasTime {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        TimePickerField(
                            time: $selectedTime,
                            onTimeChange: { newStartTime in
                                selectedEndTime = newStartTime.addingTimeInterval(3600)
                            },
                            colorScheme: colorScheme
                        )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("End")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        TimePickerField(
                            time: $selectedEndTime,
                            colorScheme: colorScheme
                        )
                    }
                }
            }
        }
    }

    private var recurringToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Recurring Event", isOn: $isRecurring)
                    .font(.shadcnTextSm)
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()
            }

            if isRecurring {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Repeat")
                        .font(.shadcnTextSm)
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                    if task.isRecurring {
                        HStack {
                            Text(recurrenceFrequency.rawValue.capitalized)
                                .font(.shadcnTextBase)
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                            Spacer()

                            Text("Cannot change frequency")
                                .font(.shadcnTextXs)
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
                        )
                    } else {
                        Button(action: {
                            showingRecurrenceOptions.toggle()
                        }) {
                            HStack {
                                Text(recurrenceFrequency.rawValue.capitalized)
                                    .font(.shadcnTextBase)
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                                Spacer()

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(colorScheme == .dark ? Color.black : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
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
    }

    private var reminderPickerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reminder")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

            Button(action: {
                showingReminderOptions.toggle()
            }) {
                HStack {
                    Image(systemName: selectedReminder.icon)
                        .font(.system(size: 13))
                        .foregroundColor(selectedReminder == .none ? (colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)) : (colorScheme == .dark ? Color.white : Color.black))

                    Text(selectedReminder.displayName)
                        .font(.system(size: 13))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
                )
            }
            .sheet(isPresented: $showingReminderOptions) {
                ReminderOptionsSheet(
                    selectedReminder: $selectedReminder,
                    colorScheme: colorScheme
                )
                .presentationDetents([.height(320)])
            }
        }
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onCancel()
            }
            .font(.shadcnTextBase)
            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
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
            .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isValidInput ?
                        (colorScheme == .dark ?
                            Color.white :
                            Color.black) :
                        Color.gray)
            )
            .disabled(!isValidInput)
        }
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
                                            Color.white :
                                            Color.black
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
                            Color.white :
                            Color.black
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
                                            Color.white :
                                            Color.black
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
                            Color.white :
                            Color.black
                    )
                }
            }
        }
    }
}

struct TimePickerField: View {
    @Binding var time: Date
    var onTimeChange: ((Date) -> Void)? = nil
    let colorScheme: ColorScheme
    @State private var showingTimePicker = false

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }

    var body: some View {
        Button(action: { showingTimePicker = true }) {
            HStack {
                Text(formattedTime)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()

                Image(systemName: "clock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingTimePicker) {
            TimePickerSheet(time: $time, colorScheme: colorScheme, onClose: {
                onTimeChange?(time)
            })
        }
    }
}

struct TimePickerSheet: View {
    @Binding var time: Date
    let colorScheme: ColorScheme
    var onClose: () -> Void
    @Environment(\.dismiss) var dismiss

    @State private var selectedHour: Int = 12
    @State private var selectedMinute: Int = 0
    @State private var selectedPeriod: String = "AM"
    @State private var isInitialized = false

    private let hours = Array(1...12)
    private let minutes = Array(stride(from: 0, to: 60, by: 5))
    private let periods = ["AM", "PM"]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .center, spacing: 8) {
                        Text("Hour")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Picker("Hour", selection: $selectedHour) {
                            ForEach(hours, id: \.self) { hour in
                                Text(String(format: "%d", hour))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    .tag(hour)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxHeight: 150)
                    }

                    VStack(alignment: .center, spacing: 8) {
                        Text("Minute")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Picker("Minute", selection: $selectedMinute) {
                            ForEach(minutes, id: \.self) { minute in
                                Text(String(format: "%02d", minute))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    .tag(minute)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxHeight: 150)
                    }

                    VStack(alignment: .center, spacing: 8) {
                        Text("Period")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Picker("Period", selection: $selectedPeriod) {
                            ForEach(periods, id: \.self) { period in
                                Text(period)
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                    .tag(period)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxHeight: 150)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Spacer()
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle("Select Time")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        var components = Calendar.current.dateComponents([.year, .month, .day], from: time)

                        // Convert 12-hour format to 24-hour format
                        var hour24 = selectedHour
                        if selectedPeriod == "AM" {
                            if hour24 == 12 {
                                hour24 = 0 // 12 AM is 0 in 24-hour format
                            }
                        } else { // PM
                            if hour24 != 12 {
                                hour24 += 12 // Convert 1-11 PM to 13-23
                            }
                        }

                        components.hour = hour24
                        components.minute = selectedMinute
                        if let newTime = Calendar.current.date(from: components) {
                            time = newTime
                        }
                        onClose()
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
            }
        }
        .onAppear {
            if !isInitialized {
                initializeTimeValues()
                isInitialized = true
            }
        }
    }

    private func initializeTimeValues() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour24 = components.hour ?? 0
        let minute = components.minute ?? 0

        // Round minute to nearest 5
        selectedMinute = (minute + 2) / 5 * 5
        if selectedMinute >= 60 {
            selectedMinute = 55
        }

        // Convert 24-hour format to 12-hour format
        if hour24 == 0 {
            selectedHour = 12
            selectedPeriod = "AM"
        } else if hour24 < 12 {
            selectedHour = hour24
            selectedPeriod = "AM"
        } else if hour24 == 12 {
            selectedHour = 12
            selectedPeriod = "PM"
        } else {
            selectedHour = hour24 - 12
            selectedPeriod = "PM"
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