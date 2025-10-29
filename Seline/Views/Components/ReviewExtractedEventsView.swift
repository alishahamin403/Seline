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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Review Events")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text("\(extractionResponse.events.count) events found")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Button(action: { onDismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.black)
                                    .opacity(0.5)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(UIColor.systemBackground))

                    // Content ScrollView
                    ScrollView(showsIndicators: true) {
                        VStack(spacing: 16) {
                            // Tag selector section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Save to:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .fontWeight(.semibold)

                                HStack(spacing: 10) {
                                    // Tag display button
                                    Button(action: {
                                        showingTagOptions.toggle()
                                    }) {
                                        HStack(spacing: 6) {
                                            if let tagId = selectedTagId, let tag = tagManager.getTag(by: tagId) {
                                                Circle()
                                                    .fill(tag.color)
                                                    .frame(width: 8, height: 8)
                                                Text(tag.name)
                                            } else {
                                                // Use the default color from palette (index 0 - muted blue)
                                                Circle()
                                                    .fill(TagColorPalette.colorForIndex(0))
                                                    .frame(width: 8, height: 8)
                                                Text("Personal")
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 10))
                                        }
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(Color(UIColor.systemGray6))
                                        .cornerRadius(6)
                                    }
                                    .foregroundColor(.primary)

                                    // Create new tag button
                                    Button(action: {
                                        showingCreateTag.toggle()
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 20))
                                            .foregroundColor(.black)
                                            .opacity(0.4)
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
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            // Events header
                            Text("Events to Create")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundColor(.primary)

                            // Events list
                            if extractionResponse.events.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                        .font(.system(size: 32))
                                        .foregroundColor(.gray)
                                        .opacity(0.5)
                                    Text("No events found")
                                        .foregroundColor(.gray)
                                        .font(.caption)
                                }
                                .padding(40)
                                .frame(maxWidth: .infinity)
                            } else {
                                VStack(spacing: 12) {
                                    ForEach($extractionResponse.events, id: \.id) { $event in
                                        SimpleEventCard(event: $event)
                                    }
                                }
                            }

                            // Summary section
                            let selectedCount = extractionResponse.events.filter { $0.isSelected }.count
                            HStack {
                                Text("Selected:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(selectedCount) of \(extractionResponse.events.count)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.black)
                            }
                            .padding(.vertical, 4)
                        }
                        .padding(16)
                    }
                    .background(Color(UIColor.systemBackground))

                    // Action buttons
                    VStack(spacing: 10) {
                        let selectedCount = extractionResponse.events.filter { $0.isSelected }.count

                        Button(action: { confirmAndCreate() }) {
                            Text("Create \(selectedCount) Event\(selectedCount == 1 ? "" : "s")")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(selectedCount > 0 ? Color.black : Color.gray)
                                .cornerRadius(8)
                        }
                        .disabled(selectedCount == 0 || isCreatingEvents)

                        Button(action: { onDismiss() }) {
                            Text("Cancel")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                                .opacity(0.6)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .disabled(isCreatingEvents)
                    }
                    .padding(16)
                }
            } else {
                // Success screen
                VStack(spacing: 24) {
                    Spacer()

                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.black)

                        VStack(spacing: 6) {
                            Text("\(createdCount) Event\(createdCount == 1 ? "" : "s") Created")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text(selectedTagId != nil && tagManager.getTag(by: selectedTagId) != nil ? "Saved to \(tagManager.getTag(by: selectedTagId)?.name ?? "")" : "Saved to Personal")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .multilineTextAlignment(.center)
                    }

                    Spacer()

                    Button(action: { onDismiss() }) {
                        Text("Done")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.black)
                            .cornerRadius(8)
                    }
                    .padding(16)
                }
            }

            // Loading overlay
            if isCreatingEvents {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("Creating events...")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)
                    }
                    .padding(28)
                    .background(Color.white)
                    .cornerRadius(12)
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
    @State private var showStartTimePicker = false
    @State private var showEndTimePicker = false

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatTimeRange() -> String {
        let startStr = formatTime(event.startTime)
        if let endTime = event.endTime {
            let endStr = formatTime(endTime)
            return "\(startStr) - \(endStr)"
        }
        return startStr
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main event row
            HStack(spacing: 12) {
                if event.alreadyExists {
                    // Already exists - show info icon instead of toggle
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.gray)
                        .opacity(0.5)
                } else {
                    Toggle("", isOn: $event.isSelected)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(event.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .foregroundColor(event.alreadyExists ? .gray : .primary)

                        if event.alreadyExists {
                            Text("(Already exists)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }

                    Text(formatTimeRange())
                        .font(.caption)
                        .foregroundColor(.gray)
                        .opacity(event.alreadyExists ? 0.5 : 1)
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .opacity(event.alreadyExists ? 0.6 : 1)

            // Divider
            Divider()
                .padding(.horizontal, 14)

            // Time editing section - disabled if event already exists
            VStack(alignment: .leading, spacing: 0) {
                // Start time
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Start")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .opacity(event.alreadyExists ? 0.5 : 1)

                            if !showStartTimePicker {
                                Text(formatTime(event.startTime))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .opacity(event.alreadyExists ? 0.5 : 1)
                            }
                        }

                        Spacer()

                        if !event.alreadyExists {
                            if !showStartTimePicker {
                                Button(action: { showStartTimePicker = true }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .foregroundColor(.black)
                                        .opacity(0.5)
                                }
                            } else {
                                Button(action: { showStartTimePicker = false }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.black)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 14)

                    if showStartTimePicker && !event.alreadyExists {
                        DatePicker("", selection: $event.startTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(height: 100)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if event.endTime != nil {
                    Divider()
                        .padding(.horizontal, 14)

                    // End time
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("End")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .opacity(event.alreadyExists ? 0.5 : 1)

                                if !showEndTimePicker {
                                    if let endTime = event.endTime {
                                        Text(formatTime(endTime))
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .opacity(event.alreadyExists ? 0.5 : 1)
                                    } else {
                                        Text("No end time")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                            .opacity(event.alreadyExists ? 0.5 : 1)
                                    }
                                }
                            }

                            Spacer()

                            if !event.alreadyExists {
                                if !showEndTimePicker {
                                    Button(action: { showEndTimePicker = true }) {
                                        Image(systemName: "pencil.circle.fill")
                                            .foregroundColor(.black)
                                            .opacity(0.5)
                                    }
                                } else {
                                    Button(action: { showEndTimePicker = false }) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.black)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)

                        if showEndTimePicker && !event.alreadyExists {
                            DatePicker("", selection: .init(get: { event.endTime ?? Date() }, set: { event.endTime = $0 }), displayedComponents: .hourAndMinute)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .frame(height: 100)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Attendees section
            if !event.attendees.isEmpty {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Attendees")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(event.attendees.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
            }
        }
        .background(Color.white)
        .cornerRadius(0)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.1), lineWidth: 1)
        )
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
