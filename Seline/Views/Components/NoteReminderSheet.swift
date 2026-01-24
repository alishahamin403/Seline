import SwiftUI

struct NoteReminderSheet: View {
    let note: Note
    let onSave: (Date, String) -> Void
    let onRemove: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedDate: Date
    @State private var selectedTime: Date
    @State private var reminderNote: String
    @State private var showRemoveConfirmation = false
    
    init(note: Note, onSave: @escaping (Date, String) -> Void, onRemove: @escaping () -> Void) {
        self.note = note
        self.onSave = onSave
        self.onRemove = onRemove
        
        // Initialize with existing reminder or defaults
        let now = Date()
        let calendar = Calendar.current
        
        if let existingReminder = note.reminderDate {
            _selectedDate = State(initialValue: existingReminder)
            _selectedTime = State(initialValue: existingReminder)
        } else {
            // Default to tomorrow at 9 AM
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.day! += 1
            components.hour = 9
            components.minute = 0
            let tomorrow9AM = calendar.date(from: components) ?? now
            
            _selectedDate = State(initialValue: tomorrow9AM)
            _selectedTime = State(initialValue: tomorrow9AM)
        }
        
        _reminderNote = State(initialValue: note.reminderNote ?? "")
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Note title display
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Note")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Text(note.title)
                                .font(FontManager.geist(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                        
                        // Date Picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Remind me on")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            DatePicker("", selection: $selectedDate, in: Date()..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .tint(colorScheme == .dark ? .white : .black)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                        
                        // Time Picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("At time")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            DatePicker("", selection: $selectedTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .frame(height: 100)
                                .clipped()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                        
                        // Reminder Note
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reminder note (optional)")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            TextField("What needs to be done?", text: $reminderNote)
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                        
                        // Quick presets
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quick presets")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                QuickPresetButton(title: "Today 6 PM", icon: "sun.max") {
                                    setPreset(daysFromNow: 0, hour: 18, minute: 0)
                                }
                                
                                QuickPresetButton(title: "Tomorrow 9 AM", icon: "sunrise") {
                                    setPreset(daysFromNow: 1, hour: 9, minute: 0)
                                }
                                
                                QuickPresetButton(title: "In 3 days", icon: "calendar") {
                                    setPreset(daysFromNow: 3, hour: 9, minute: 0)
                                }
                                
                                QuickPresetButton(title: "Next week", icon: "calendar.badge.plus") {
                                    setPreset(daysFromNow: 7, hour: 9, minute: 0)
                                }
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        )
                        
                        // Remove reminder button (if exists)
                        if note.reminderDate != nil {
                            Button(action: {
                                showRemoveConfirmation = true
                            }) {
                                HStack {
                                    Image(systemName: "bell.slash")
                                    Text("Remove Reminder")
                                }
                                .font(FontManager.geist(size: 14, weight: .medium))
                                .foregroundColor(.red)
                            }
                            .padding(.top, 8)
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle(note.reminderDate != nil ? "Edit Reminder" : "Set Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let calendar = Calendar.current
                        let dateComponents = calendar.dateComponents([.year, .month, .day], from: selectedDate)
                        let timeComponents = calendar.dateComponents([.hour, .minute], from: selectedTime)
                        
                        var combined = DateComponents()
                        combined.year = dateComponents.year
                        combined.month = dateComponents.month
                        combined.day = dateComponents.day
                        combined.hour = timeComponents.hour
                        combined.minute = timeComponents.minute
                        
                        if let combinedDate = calendar.date(from: combined) {
                            onSave(combinedDate, reminderNote)
                        }
                        dismiss()
                    }
                    .font(FontManager.geist(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
        .confirmationDialog("Remove Reminder", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                onRemove()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove the reminder for this note?")
        }
    }
    
    private func setPreset(daysFromNow: Int, hour: Int, minute: Int) {
        let calendar = Calendar.current
        let now = Date()
        
        guard let futureDate = calendar.date(byAdding: .day, value: daysFromNow, to: now) else { return }
        var components = calendar.dateComponents([.year, .month, .day], from: futureDate)
        components.hour = hour
        components.minute = minute
        
        if let newDate = calendar.date(from: components) {
            selectedDate = newDate
            selectedTime = newDate
        }
        
        HapticManager.shared.selection()
    }
}

struct QuickPresetButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(FontManager.geist(size: 12, weight: .medium))
            }
            .foregroundColor(colorScheme == .dark ? .white : .black)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            )
        }
    }
}

#Preview {
    NoteReminderSheet(
        note: Note(title: "Test Note", content: "Content"),
        onSave: { _, _ in },
        onRemove: {}
    )
    .preferredColorScheme(.dark)
}
