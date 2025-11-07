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

    private var formatTimeWithAMPM(_ date: Date) -> String {
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
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        Divider()
                            .opacity(0.5)

                        // Tag Selector
                        Button(action: { showingTagOptions.toggle() }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Tag")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(secondaryTextColor)

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
                                                .fill(Color.gray)
                                                .frame(width: 8, height: 8)
                                            Text("Personal")
                                                .font(.system(size: 14))
                                                .foregroundColor(textColor)
                                        }
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
                                            Text(recurrenceFrequency.rawValue.capitalized)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(textColor)
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
                                        colorScheme: colorScheme
                                    )
                                    .presentationDetents([.height(300)])
                                }
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
                        .foregroundColor(.white)
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

#Preview {
    @State var title = ""
    @State var description = ""
    @State var selectedDate = Date()
    @State var hasTime = false
    @State var selectedTime = Date()
    @State var selectedEndTime = Date().addingTimeInterval(3600)
    @State var isRecurring = false
    @State var recurrenceFrequency: RecurrenceFrequency = .weekly
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
            selectedReminder: $selectedReminder,
            selectedTagId: $selectedTagId
        )
    }
}
