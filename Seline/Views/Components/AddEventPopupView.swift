import SwiftUI

struct AddEventPopupView: View {
    @Binding var isPresented: Bool
    let onSave: (String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, String?) -> Void

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
    @State private var selectedReminder: ReminderTime = .none
    @State private var selectedTagId: String? = nil
    @State private var showingRecurrenceOptions: Bool = false
    @State private var showingReminderOptions: Bool = false
    @State private var showingTagOptions: Bool = false
    @State private var showingStartTimePicker: Bool = false
    @State private var showingEndTimePicker: Bool = false
    @StateObject private var tagManager = TagManager.shared
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var taskManager = TaskManager.shared

    init(
        isPresented: Binding<Bool>,
        onSave: @escaping (String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, String?) -> Void,
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

    private func formatTimeWithAMPM(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Title Input Section
    private var titleInputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Event Title")
                .font(.system(size: 14, weight: .semibold))
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

    // MARK: - Description Input Section
    private var descriptionInputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Description (Optional)")
                .font(.system(size: 14, weight: .semibold))
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

    // MARK: - Tag Selector Section
    private var tagSelectorSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tag (Optional)")
                .font(.system(size: 14, weight: .semibold))
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

    // MARK: - Date Picker Section
    private var datePickerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Date")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

            HStack {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(CompactDatePickerStyle())
                    .labelsHidden()

                Spacer()
            }
        }
    }

    // MARK: - Time Toggle Section
    private var timeToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Include Time", isOn: $hasTime)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()
            }

            if hasTime {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Button(action: { showingStartTimePicker = true }) {
                            HStack {
                                Text(formatTimeWithAMPM(selectedTime))
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
                                    .fill(colorScheme == .dark ? Color.black : Color(UIColor.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sheet(isPresented: $showingStartTimePicker) {
                            EventTimePickerSheet(selectedTime: $selectedTime, colorScheme: colorScheme, title: "Start Time")
                                .presentationDetents([.height(350)])
                        }
                        .onChange(of: selectedTime) { newStartTime in
                            selectedEndTime = newStartTime.addingTimeInterval(3600)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("End")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Button(action: { showingEndTimePicker = true }) {
                            HStack {
                                Text(formatTimeWithAMPM(selectedEndTime))
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
                                    .fill(colorScheme == .dark ? Color.black : Color(UIColor.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .sheet(isPresented: $showingEndTimePicker) {
                            EventTimePickerSheet(selectedTime: $selectedEndTime, colorScheme: colorScheme, title: "End Time")
                                .presentationDetents([.height(350)])
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Recurring Toggle Section
    private var recurringToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Repeat Event", isOn: $isRecurring)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()
            }

            if isRecurring {
                Button(action: { showingRecurrenceOptions.toggle() }) {
                    HStack {
                        Text("Every")
                            .font(.system(size: 13))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                        Text(recurrenceFrequency.rawValue.capitalized)
                            .font(.system(size: 13, weight: .semibold))
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Reminder Picker Section
    private var reminderPickerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Reminder (Optional)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                if !hasTime {
                    Text("All-day events don't have reminders")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
            }

            Button(action: { if hasTime { showingReminderOptions.toggle() } }) {
                HStack {
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
                        .fill(hasTime ?
                            (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)) :
                            (colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.02)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(hasTime ? 0.15 : 0.08), lineWidth: 0.8)
                )
            }
            .disabled(!hasTime)
            .opacity(hasTime ? 1.0 : 0.6)
            .sheet(isPresented: $showingReminderOptions) {
                ReminderOptionsSheet(
                    selectedReminder: $selectedReminder,
                    colorScheme: colorScheme
                )
                .presentationDetents([.height(350)])
            }
        }
    }

    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: { isPresented = false }) {
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }

            Button(action: {
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                let descriptionToSave = trimmedDescription.isEmpty ? nil : trimmedDescription
                let timeToSave = hasTime ? selectedTime : nil
                let endTimeToSave = hasTime ? selectedEndTime : nil

                onSave(
                    trimmedTitle,
                    descriptionToSave,
                    selectedDate,
                    timeToSave,
                    endTimeToSave,
                    selectedReminder == .none ? nil : selectedReminder,
                    isRecurring,
                    isRecurring ? recurrenceFrequency : nil,
                    selectedTagId
                )
                isPresented = false
            }) {
                Text("Create Event")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isValidInput ? (colorScheme == .dark ? Color.white : Color.black) : Color.gray.opacity(0.3))
                    )
            }
            .disabled(!isValidInput)
        }
    }

    var body: some View {
        NavigationView {
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
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .sheet(isPresented: $showingRecurrenceOptions) {
                RecurringOptionsSheet(
                    selectedFrequency: $recurrenceFrequency,
                    colorScheme: colorScheme
                )
                .presentationDetents([.height(300)])
            }
            .sheet(isPresented: $showingReminderOptions) {
                ReminderOptionsSheet(
                    selectedReminder: $selectedReminder,
                    colorScheme: colorScheme
                )
                .presentationDetents([.height(350)])
            }
        }
    }
}

struct TagSelectionSheet: View {
    @Binding var selectedTagId: String?
    let colorScheme: ColorScheme
    @StateObject private var tagManager = TagManager.shared
    @State private var newTagName = ""
    @Environment(\.dismiss) var dismiss

    // MARK: - Create New Tag Section
    private var createNewTagSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Create new tag...", text: $newTagName)
                    .font(.system(size: 14))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                Button(action: {
                    if !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let newTag = tagManager.createTag(name: newTagName) {
                            selectedTagId = newTag.id
                            newTagName = ""
                            dismiss()
                        }
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.5) : (colorScheme == .dark ? Color.white : Color.black))
                }
                .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .border(Color.gray.opacity(0.2), width: 1)
    }

    // MARK: - Personal Tag Section
    private var personalTagSection: some View {
        Button(action: {
            selectedTagId = nil
            dismiss()
        }) {
            HStack {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 12, height: 12)

                Text("Personal (Default)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()

                if selectedTagId == nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(selectedTagId == nil ? Color.gray.opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - User Tags Section
    private var userTagsSection: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(tagManager.tags, id: \.id) { tag in
                    Button(action: {
                        selectedTagId = tag.id
                        dismiss()
                    }) {
                        HStack {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 12, height: 12)

                            Text(tag.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Spacer()

                            if selectedTagId == tag.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(tag.color)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(selectedTagId == tag.id ? tag.color.opacity(0.1) : Color.clear)
                    }
                    .buttonStyle(PlainButtonStyle())

                    if tag.id != tagManager.tags.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                createNewTagSection

                personalTagSection

                Divider()

                userTagsSection

                Spacer()
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationTitle("Select Tag")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
            }
        }
    }
}

// MARK: - Time Picker Sheet for Events
struct EventTimePickerSheet: View {
    @Binding var selectedTime: Date
    let colorScheme: ColorScheme
    let title: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                DatePicker(
                    "",
                    selection: $selectedTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding(.vertical, 20)

                Spacer()

                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                        )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ZStack {
        Color.gray
            .ignoresSafeArea()

        AddEventPopupView(
            isPresented: .constant(true),
            onSave: { title, description, date, time, endTime, reminder, recurring, frequency, tagId in
                print("Created: \(title), Description: \(description ?? "None"), TagID: \(tagId ?? "Personal")")
            }
        )
    }
}
