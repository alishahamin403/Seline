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
    @State private var selectedReminder: ReminderTime = .oneHour  // Default to 1 hour before
    @State private var selectedTagId: String? = nil  // nil means "Personal" default
    @State private var showingRecurrenceOptions: Bool = false
    @State private var showingReminderOptions: Bool = false
    @State private var showingTagOptions: Bool = false
    @StateObject private var tagManager = TagManager.shared
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isTitleFocused: Bool

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

        // Initialize state variables
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

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            // Glassy card
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("New Event")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Spacer()

                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.shadcnMuted(colorScheme))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                ScrollView {
                    VStack(spacing: 28) {
                        // Title Input - Minimal style
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Event name", text: $title)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .padding(.bottom, 8)
                                .overlay(
                                    VStack(spacing: 0) {
                                        Spacer()
                                        Divider()
                                            .opacity(isTitleFocused ? 1 : 0.3)
                                    }
                                )
                                .focused($isTitleFocused)

                            TextField("Add details (optional)", text: $description, axis: .vertical)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundColor(Color.shadcnMuted(colorScheme))
                                .lineLimit(2...4)
                        }

                        Divider()
                            .opacity(0.2)

                        // Date & Time - Compact
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color.shadcnMuted(colorScheme))

                                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                    .datePickerStyle(CompactDatePickerStyle())
                                    .labelsHidden()

                                Spacer()
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                Toggle(isOn: $hasTime) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "clock")
                                            .font(.system(size: 14, weight: .medium))
                                        Text("Specific time")
                                            .font(.system(size: 15, weight: .regular))
                                    }
                                }
                                .tint(colorScheme == .dark ? Color.white : Color.black)

                                if hasTime {
                                    VStack(spacing: 12) {
                                        HStack {
                                            Text("From")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(Color.shadcnMuted(colorScheme))
                                            Spacer()
                                            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                                .datePickerStyle(WheelDatePickerStyle())
                                                .labelsHidden()
                                                .onChange(of: selectedTime) { newStartTime in
                                                    selectedEndTime = newStartTime.addingTimeInterval(3600)
                                                }
                                        }

                                        HStack {
                                            Text("To")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(Color.shadcnMuted(colorScheme))
                                            Spacer()
                                            DatePicker("", selection: $selectedEndTime, displayedComponents: .hourAndMinute)
                                                .datePickerStyle(WheelDatePickerStyle())
                                                .labelsHidden()
                                        }
                                    }
                                    .padding(.top, 8)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }

                        Divider()
                            .opacity(0.2)

                        // Tag Selector - Minimal
                        VStack(alignment: .leading, spacing: 12) {
                            Button(action: { showingTagOptions.toggle() }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "tag")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Color.shadcnMuted(colorScheme))

                                    HStack(spacing: 8) {
                                        if let tagId = selectedTagId, let tag = tagManager.getTag(by: tagId) {
                                            Circle()
                                                .fill(tag.color)
                                                .frame(width: 8, height: 8)
                                            Text(tag.name)
                                        } else {
                                            Circle()
                                                .fill(Color.blue)
                                                .frame(width: 8, height: 8)
                                            Text("Personal")
                                        }
                                    }
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(Color.shadcnForeground(colorScheme))

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color.shadcnMuted(colorScheme))
                                }
                                .contentShape(Rectangle())
                            }
                            .sheet(isPresented: $showingTagOptions) {
                                TagSelectionSheet(
                                    selectedTagId: $selectedTagId,
                                    colorScheme: colorScheme
                                )
                                .presentationDetents([.height(300)])
                            }
                        }

                        // Options - Toggles only
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: $isRecurring) {
                                HStack(spacing: 8) {
                                    Image(systemName: "repeat")
                                        .font(.system(size: 14, weight: .medium))
                                    Text("Repeat event")
                                        .font(.system(size: 15, weight: .regular))
                                }
                            }
                            .tint(colorScheme == .dark ? Color.white : Color.black)

                            if isRecurring {
                                Button(action: { showingRecurrenceOptions.toggle() }) {
                                    HStack {
                                        Text("Every")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Color.shadcnMuted(colorScheme))

                                        Text(recurrenceFrequency.rawValue.capitalized)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(Color.shadcnForeground(colorScheme))

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Color.shadcnMuted(colorScheme))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            Button(action: { showingReminderOptions.toggle() }) {
                                HStack(spacing: 10) {
                                    Image(systemName: selectedReminder.icon)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(selectedReminder == .none ? Color.shadcnMuted(colorScheme) : Color.shadcnForeground(colorScheme))

                                    Text(selectedReminder.displayName)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(Color.shadcnForeground(colorScheme))

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color.shadcnMuted(colorScheme))
                                }
                                .contentShape(Rectangle())
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }

                // Action Buttons - Minimal
                HStack(spacing: 16) {
                    Button(action: { isPresented = false }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.shadcnMuted(colorScheme))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }

                    Button(action: {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                        let descriptionToSave = trimmedDescription.isEmpty ? nil : trimmedDescription
                        let timeToSave = hasTime ? selectedTime : nil
                        let endTimeToSave = hasTime ? selectedEndTime : nil
                        let reminderToSave = selectedReminder == .none ? nil : selectedReminder

                        onSave(
                            trimmedTitle,
                            descriptionToSave,
                            selectedDate,
                            timeToSave,
                            endTimeToSave,
                            reminderToSave,
                            isRecurring,
                            isRecurring ? recurrenceFrequency : nil,
                            selectedTagId
                        )
                        isPresented = false
                    }) {
                        Text("Create")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isValidInput ?
                                        (colorScheme == .dark ?
                                            Color.white :
                                            Color.black) :
                                        Color.gray.opacity(0.4))
                            )
                    }
                    .disabled(!isValidInput)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.black.opacity(0.4) : Color.white.opacity(0.8))
                        .blur(radius: 10)
                )
            }
            .frame(maxWidth: min(UIScreen.main.bounds.width - 32, 480))
            .frame(height: min(UIScreen.main.bounds.height * 0.85, 700))
            .background(
                // Glassy background effect
                ZStack {
                    if colorScheme == .dark {
                        Color.black.opacity(0.7)
                    } else {
                        Color.white.opacity(0.9)
                    }

                    // Blur effect
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
            )
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 10)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasTime)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isRecurring)
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
        .onAppear {
            // Auto-focus title field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTitleFocused = true
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

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Personal (default) option
                Button(action: {
                    selectedTagId = nil
                    dismiss()
                }) {
                    HStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)

                        Text("Personal (Default)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.shadcnForeground(colorScheme))

                        Spacer()

                        if selectedTagId == nil {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(selectedTagId == nil ? Color.shadcnMuted(colorScheme).opacity(0.1) : Color.clear)
                }
                .buttonStyle(PlainButtonStyle())

                Divider()

                // User-created tags
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
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(Color.shadcnForeground(colorScheme))

                                    Spacer()

                                    if selectedTagId == tag.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(tag.color)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(selectedTagId == tag.id ? tag.color.opacity(0.1) : Color.clear)
                            }
                            .buttonStyle(PlainButtonStyle())

                            if tag.id != tagManager.tags.last?.id {
                                Divider()
                            }
                        }
                    }
                }

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
                    .foregroundColor(Color.blue)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.blue
            .ignoresSafeArea()

        AddEventPopupView(
            isPresented: .constant(true),
            onSave: { title, description, date, time, endTime, reminder, recurring, frequency, tagId in
                print("Created: \(title), Description: \(description ?? "None"), TagID: \(tagId ?? "Personal")")
            }
        )
    }
}
