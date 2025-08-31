//
//  AddCalendarEventView.swift
//  Seline
//
//  Created by Claude on 2025-08-31.
//

import SwiftUI
import Foundation

struct AddCalendarEventView: View {
    private let calendarService = CalendarService.shared
    @Environment(\.dismiss) private var dismiss
    
    // Optional initialization parameters for voice input
    init(
        title: String = "",
        description: String? = nil,
        start: Date = Date(),
        end: Date = Date().addingTimeInterval(3600),
        location: String? = nil,
        isAllDay: Bool = false
    ) {
        self._title = State(initialValue: title)
        self._description = State(initialValue: description ?? "")
        self._startDate = State(initialValue: start)
        self._endDate = State(initialValue: end)
        self._location = State(initialValue: location ?? "")
        self._isAllDay = State(initialValue: isAllDay)
    }
    
    @State private var title: String
    @State private var description: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var location: String
    @State private var isAllDay: Bool
    @State private var isCreating: Bool = false
    @State private var showingError: Bool = false
    @State private var showingSuccess: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Event Details") {
                    TextField("Event Title", text: $title)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .lineLimit(3...6)
                    
                    TextField("Location (optional)", text: $location)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                }
                
                Section("Date & Time") {
                    Toggle("All Day", isOn: $isAllDay)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .onChange(of: isAllDay) { allDay in
                            if allDay {
                                // Set to start of day for all-day events
                                let calendar = Calendar.current
                                startDate = calendar.startOfDay(for: startDate)
                                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
                            }
                        }
                    
                    DatePicker("Starts", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .onChange(of: startDate) { newStart in
                            // Auto-adjust end date if it's before start date
                            if endDate <= newStart {
                                endDate = newStart.addingTimeInterval(isAllDay ? 86400 : 3600) // 1 day or 1 hour
                            }
                        }
                    
                    DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                }
                
                Section {
                    HStack {
                        Image(systemName: "cloud.fill")
                            .foregroundColor(DesignSystem.Colors.accent)
                            .font(.system(size: 14))
                        
                        Text("This event will be synced with your Google Calendar")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Events are automatically synced with your connected Google account.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        createEvent()
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                    .disabled(title.isEmpty || isCreating)
                }
            }
            .disabled(isCreating)
        }
        .alert("Error Creating Event", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Event Created! ✅", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your calendar event '\(title)' has been created successfully and synced with Google Calendar.")
        }
    }
    
    // MARK: - Prefill Initializer
    init(title: String? = nil, description: String? = nil, start: Date? = nil, end: Date? = nil, location: String? = nil, isAllDay: Bool = false) {
        // Initialize State wrappers
        _title = State(initialValue: title ?? "")
        _description = State(initialValue: description ?? "")
        let defaultStart = start ?? Date()
        var computedEnd: Date
        if let end = end {
            computedEnd = end
        } else {
            computedEnd = defaultStart.addingTimeInterval(3600)
        }
        _startDate = State(initialValue: defaultStart)
        _endDate = State(initialValue: computedEnd)
        _location = State(initialValue: location ?? "")
        _isAllDay = State(initialValue: isAllDay)
    }

    private func createEvent() {
        guard !title.isEmpty else { return }
        
        isCreating = true
        
        Task {
            do {
                let _ = try await calendarService.createEvent(
                    title: title,
                    description: description.isEmpty ? nil : description,
                    startDate: startDate,
                    endDate: endDate,
                    location: location.isEmpty ? nil : location
                )
                
                await MainActor.run {
                    showingSuccess = true
                    
                    // Dismiss after showing success briefly
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                }
                
                ProductionLogger.logAppEvent("📅 Calendar event created: \(title)")
                ProductionLogger.debug("Calendar event details - Title: \(title), HasDescription: \(!description.isEmpty), HasLocation: \(!location.isEmpty), IsAllDay: \(isAllDay)", category: "calendar")
                
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showingError = true
                    
                    ProductionLogger.logError(error, context: "Failed to create calendar event")
                }
            }
        }
    }
}

#Preview {
    AddCalendarEventView()
        .preferredColorScheme(.dark)
}