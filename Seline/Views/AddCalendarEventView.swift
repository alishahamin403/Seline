//
//  AddCalendarEventView.swift
//  Seline
//
//  Created by Claude Code on 2025-09-04.
//

import SwiftUI

struct AddCalendarEventView: View {
    let title: String
    let description: String?
    let start: Date
    let end: Date
    let location: String?
    
    @Environment(\.dismiss) private var dismiss
    @State private var eventTitle: String
    @State private var eventDescription: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var eventLocation: String
    @State private var isAllDay: Bool = false
    @State private var isLoading: Bool = false
    
    init(title: String = "", description: String? = nil, start: Date = Date(), end: Date = Date().addingTimeInterval(3600), location: String? = nil) {
        self.title = title
        self.description = description
        self.start = start
        self.end = end
        self.location = location
        
        self._eventTitle = State(initialValue: title)
        self._eventDescription = State(initialValue: description ?? "")
        self._startDate = State(initialValue: start)
        self._endDate = State(initialValue: end)
        self._eventLocation = State(initialValue: location ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    TextField("Event Title", text: $eventTitle)
                    TextField("Description", text: $eventDescription, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                
                Section("Date & Time") {
                    Toggle("All Day", isOn: $isAllDay)
                    
                    DatePicker("Start", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    
                    if !isAllDay {
                        DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
                Section("Location") {
                    TextField("Add Location", text: $eventLocation)
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await createEvent()
                        }
                    }
                    .disabled(eventTitle.isEmpty || isLoading)
                }
            }
        }
    }
    
    private func createEvent() async {
        isLoading = true
        
        do {
            let event = CalendarEvent(
                title: eventTitle,
                description: eventDescription.isEmpty ? nil : eventDescription,
                startDate: startDate,
                endDate: isAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: startDate) ?? endDate : endDate,
                location: eventLocation.isEmpty ? nil : eventLocation,
                isAllDay: isAllDay
            )
            
            // In a real implementation, this would save to CalendarService
            _ = try await CalendarService.shared.createEvent(event)
            
            await MainActor.run {
                dismiss()
            }
        } catch {
            // Handle error - in a real implementation would show error alert
            print("Error creating event: \(error)")
        }
        
        isLoading = false
    }
}