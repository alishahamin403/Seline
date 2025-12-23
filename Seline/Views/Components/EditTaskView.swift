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
    @State private var customRecurrenceDays: Set<WeekDay>
    @State private var selectedReminder: ReminderTime
    @State private var selectedTagId: String?
    @Environment(\.colorScheme) var colorScheme

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
            .font(.system(size: 15, weight: .semibold))
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
            .font(.system(size: 15, weight: .semibold))
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
                description: $description,
                selectedDate: $selectedDate,
                hasTime: $hasTime,
                selectedTime: $selectedTime,
                selectedEndTime: $selectedEndTime,
                isRecurring: $isRecurring,
                recurrenceFrequency: $recurrenceFrequency,
                customRecurrenceDays: $customRecurrenceDays,
                selectedReminder: $selectedReminder,
                selectedTagId: $selectedTagId
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
