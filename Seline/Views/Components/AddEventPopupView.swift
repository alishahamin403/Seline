import SwiftUI

struct AddEventPopupView: View {
    @Binding var isPresented: Bool
    let onSave: (String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, [WeekDay]?, String?, String?) -> Void

    // Optional initial values
    let initialDate: Date?
    let initialTime: Date?

    @State private var title: String = ""
    @State private var location: String = ""
    @State private var description: String = ""
    @State private var selectedDate: Date
    @State private var selectedEndDate: Date
    @State private var isMultiDay: Bool = false
    @State private var hasTime: Bool
    @State private var selectedTime: Date
    @State private var selectedEndTime: Date
    @State private var isRecurring: Bool = false
    @State private var recurrenceFrequency: RecurrenceFrequency = .weekly
    @State private var customRecurrenceDays: Set<WeekDay> = []
    @State private var selectedReminder: ReminderTime = .none
    @State private var selectedTagId: String? = nil
    @State private var createAnother: Bool = false
    @State private var showingDatePicker: Bool = false
    @State private var showingEndDatePicker: Bool = false
    @Environment(\.colorScheme) var colorScheme

    init(
        isPresented: Binding<Bool>,
        onSave: @escaping (String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, [WeekDay]?, String?, String?) -> Void,
        initialDate: Date? = nil,
        initialTime: Date? = nil
    ) {
        self._isPresented = isPresented
        self.onSave = onSave
        self.initialDate = initialDate
        self.initialTime = initialTime

        let date = initialDate ?? Date()
        let time = AddEventPopupView.snapTo15Minutes(initialTime ?? Date())
        _selectedDate = State(initialValue: date)
        _selectedEndDate = State(initialValue: date)
        _hasTime = State(initialValue: initialTime != nil)
        _selectedTime = State(initialValue: time)
        _selectedEndTime = State(initialValue: time.addingTimeInterval(3600))
    }

    private static func snapTo15Minutes(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minutes = calendar.component(.minute, from: date)
        let roundedMinutes = ((minutes + 7) / 15) * 15
        
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        components.minute = roundedMinutes
        
        // Handle cases where rounding goes to 60
        if roundedMinutes == 60 {
            components.hour = (components.hour ?? 0) + 1
            components.minute = 0
        }
        
        return calendar.date(from: components) ?? date
    }

    private var isValidInput: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: { isPresented = false }) {
                Text("Cancel")
                    .font(FontManager.geist(size: 15, weight: .semibold))
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
                let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
                let descriptionToSave = trimmedDescription.isEmpty ? nil : trimmedDescription
                let locationToSave = trimmedLocation.isEmpty ? nil : trimmedLocation
                
                // For multi-day events, combine date and time for both start and end
                var timeToSave: Date? = nil
                var endTimeToSave: Date? = nil
                let calendar = Calendar.current
                
                if hasTime {
                    // Combine start date with start time
                    let startDateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
                    let startTimeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
                    var startCombinedComponents = DateComponents()
                    startCombinedComponents.year = startDateComponents.year
                    startCombinedComponents.month = startDateComponents.month
                    startCombinedComponents.day = startDateComponents.day
                    startCombinedComponents.hour = startTimeComponents.hour
                    startCombinedComponents.minute = startTimeComponents.minute
                    timeToSave = calendar.date(from: startCombinedComponents) ?? selectedTime
                    
                    if isMultiDay {
                        // Combine end date with end time
                        let endDateComponents = calendar.dateComponents([.year, .month, .day], from: selectedEndDate)
                        let endTimeComponents = calendar.dateComponents([.hour, .minute], from: selectedEndTime)
                        var endCombinedComponents = DateComponents()
                        endCombinedComponents.year = endDateComponents.year
                        endCombinedComponents.month = endDateComponents.month
                        endCombinedComponents.day = endDateComponents.day
                        endCombinedComponents.hour = endTimeComponents.hour
                        endCombinedComponents.minute = endTimeComponents.minute
                        endTimeToSave = calendar.date(from: endCombinedComponents) ?? selectedEndTime
                    } else {
                        endTimeToSave = selectedEndTime
                    }
                } else if isMultiDay {
                    // All-day multi-day event: set end time to end of end date
                    endTimeToSave = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: selectedEndDate)
                }
                
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
                    selectedTagId,
                    locationToSave
                )
                
                if createAnother {
                    // Reset form for next event
                    title = ""
                    location = ""
                    description = ""
                    // Keep multi-day state, but advance dates
                    let nextDate = isMultiDay ? selectedEndDate.addingTimeInterval(86400) : selectedDate.addingTimeInterval(86400)
                    selectedDate = nextDate
                    if isMultiDay {
                        selectedEndDate = nextDate
                    }
                    // Reset times to default
                    let calendar = Calendar.current
                    let defaultTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextDate) ?? Date()
                    selectedTime = defaultTime
                    selectedEndTime = defaultTime.addingTimeInterval(3600)
                    // Keep other settings as they might be useful for creating similar events
                    // isRecurring, recurrenceFrequency, customRecurrenceDays, selectedReminder, selectedTagId remain
                } else {
                    isPresented = false
                }
            }) {
                Text("Create Event")
                .font(FontManager.geist(size: 15, weight: .semibold))
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

                // Create Another Toggle
                HStack {
                    Toggle("Create Another", isOn: $createAnother)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
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
            onSave: { title, description, date, time, endTime, reminder, recurring, frequency, customDays, tagId, location in
                print("Created: \(title), Description: \(description ?? "None"), Location: \(location ?? "None")")
            }
        )
    }
}
