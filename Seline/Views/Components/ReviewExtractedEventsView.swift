import SwiftUI

struct ReviewExtractedEventsView: View {
    @State private var extractionResponse: CalendarPhotoExtractionResponse
    var onDismiss: () -> Void

    init(extractionResponse: CalendarPhotoExtractionResponse, onDismiss: @escaping () -> Void) {
        _extractionResponse = State(initialValue: extractionResponse)
        self.onDismiss = onDismiss
    }

    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @State private var selectedTagId: String? = nil // nil means Personal (default)
    @State private var showingTagOptions = false
    @State private var showingCreateTag = false
    @State private var newTagName = ""
    @State private var isCreatingEvents = false
    @State private var showSuccessScreen = false
    @State private var createdCount = 0

    var body: some View {
        ZStack {
            // Main background
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            if !showSuccessScreen {
                // Main review screen
                VStack(spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Review Extracted Events")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("Found \(extractionResponse.events.count) events")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Button(action: { onDismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(UIColor.systemGray6))

                    // Content ScrollView
                    ScrollView(showsIndicators: true) {
                        VStack(spacing: 16) {
                            // Tag selector section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Select Tag:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)

                                HStack(spacing: 12) {
                                    // Tag display button
                                    Button(action: {
                                        showingTagOptions.toggle()
                                    }) {
                                        HStack {
                                            if let tagId = selectedTagId, let tag = tagManager.getTag(by: tagId) {
                                                Circle()
                                                    .fill(tag.color)
                                                    .frame(width: 10, height: 10)
                                                Text(tag.name)
                                            } else {
                                                Circle()
                                                    .fill(Color.blue)
                                                    .frame(width: 10, height: 10)
                                                Text("Personal (Default)")
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 12))
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Color(UIColor.systemBackground))
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                        )
                                    }
                                    .foregroundColor(.primary)

                                    // Create new tag button
                                    Button(action: {
                                        showingCreateTag.toggle()
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.blue)
                                    }
                                }

                                // Create tag sheet
                                .sheet(isPresented: $showingCreateTag) {
                                    CreateTagSheet(
                                        tagName: $newTagName,
                                        onCreate: { tagName in
                                            if let newTag = tagManager.createTag(name: tagName) {
                                                selectedTagId = newTag.id
                                                newTagName = ""
                                                showingCreateTag = false
                                            }
                                        }
                                    )
                                    .presentationDetents([.height(250)])
                                }

                                // Tag selection sheet
                                .sheet(isPresented: $showingTagOptions) {
                                    TagSelectionSheet(
                                        selectedTagId: $selectedTagId,
                                        colorScheme: .light
                                    )
                                    .presentationDetents([.height(300)])
                                }
                            }
                            .padding(16)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(12)

                            // Events header
                            Text("Events to Create")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(.primary)

                            // Events list
                            if extractionResponse.events.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray)
                                    Text("No events found")
                                        .foregroundColor(.gray)
                                        .font(.subheadline)
                                }
                                .padding(40)
                                .frame(maxWidth: .infinity)
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(12)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach($extractionResponse.events, id: \.id) { $event in
                                        SimpleEventCard(event: $event)
                                    }
                                }
                            }

                            // Summary section
                            let selectedCount = extractionResponse.events.filter { $0.isSelected }.count
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Selected events:")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("\(selectedCount) of \(extractionResponse.events.count)")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(12)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(8)
                        }
                        .padding(16)
                    }
                    .background(Color(UIColor.systemBackground))

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
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(12)
                        }
                        .disabled(isCreatingEvents)
                    }
                    .padding(16)
                }
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
                                .foregroundColor(.primary)

                            Text(selectedTagId != nil && tagManager.getTag(by: selectedTagId) != nil ? "Added to \(tagManager.getTag(by: selectedTagId)?.name ?? "")" : "Added to Personal")
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
            }

            // Loading overlay
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
        .onAppear {
            print("📱 ReviewExtractedEventsView appeared with \(extractionResponse.events.count) events")
            for (index, event) in extractionResponse.events.enumerated() {
                print("  Event \(index): \(event.title) - Selected: \(event.isSelected)")
            }
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
                    reminderTime: .oneHour,
                    tagId: selectedTagId
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

// MARK: - Create Tag Sheet

struct CreateTagSheet: View {
    @Binding var tagName: String
    var onCreate: (String) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create New Tag")
                        .font(.headline)

                    TextField("Tag name (e.g., 'School', 'Gym')", text: $tagName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.top, 4)
                }
                .padding(16)

                Spacer()

                VStack(spacing: 12) {
                    Button(action: {
                        onCreate(tagName)
                    }) {
                        Text("Create Tag")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                            .cornerRadius(12)
                    }
                    .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(12)
                    }
                }
                .padding(16)
            }
            .navigationBarHidden(true)
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

                    // Show time range if end time exists, otherwise just start time
                    if let endTime = event.endTime {
                        let formatter = DateFormatter()
                        formatter.timeStyle = .short
                        let startTimeStr = formatter.string(from: event.startTime)
                        let endTimeStr = formatter.string(from: endTime)
                        Text("\(startTimeStr) - \(endTimeStr)")
                            .font(.caption)
                            .foregroundColor(.gray)

                        if let duration = event.durationText {
                            Text("(\(duration))")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    } else {
                        Text(event.formattedTime)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("(no end time)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
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
