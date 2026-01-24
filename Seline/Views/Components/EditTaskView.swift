import SwiftUI

struct EditTaskView: View {
    let task: TaskItem
    let onSave: (TaskItem) -> Void
    let onCancel: () -> Void
    let onDelete: ((TaskItem) -> Void)?
    let onDeleteRecurringSeries: ((TaskItem) -> Void)?

    @State private var title: String
    @State private var location: String
    @State private var description: String
    @State private var selectedDate: Date
    @State private var selectedEndDate: Date
    @State private var isMultiDay: Bool
    @State private var hasTime: Bool
    @State private var selectedTime: Date
    @State private var selectedEndTime: Date
    @State private var isRecurring: Bool
    @State private var recurrenceFrequency: RecurrenceFrequency
    @State private var customRecurrenceDays: Set<WeekDay>
    @State private var selectedReminder: ReminderTime
    @State private var selectedTagId: String?
    @State private var showingDatePicker: Bool = false
    @State private var showingEndDatePicker: Bool = false
    @Environment(\.colorScheme) var colorScheme

    init(task: TaskItem, onSave: @escaping (TaskItem) -> Void, onCancel: @escaping () -> Void, onDelete: ((TaskItem) -> Void)? = nil, onDeleteRecurringSeries: ((TaskItem) -> Void)? = nil) {
        self.task = task
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onDeleteRecurringSeries = onDeleteRecurringSeries

        let startDate = task.targetDate ?? task.weekday.dateForCurrentWeek()
        let calendar = Calendar.current
        
        // Determine if this is a multi-day event
        var isMultiDayEvent = false
        var endDate = startDate
        
        if let endTime = task.endTime {
            // Check if end time is on a different day than start date
            if !calendar.isDate(endTime, inSameDayAs: startDate) {
                isMultiDayEvent = true
                endDate = calendar.startOfDay(for: endTime)
            } else {
                endDate = startDate
            }
        }
        
        _title = State(initialValue: task.title)
        _location = State(initialValue: task.location ?? "")
        _description = State(initialValue: task.description ?? "")
        _selectedDate = State(initialValue: startDate)
        _selectedEndDate = State(initialValue: endDate)
        _isMultiDay = State(initialValue: isMultiDayEvent)
        _hasTime = State(initialValue: task.scheduledTime != nil)
        _selectedTime = State(initialValue: task.scheduledTime ?? Date())
        _selectedEndTime = State(initialValue: task.endTime ?? (task.scheduledTime?.addingTimeInterval(3600) ?? Date().addingTimeInterval(3600)))
        _isRecurring = State(initialValue: task.isRecurring)
        _recurrenceFrequency = State(initialValue: task.recurrenceFrequency ?? .weekly)
        _customRecurrenceDays = State(initialValue: Set(task.customRecurrenceDays ?? []))
        _selectedReminder = State(initialValue: task.reminderTime ?? .none)
        _selectedTagId = State(initialValue: task.tagId)
    }

    private var isValidInput: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                onCancel()
            }
            .font(FontManager.geist(size: 15, weight: .semibold))
            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
            )

            Button("Save") {
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
                let descriptionToSave = trimmedDescription.isEmpty ? nil : trimmedDescription
                let locationToSave = trimmedLocation.isEmpty ? nil : trimmedLocation
                
                // Handle time and end time for multi-day events
                var timeToSave: Date? = nil
                var endTimeToSave: Date? = nil
                let calendar = Calendar.current
                
                if hasTime {
                    timeToSave = selectedTime
                    if isMultiDay {
                        // Combine end date with end time
                        let endDateComponents = calendar.dateComponents([.year, .month, .day], from: selectedEndDate)
                        let endTimeComponents = calendar.dateComponents([.hour, .minute], from: selectedEndTime)
                        var combinedComponents = DateComponents()
                        combinedComponents.year = endDateComponents.year
                        combinedComponents.month = endDateComponents.month
                        combinedComponents.day = endDateComponents.day
                        combinedComponents.hour = endTimeComponents.hour
                        combinedComponents.minute = endTimeComponents.minute
                        endTimeToSave = calendar.date(from: combinedComponents) ?? selectedEndTime
                    } else {
                        endTimeToSave = selectedEndTime
                    }
                } else if isMultiDay {
                    // All-day multi-day event: set end time to end of end date
                    endTimeToSave = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: selectedEndDate)
                }
                
                let reminderToSave = selectedReminder == .none ? nil : selectedReminder

                var updatedTask = TaskItem(
                    title: trimmedTitle,
                    weekday: task.weekday,
                    description: descriptionToSave,
                    scheduledTime: timeToSave,
                    endTime: endTimeToSave,
                    targetDate: selectedDate,
                    reminderTime: reminderToSave,
                    location: locationToSave,
                    isRecurring: isRecurring,
                    recurrenceFrequency: isRecurring ? recurrenceFrequency : nil,
                    customRecurrenceDays: isRecurring && recurrenceFrequency == .custom && !customRecurrenceDays.isEmpty ? Array(customRecurrenceDays) : nil,
                    parentRecurringTaskId: task.parentRecurringTaskId
                )
                updatedTask.id = task.id
                updatedTask.isCompleted = task.isCompleted
                updatedTask.completedDate = task.completedDate
                updatedTask.createdAt = task.createdAt
                updatedTask.tagId = selectedTagId

                onSave(updatedTask)
            }
            .font(FontManager.geist(size: 15, weight: .semibold))
            .foregroundColor(isValidInput ? (colorScheme == .dark ? Color.black : Color.white) : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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

    var body: some View {
        VStack(spacing: 0) {
            EventFormContent(
                title: $title,
                location: $location,
                description: $description,
                selectedDate: $selectedDate,
                selectedEndDate: $selectedEndDate,
                isMultiDay: $isMultiDay,
                hasTime: $hasTime,
                selectedTime: $selectedTime,
                selectedEndTime: $selectedEndTime,
                isRecurring: $isRecurring,
                recurrenceFrequency: $recurrenceFrequency,
                customRecurrenceDays: $customRecurrenceDays,
                selectedReminder: $selectedReminder,
                selectedTagId: $selectedTagId,
                showingDatePicker: $showingDatePicker,
                showingEndDatePicker: $showingEndDatePicker
            )

            Divider()
                .padding(.top, 16)

            actionButtonsSection
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
        }
        .background(
            colorScheme == .dark ? Color.gmailDarkBackground : Color.white
        )
        .navigationTitle("Edit Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
    }
}

#Preview {
    NavigationView {
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
}
