import SwiftUI

struct EventFormContent: View {
    // MARK: - Bindings
    @Binding var title: String
    @Binding var description: String
    @Binding var selectedDate: Date
    @Binding var hasTime: Bool
    @Binding var selectedTime: Date
    @Binding var selectedEndTime: Date
    @Binding var isRecurring: Bool
    @Binding var recurrenceFrequency: RecurrenceFrequency
    @Binding var customRecurrenceDays: Set<WeekDay>
    @Binding var selectedReminder: ReminderTime
    @Binding var selectedTagId: String?

    // MARK: - State
    @State private var showingStartTimePicker = false
    @State private var showingEndTimePicker = false
    @State private var showingRecurrenceOptions = false
    @State private var showingReminderOptions = false
    @State private var showingTagOptions = false

    // MARK: - Managers
    @StateObject private var tagManager = TagManager.shared

    // MARK: - Environment
    @Environment(\.colorScheme) var colorScheme

    var isValidInput: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sectionBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)
    }

    private var textColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
    }

    private var fieldBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    private func formatTimeWithAMPM(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - View Components

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Basic Info Section
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Basic Info")

                    VStack(spacing: 12) {
                        // Title Input
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Event Title")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(secondaryTextColor)

                            TextField("Enter event title", text: $title)
                                .font(.system(size: 15))
                                .foregroundColor(textColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(fieldBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
                                )
                        }

                        // Description Input
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Description (Optional)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(secondaryTextColor)

                            TextField("Add details...", text: $description, axis: .vertical)
                                .font(.system(size: 14))
                                .foregroundColor(textColor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .lineLimit(2...3)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(fieldBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
                                )
                        }
                    }
                    .padding(14)
                    .background(sectionBackground)
                    .cornerRadius(12)
                }

                // MARK: - Details Section
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Details")

                    VStack(spacing: 12) {
                        // Date Picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Date")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(secondaryTextColor)

                            HStack {
                                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                    .datePickerStyle(CompactDatePickerStyle())
                                    .labelsHidden()
                                Spacer()
                            }
                        }

                        Divider()
                            .opacity(0.5)

                        // Time Toggle
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Toggle("Include Time", isOn: $hasTime)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(textColor)
                                Spacer()
                            }

                            if hasTime {
                                VStack(spacing: 10) {
                                    // Start Time
                                    Button(action: { showingStartTimePicker = true }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Start Time")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(secondaryTextColor)
                                                Text(formatTimeWithAMPM(selectedTime))
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(textColor)
                                            }

                                            Spacer()

                                            Image(systemName: "clock.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(secondaryTextColor)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(fieldBackground)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
                                        )
                                    }
                                    .sheet(isPresented: $showingStartTimePicker) {
                                        UnifiedTimePickerSheet(
                                            selectedTime: $selectedTime,
                                            colorScheme: colorScheme,
                                            title: "Start Time",
                                            onTimeChange: { newStartTime in
                                                selectedEndTime = newStartTime.addingTimeInterval(3600)
                                            }
                                        )
                                    }
                                .presentationBg()

                                    // End Time
                                    Button(action: { showingEndTimePicker = true }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("End Time")
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(secondaryTextColor)
                                                Text(formatTimeWithAMPM(selectedEndTime))
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundColor(textColor)
                                            }

                                            Spacer()

                                            Image(systemName: "clock.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(secondaryTextColor)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                        .background(fieldBackground)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
                                        )
                                    }
                                    .sheet(isPresented: $showingEndTimePicker) {
                                        UnifiedTimePickerSheet(
                                            selectedTime: $selectedEndTime,
                                            colorScheme: colorScheme,
                                            title: "End Time"
                                        )
                                    }
                                .presentationBg()
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        Divider()
                            .opacity(0.5)

                        // Tag Selector
                        Button(action: { showingTagOptions.toggle() }) {
                            HStack {
                                HStack(spacing: 6) {
                                        if let tagId = selectedTagId, let tag = tagManager.getTag(by: tagId) {
                                            Circle()
                                                .fill(tag.color)
                                                .frame(width: 8, height: 8)
                                            Text(tag.name)
                                                .font(.system(size: 14))
                                                .foregroundColor(textColor)
                                        } else {
                                            Circle()
                                                .fill(Color.gray.opacity(0.5))
                                                .frame(width: 8, height: 8)
                                            Text("Personal")
                                                .font(.system(size: 14))
                                                .foregroundColor(textColor)
                                        }
                                    }

                                Spacer()

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(secondaryTextColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(fieldBackground)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
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
                    .presentationBg()
                    }
                    .padding(14)
                    .background(sectionBackground)
                    .cornerRadius(12)
                }

                // MARK: - Advanced Section
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Advanced")

                    VStack(spacing: 12) {
                        // Recurring Toggle
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Toggle("Repeat Event", isOn: $isRecurring)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(textColor)
                                Spacer()
                            }

                            if isRecurring {
                                Button(action: { showingRecurrenceOptions.toggle() }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Frequency")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(secondaryTextColor)
                                            Text(recurrenceFrequency == .custom && !customRecurrenceDays.isEmpty ?
                                                customRecurrenceDays.sorted(by: { $0.sortOrder < $1.sortOrder }).map { $0.shortDisplayName }.joined(separator: ", ") :
                                                recurrenceFrequency.rawValue.capitalized)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(textColor)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 12))
                                            .foregroundColor(secondaryTextColor)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(fieldBackground)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
                                    )
                                }
                                .sheet(isPresented: $showingRecurrenceOptions) {
                                    RecurringOptionsSheet(
                                        selectedFrequency: $recurrenceFrequency,
                                        customRecurrenceDays: $customRecurrenceDays,
                                        colorScheme: colorScheme
                                    )
                                    .presentationDetents([.height(recurrenceFrequency == .custom ? 450 : 300)])
                                }
                            .presentationBg()
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        Divider()
                            .opacity(0.5)

                        // Reminder Selector
                        Button(action: { if hasTime { showingReminderOptions.toggle() } }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("Reminder")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(secondaryTextColor)

                                        if !hasTime {
                                            Text("(Requires time)")
                                                .font(.system(size: 10, weight: .regular))
                                                .foregroundColor(Color.gray.opacity(0.6))
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        Image(systemName: selectedReminder.icon)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(selectedReminder == .none ? Color.gray : textColor)

                                        Text(selectedReminder.displayName)
                                            .font(.system(size: 14))
                                            .foregroundColor(textColor)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(secondaryTextColor)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(hasTime ? fieldBackground : fieldBackground.opacity(0.5))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
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
                    .presentationBg()
                    }
                    .padding(14)
                    .background(sectionBackground)
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Section Header Component
struct SectionHeader: View {
    let title: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            .padding(.horizontal, 4)
    }
}

// MARK: - Unified Time Picker Sheet
struct UnifiedTimePickerSheet: View {
    @Binding var selectedTime: Date
    let colorScheme: ColorScheme
    let title: String
    var onTimeChange: ((Date) -> Void)? = nil
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

                Button(action: {
                    onTimeChange?(selectedTime)
                    dismiss()
                }) {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Tag Selection Sheet
struct TagSelectionSheet: View {
    @Binding var selectedTagId: String?
    let colorScheme: ColorScheme
    @StateObject private var tagManager = TagManager.shared
    @State private var newTagName = ""
    @Environment(\.dismiss) var dismiss

    private var createNewTagSection: some View {
        HStack(spacing: 10) {
            TextField("Create new tag...", text: $newTagName)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
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
                    .foregroundColor(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : (colorScheme == .dark ? Color.white : Color.black))
            }
            .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
    }

    private var personalTagSection: some View {
        Button(action: {
            selectedTagId = nil
            dismiss()
        }) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(red: 0.2039, green: 0.6588, blue: 0.3255))
                    .frame(width: 12, height: 12)

                Text("Personal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()

                if selectedTagId == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 0.2039, green: 0.6588, blue: 0.3255))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTagId == nil ? Color(red: 0.2039, green: 0.6588, blue: 0.3255).opacity(0.1) : (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedTagId == nil ? Color(red: 0.2039, green: 0.6588, blue: 0.3255).opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
    }

    private var userTagsSection: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(tagManager.tags, id: \.id) { tag in
                    Button(action: {
                        selectedTagId = tag.id
                        dismiss()
                    }) {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 12, height: 12)

                            Text(tag.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            Spacer()

                            if selectedTagId == tag.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(tag.color)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTagId == tag.id ? tag.color.opacity(0.1) : (colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTagId == tag.id ? tag.color.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 8) {
                createNewTagSection

                personalTagSection

                userTagsSection

                Spacer()
            }
            .padding(.vertical, 8)
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

// MARK: - Custom Day Button
struct CustomDayButton: View {
    let day: WeekDay
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onTap: () -> Void
    
    private var foregroundColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.black : Color.white
        } else {
            return colorScheme == .dark ? Color.white : Color.black
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return colorScheme == .dark ? Color.white : Color.black
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
        }
    }
    
    private var strokeColor: Color {
        isSelected ? Color.clear : Color.gray.opacity(0.2)
    }
    
    var body: some View {
        Button(action: onTap) {
            Text(day.shortDisplayName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(backgroundColor)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(strokeColor, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recurring Options Sheet
struct RecurringOptionsSheet: View {
    @Binding var selectedFrequency: RecurrenceFrequency
    @Binding var customRecurrenceDays: Set<WeekDay>
    let colorScheme: ColorScheme
    @Environment(\.dismiss) private var dismiss
    
    private var checkmarkColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    private func backgroundForFrequency(_ frequency: RecurrenceFrequency) -> Color {
        if selectedFrequency == frequency {
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
        } else {
            return Color.clear
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { frequency in
                            Button(action: {
                                selectedFrequency = frequency
                                if frequency != .custom {
                                    dismiss()
                                }
                            }) {
                                HStack {
                                    Text(frequency.displayName)
                                        .font(.shadcnTextBase)
                                        .foregroundColor(Color.shadcnForeground(colorScheme))

                                    Spacer()

                                    if selectedFrequency == frequency {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(checkmarkColor)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(backgroundForFrequency(frequency))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Custom day selector (shown when custom is selected)
                        if selectedFrequency == .custom {
                            VStack(alignment: .leading, spacing: 12) {
                                Divider()
                                    .padding(.vertical, 8)

                                Text("Select Days")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                    .padding(.horizontal, 20)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(WeekDay.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { day in
                                        CustomDayButton(
                                            day: day,
                                            isSelected: customRecurrenceDays.contains(day),
                                            colorScheme: colorScheme,
                                            onTap: {
                                                if customRecurrenceDays.contains(day) {
                                                    customRecurrenceDays.remove(day)
                                                } else {
                                                    customRecurrenceDays.insert(day)
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
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
                    .foregroundColor(checkmarkColor)
                    .disabled(selectedFrequency == .custom && customRecurrenceDays.isEmpty)
                }
            }
        }
    }
}

// MARK: - Reminder Options Sheet
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
                                .foregroundColor(reminder == .none ? Color.gray : (colorScheme == .dark ? Color.white : Color.black))
                                .frame(width: 24)

                            Text(reminder.displayName)
                                .font(.shadcnTextBase)
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

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

#Preview {
    @State var title = ""
    @State var description = ""
    @State var selectedDate = Date()
    @State var hasTime = false
    @State var selectedTime = Date()
    @State var selectedEndTime = Date().addingTimeInterval(3600)
    @State var isRecurring = false
    @State var recurrenceFrequency: RecurrenceFrequency = .weekly
    @State var customRecurrenceDays: Set<WeekDay> = []
    @State var selectedReminder: ReminderTime = .none
    @State var selectedTagId: String? = nil

    return ZStack {
        Color.white
            .ignoresSafeArea()

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
    }
}
