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
        NavigationStack {
            if !showSuccessScreen {
                // Main review screen
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Review Extracted Events")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("Found \(extractionResponse.events.count) events")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(UIColor.systemGray5))

                    // Content
                    ScrollView {
                        VStack(spacing: 16) {
                            // Calendar selector
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Add to Calendar:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Picker("Calendar", selection: $selectedCalendar) {
                                    Text("Default").tag("default")
                                    Text("Work").tag("work")
                                    Text("Personal").tag("personal")
                                }
                                .pickerStyle(.segmented)
                            }
                            .padding(16)
                            .background(Color(UIColor.systemGray5))
                            .cornerRadius(12)

                            // Events list
                            if extractionResponse.events.isEmpty {
                                Text("No events found")
                                    .foregroundColor(.gray)
                                    .padding(20)
                            } else {
                                ForEach($extractionResponse.events, id: \.id) { $event in
                                    SimpleEventCard(event: $event)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .background(Color.white)

                    // Action buttons
                    VStack(spacing: 12) {
                        let selectedCount = extractionResponse.events.filter { $0.isSelected }.count

                        Button(action: { confirmAndCreate() }) {
                            Text("Confirm & Create \(selectedCount) Events")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(selectedCount > 0 ? Color.blue : Color.gray)
                                .cornerRadius(12)
                        }
                        .disabled(selectedCount == 0 || isCreatingEvents)

                        Button(action: { onDismiss() }) {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .disabled(isCreatingEvents)
                    }
                    .padding(16)
                    .background(Color(UIColor.systemGray5))
                }
                .background(Color.white)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                // Success screen
                VStack(spacing: 24) {
                    Spacer()

                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        VStack(spacing: 8) {
                            Text("✅ \(createdCount) Events Created!")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Added to \(selectedCalendar) calendar")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .multilineTextAlignment(.center)
                    }

                    Spacer()

                    Button(action: { onDismiss() }) {
                        Text("Done")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(16)
                }
                .background(Color.white)
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
                                .foregroundColor(.black)
                        }
                        .padding(32)
                        .background(Color.white)
                        .cornerRadius(16)
                    }
                }
            }
        )
        .onAppear {
            print("📱 ReviewExtractedEventsView appeared with \(extractionResponse.events.count) events")
        }
    }

    private func confirmAndCreate() {
        isCreatingEvents = true

        Task {
            var count = 0
            for event in extractionResponse.events where event.isSelected {
                taskManager.addTask(
                    title: event.title,
                    to: weekdayFromDate(event.startTime),
                    description: event.notes.isEmpty ? nil : event.notes,
                    scheduledTime: event.startTime,
                    endTime: event.endTime,
                    targetDate: event.startTime,
                    reminderTime: .oneHour
                )
                count += 1

                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            await MainActor.run {
                createdCount = count
                showSuccessScreen = true
                isCreatingEvents = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    onDismiss()
                }
            }
        }
    }

    private func weekdayFromDate(_ date: Date) -> WeekDay {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
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

// MARK: - Simple Event Card

struct SimpleEventCard: View {
    @Binding var event: ExtractedEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Toggle("", isOn: $event.isSelected)
                    .labelsHidden()

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(event.formattedTime)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()
            }

            if !event.attendees.isEmpty {
                Text(event.attendees.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color(UIColor.systemGray5))
        .cornerRadius(10)
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
                    attendees: ["Sarah"],
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
