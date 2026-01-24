import SwiftUI

// MARK: - Event Creation Sheet from Note
// Shows when user taps calendar icon on a detected date in notes
struct NoteEventCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var eventTitle: String
    @State private var eventDate: Date
    @State private var eventEndDate: Date
    @State private var eventDescription: String = ""
    @State private var hasEndTime: Bool = false
    
    var onSave: (String, Date, Date?, String) -> Void
    var onCancel: () -> Void
    
    init(eventTitle: String, eventDate: Date, onSave: @escaping (String, Date, Date?, String) -> Void, onCancel: @escaping () -> Void) {
        _eventTitle = State(initialValue: eventTitle)
        _eventDate = State(initialValue: eventDate)
        _eventEndDate = State(initialValue: eventDate.addingTimeInterval(3600))
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Event Title")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Event name", text: $eventTitle)
                        .font(FontManager.geist(size: 16, weight: .regular))
                        .padding(12)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        .cornerRadius(10)
                }
                
                // Start Date & Time
                VStack(alignment: .leading, spacing: 6) {
                    Text("Date & Time")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    DatePicker("", selection: $eventDate, displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .padding(12)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        .cornerRadius(10)
                }
                
                // End Time Toggle
                Toggle("Add End Time", isOn: $hasEndTime)
                    .padding(.horizontal, 4)
                
                if hasEndTime {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("End Time")
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        DatePicker("", selection: $eventEndDate, displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .padding(12)
                            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                            .cornerRadius(10)
                    }
                }
                
                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Description (Optional)")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Add details...", text: $eventDescription, axis: .vertical)
                        .lineLimit(3...5)
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .padding(12)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        .cornerRadius(10)
                }
                
                Spacer()
                
                // Save Button
                Button(action: {
                    let endDate = hasEndTime ? eventEndDate : nil
                    onSave(eventTitle, eventDate, endDate, eventDescription)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "calendar.badge.plus")
                        Text("Create Event")
                    }
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .disabled(eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
            .navigationTitle("Create Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }
}
