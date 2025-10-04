import SwiftUI

struct AddEventPopupView: View {
    @Binding var isPresented: Bool
    let onSave: (String, Date, Date?, ReminderTime?, Bool, RecurrenceFrequency?) -> Void

    @State private var title: String = ""
    @State private var selectedDate: Date = Date()
    @State private var hasTime: Bool = false
    @State private var selectedTime: Date = Date()
    @State private var isRecurring: Bool = false
    @State private var recurrenceFrequency: RecurrenceFrequency = .weekly
    @State private var selectedReminder: ReminderTime = .oneHour  // Default to 1 hour before
    @State private var showingRecurrenceOptions: Bool = false
    @State private var showingReminderOptions: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isTitleFocused: Bool

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
                    VStack(spacing: 20) {
                        // Title Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.shadcnMuted(colorScheme))

                            TextField("What's the event?", text: $title)
                                .font(.system(size: 16))
                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            isTitleFocused ?
                                                (colorScheme == .dark ?
                                                    Color(red: 0.518, green: 0.792, blue: 0.914) :
                                                    Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                                Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                                .focused($isTitleFocused)
                        }

                        // Date & Time
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Date & Time")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.shadcnMuted(colorScheme))

                            DatePicker("", selection: $selectedDate, displayedComponents: .date)
                                .datePickerStyle(CompactDatePickerStyle())
                                .labelsHidden()

                            Toggle("Add specific time", isOn: $hasTime)
                                .font(.system(size: 15))
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            if hasTime {
                                DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(WheelDatePickerStyle())
                                    .labelsHidden()
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }

                        // Recurring
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Recurring event", isOn: $isRecurring)
                                .font(.system(size: 15))
                                .foregroundColor(Color.shadcnForeground(colorScheme))

                            if isRecurring {
                                Button(action: {
                                    showingRecurrenceOptions.toggle()
                                }) {
                                    HStack {
                                        Text("Repeat")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Color.shadcnMuted(colorScheme))

                                        Spacer()

                                        Text(recurrenceFrequency.rawValue.capitalized)
                                            .font(.system(size: 15))
                                            .foregroundColor(Color.shadcnForeground(colorScheme))

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color.shadcnMuted(colorScheme))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                                    )
                                }
                                .transition(.opacity.combined(with: .scale))
                            }
                        }

                        // Reminder
                        VStack(alignment: .leading, spacing: 8) {
                            Button(action: {
                                showingReminderOptions.toggle()
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Reminder")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Color.shadcnMuted(colorScheme))

                                        HStack(spacing: 8) {
                                            Image(systemName: selectedReminder.icon)
                                                .font(.system(size: 14))
                                                .foregroundColor(selectedReminder == .none ? Color.shadcnMuted(colorScheme) : (colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40)))

                                            Text(selectedReminder.displayName)
                                                .font(.system(size: 15))
                                                .foregroundColor(Color.shadcnForeground(colorScheme))
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.shadcnMuted(colorScheme))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                // Action Buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.shadcnForeground(colorScheme))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )

                    Button("Create") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let timeToSave = hasTime ? selectedTime : nil
                        let reminderToSave = selectedReminder == .none ? nil : selectedReminder

                        onSave(
                            trimmedTitle,
                            selectedDate,
                            timeToSave,
                            reminderToSave,
                            isRecurring,
                            isRecurring ? recurrenceFrequency : nil
                        )
                        isPresented = false
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isValidInput ?
                                (colorScheme == .dark ?
                                    Color(red: 0.518, green: 0.792, blue: 0.914) :
                                    Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                Color.gray.opacity(0.5))
                    )
                    .disabled(!isValidInput)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.5))
                        .blur(radius: 20)
                )
            }
            .frame(maxWidth: min(UIScreen.main.bounds.width - 32, 480))
            .frame(maxHeight: min(UIScreen.main.bounds.height * 0.8, 600))
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

#Preview {
    ZStack {
        Color.blue
            .ignoresSafeArea()

        AddEventPopupView(
            isPresented: .constant(true),
            onSave: { title, date, time, reminder, recurring, frequency in
                print("Created: \(title)")
            }
        )
    }
}
