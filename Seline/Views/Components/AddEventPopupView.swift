import SwiftUI

struct AddEventPopupView: View {
    @Binding var isPresented: Bool
    let onSave: (String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, [WeekDay]?, String?) -> Void

    // Optional initial values
    let initialDate: Date?
    let initialTime: Date?

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedDate: Date
    @State private var hasTime: Bool
    @State private var selectedTime: Date
    @State private var selectedEndTime: Date
    @State private var isRecurring: Bool = false
    @State private var recurrenceFrequency: RecurrenceFrequency = .weekly
    @State private var customRecurrenceDays: Set<WeekDay> = []
    @State private var selectedReminder: ReminderTime = .none
    @State private var selectedTagId: String? = nil
    @Environment(\.colorScheme) var colorScheme

    init(
        isPresented: Binding<Bool>,
        onSave: @escaping (String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, [WeekDay]?, String?) -> Void,
        initialDate: Date? = nil,
        initialTime: Date? = nil
    ) {
        self._isPresented = isPresented
        self.onSave = onSave
        self.initialDate = initialDate
        self.initialTime = initialTime

        let date = initialDate ?? Date()
        let time = initialTime ?? Date()
        _selectedDate = State(initialValue: date)
        _hasTime = State(initialValue: initialTime != nil)
        _selectedTime = State(initialValue: time)
        _selectedEndTime = State(initialValue: time.addingTimeInterval(3600))
    }

    private var isValidInput: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: { isPresented = false }) {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                    )
            }

            Button(action: {
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                let descriptionToSave = trimmedDescription.isEmpty ? nil : trimmedDescription
                let timeToSave = hasTime ? selectedTime : nil
                let endTimeToSave = hasTime ? selectedEndTime : nil
                let customDays = (isRecurring && recurrenceFrequency == .custom && !customRecurrenceDays.isEmpty) ?
                    Array(customRecurrenceDays).sorted(by: { $0.sortOrder < $1.sortOrder }) : nil

                onSave(
                    trimmedTitle,
                    descriptionToSave,
                    selectedDate,
                    timeToSave,
                    endTimeToSave,
                    selectedReminder == .none ? nil : selectedReminder,
                    isRecurring,
                    isRecurring ? recurrenceFrequency : nil,
                    customDays,
                    selectedTagId
                )
                isPresented = false
            }) {
                Text("Create Event")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isValidInput ? (colorScheme == .dark ? Color.black : Color.white) : Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isValidInput ? (colorScheme == .dark ? Color.white : Color.black) : Color.gray.opacity(0.3))
                    )
            }
            .disabled(!isValidInput)
        }
    }

    var body: some View {
        NavigationView {
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
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
    }
}

#Preview {
    ZStack {
        Color.gray
            .ignoresSafeArea()

        AddEventPopupView(
            isPresented: .constant(true),
            onSave: { title, description, date, time, endTime, reminder, recurring, frequency, customDays, tagId in
                print("Created: \(title), Description: \(description ?? "None"), Custom Days: \(customDays?.map { $0.shortDisplayName }.joined(separator: ", ") ?? "None"), TagID: \(tagId ?? "Personal")")
            }
        )
    }
}
