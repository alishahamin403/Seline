import SwiftUI

struct ReviewExtractedEventsView: View {
    @State private var extractionResponse: CalendarPhotoExtractionResponse
    var onDismiss: () -> Void

    init(extractionResponse: CalendarPhotoExtractionResponse, onDismiss: @escaping () -> Void) {
        _extractionResponse = State(initialValue: extractionResponse)
        self.onDismiss = onDismiss
    }

    @StateObject private var taskManager = TaskManager.shared
    @State private var selectedCalendar: String = "default"
    @State private var isCreatingEvents = false
    @State private var showSuccessScreen = false
    @State private var createdCount = 0

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Review Extracted Events")
                                .font(.title2)
                                .fontWeight(.semibold)

                            if extractionResponse.status == .partial {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.caption)
                                    Text("Some titles unclear")
                                        .font(.caption)
                                }
                                .foregroundColor(.orange)
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemBackground))
                }

                // Events list
                if !showSuccessScreen {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Calendar selector
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Add to Calendar:")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                }

                                Picker("Calendar", selection: $selectedCalendar) {
                                    Text("Default").tag("default")
                                    Text("Work").tag("work")
                                    Text("Personal").tag("personal")
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding(16)
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)

                            // Event list
                            ForEach($extractionResponse.events) { $event in
                                EventReviewCard(event: $event)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }

                    // Actions
                    VStack(spacing: 12) {
                        let selectedCount = extractionResponse.events.filter { $0.isSelected }.count

                        Button(action: { confirmAndCreate() }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Confirm & Create \(selectedCount) Event\(selectedCount == 1 ? "" : "s")")
                                Spacer()
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(height: 50)
                            .frame(maxWidth: .infinity)
                            .background(selectedCount > 0 ? Color.blue : Color.gray)
                            .cornerRadius(12)
                        }
                        .disabled(selectedCount == 0 || isCreatingEvents)

                        Button(action: { onDismiss() }) {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(height: 50)
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(isCreatingEvents)
                    }
                    .padding(16)
                    .background(Color(UIColor.secondarySystemBackground))
                } else {
                    // Success screen
                    VStack(spacing: 20) {
                        Spacer()

                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)

                            VStack(spacing: 8) {
                                Text("✅ \(createdCount) Events Added!")
                                    .font(.title3)
                                    .fontWeight(.semibold)

                                Text("All events added to \(calendarDisplayName())")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                        .multilineTextAlignment(.center)

                        Spacer()

                        VStack(spacing: 12) {
                            Button(action: { onDismiss() }) {
                                Text("Done")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(height: 50)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .overlay(
            Group {
                if isCreatingEvents {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Creating events...")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                    }
                }
            }
        )
    }

    // MARK: - Private Methods

    private func calendarDisplayName() -> String {
        switch selectedCalendar {
        case "work": return "Work"
        case "personal": return "Personal"
        default: return "calendar"
        }
    }

    private func confirmAndCreate() {
        isCreatingEvents = true

        Task {
            var count = 0
            for event in extractionResponse.events where event.isSelected {
                // Create TaskItem from extracted event
                let taskItem = TaskItem(
                    title: event.title,
                    weekday: weekdayFromDate(event.startTime),
                    description: event.notes.isEmpty ? nil : event.notes,
                    scheduledTime: event.startTime,
                    endTime: event.endTime,
                    targetDate: event.startTime,
                    reminderTime: .oneHour
                )

                // Add the task via TaskManager
                taskManager.addTask(taskItem)
                count += 1

                // Small delay to avoid rate limiting
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }

            await MainActor.run {
                createdCount = count
                showSuccessScreen = true
                isCreatingEvents = false

                // Auto-dismiss after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    onDismiss()
                }
            }
        }
    }

    private func weekdayFromDate(_ date: Date) -> WeekDay {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Calendar.Component.weekday: 1 = Sunday, 2 = Monday, etc.
        switch weekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
}

// MARK: - Event Review Card

struct EventReviewCard: View {
    @Binding var event: ExtractedEvent
    @State private var showEditSheet = false

    var body: some View {
        VStack(spacing: 12) {
            // Toggle and title
            HStack(spacing: 12) {
                Toggle("", isOn: $event.isSelected)
                    .labelsHidden()

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(event.title)
                            .font(.headline)
                            .lineLimit(2)

                        if !event.titleConfidence {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    // Time info
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                                .font(.caption)
                            Text(event.formattedTime)
                                .font(.caption)
                        }

                        if let duration = event.durationText {
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                    .font(.caption)
                                Text(duration)
                                    .font(.caption)
                            }
                        }

                        Spacer()
                    }
                    .foregroundColor(.gray)
                }

                Spacer()

                Button(action: { showEditSheet = true }) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }

            // Attendees if present
            if !event.attendees.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(event.attendees.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }

            Divider()

            // Confidence indicator
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        if event.dateConfidence {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Date")
                                    .font(.caption)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Text("Date")
                                    .font(.caption)
                            }
                        }

                        if event.timeConfidence {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text("Time")
                                    .font(.caption)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Text("Time")
                                    .font(.caption)
                            }
                        }

                        Spacer()
                    }
                }
            }
            .font(.caption)
            .foregroundColor(.gray)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .sheet(isPresented: $showEditSheet) {
            EditExtractedEventView(event: $event)
        }
    }
}

// MARK: - Edit Event View

struct EditExtractedEventView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var event: ExtractedEvent

    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var startTime: Date = Date()
    @State private var endDate: Date = Date()
    @State private var endTime: Date = Date()
    @State private var attendees: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Details") {
                    TextField("Title", text: $title)

                    DatePicker("Date", selection: $startDate, displayedComponents: .date)

                    HStack {
                        Text("Time")
                        Spacer()
                        DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }

                Section("End Time (Optional)") {
                    Toggle("Has end time", isOn: .constant(event.endTime != nil))

                    if event.endTime != nil {
                        HStack {
                            Text("Time")
                            Spacer()
                            DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                }

                Section("Attendees (Optional)") {
                    TextField("Names (comma-separated)", text: $attendees)
                }
            }
            .navigationTitle("Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        // Update event
                        event.title = title
                        event.attendees = attendees
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                title = event.title
                startDate = event.startTime
                startTime = event.startTime
                if let endTime = event.endTime {
                    self.endTime = endTime
                    endDate = endTime
                } else {
                    endTime = Calendar.current.date(byAdding: .hour, value: 1, to: startTime) ?? startTime
                    endDate = startDate
                }
                attendees = event.attendees.joined(separator: ", ")
            }
        }
    }
}

#Preview {
    ReviewExtractedEventsView(
        extractionResponse: CalendarPhotoExtractionResponse(
            status: .success,
            events: [
                ExtractedEvent(
                    title: "Team Meeting",
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(3600),
                    attendees: ["Sarah", "Mike"],
                    confidence: 0.95,
                    titleConfidence: true,
                    timeConfidence: true,
                    dateConfidence: true,
                    notes: ""
                )
            ],
            errorMessage: nil,
            confidence: 0.95
        ),
        onDismiss: {}
    )
}
