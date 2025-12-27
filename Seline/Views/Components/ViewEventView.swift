import SwiftUI
import UIKit

struct ViewEventView: View {
    let task: TaskItem
    let onEdit: () -> Void
    let onDelete: ((TaskItem) -> Void)?
    let onDeleteRecurringSeries: ((TaskItem) -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var tagManager = TagManager.shared
    @State private var showingDeleteOptions = false
    @State private var showingShareSheet = false
    @State private var isEmailExpanded = false

    private var formattedDate: String {
        guard let targetDate = task.targetDate else {
            return "No date set"
        }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        
        // Check if this is a multi-day event
        if let endTime = task.endTime {
            let startDate = calendar.startOfDay(for: targetDate)
            let endDate = calendar.startOfDay(for: endTime)
            
            if endDate > startDate {
                // Multi-day event: show date range
                let startDateString = formatter.string(from: targetDate)
                let endDateString = formatter.string(from: endTime)
                return "\(startDateString) - \(endDateString)"
            } else {
                // Single-day event
                return formatter.string(from: targetDate)
            }
        } else {
            // No end time: single-day event
            return formatter.string(from: targetDate)
        }
    }

    private var formattedTime: String {
        guard let scheduledTime = task.scheduledTime else {
            return "No time set"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: scheduledTime)
    }

    // Get event type color
    private var eventTypeColor: Color {
        let filterType = TimelineEventColorManager.filterType(from: task)
        if case .tag(let tagId) = filterType {
            if let tag = tagManager.getTag(by: tagId) {
                return TimelineEventColorManager.getTagColor(tagId: tagId, colorIndex: tag.colorIndex)
            }
        }
        return TimelineEventColorManager.timelineEventAccentColor(
            filterType: filterType,
            colorScheme: colorScheme,
            tagColorIndex: tagManager.getTag(by: task.tagId ?? "")?.colorIndex
        )
    }
    
    // Get event type name
    private var eventTypeName: String {
        if task.id.hasPrefix("cal_") {
            return "Synced"
        } else if let tagId = task.tagId, let tag = tagManager.getTag(by: tagId) {
            return tag.name
        }
        return "Personal"
    }
    
    // Get event type icon
    private var eventTypeIcon: String {
        if task.id.hasPrefix("cal_") {
            return "calendar.badge.clock"
        } else if task.tagId != nil {
            return "tag.fill"
        }
        return "calendar"
    }
    
    
    // Shareable text
    private var shareableEventText: String {
        var text = "Event: \(task.title)\n"
        
        let date = formattedDate
        text += "Date: \(date)\n"
        
        if task.scheduledTime != nil {
            text += "Time: \(task.formattedTimeRange)\n"
        }
        
        if let location = task.location, !location.isEmpty {
             text += "Location: \(location)\n"
        }
        
        if let description = task.description, !description.isEmpty {
            text += "\n\(description)"
        }
        
        return text
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero Header Card
                heroHeaderCard
                
                // Date & Time Card
                dateTimeCard
                
                // Recurrence & Reminder Card (if applicable)
                if task.isRecurring || task.reminderTime != .none {
                    recurrenceReminderCard
                }
                
                if let description = task.description, !description.isEmpty {
                    descriptionCard(description)
                }
                
                // Location Card (if exists)
                if let location = task.location, !location.isEmpty {
                    locationCard(location)
                }
                
                // Attached Email Card (if exists)
                if task.hasEmailAttachment {
                    emailAttachmentCard
                }
                
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 20) {
                    // Share button
                    Button(action: {
                        showingShareSheet = true
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }

                    // Edit button
                    Button(action: {
                        onEdit()
                    }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    
                    // Delete button
                    Button(action: {
                        if task.isRecurring {
                            showingDeleteOptions = true
                        } else {
                            onDelete?(task)
                            dismiss()
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            EventShareSheet(activityItems: [shareableEventText])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete Event", isPresented: $showingDeleteOptions, titleVisibility: .visible) {
            Button("Delete This Event Only", role: .destructive) {
                onDelete?(task)
                dismiss()
            }

            Button("Delete All Recurring Events", role: .destructive) {
                onDeleteRecurringSeries?(task)
                dismiss()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is a recurring event. What would you like to delete?")
        }
    }
    
    // MARK: - Card Views
    
    private var heroHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Event Type Badge
            HStack(spacing: 6) {
                Image(systemName: eventTypeIcon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(eventTypeColor)
                
                Text(eventTypeName)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(eventTypeColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(eventTypeColor.opacity(colorScheme == .dark ? 0.2 : 0.15))
            )
            
            // Title
            Text(task.title)
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private var dateTimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date & Time")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                .textCase(.uppercase)
                .tracking(0.5)
            
            VStack(spacing: 10) {
                // Date
                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                        .frame(width: 20)
                    
                    Text(formattedDate)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Spacer()
                }
                
                // Time
                if task.scheduledTime != nil || task.endTime != nil {
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            .frame(width: 20)
                        
                        Text(task.formattedTimeRange)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private var recurrenceReminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                .textCase(.uppercase)
                .tracking(0.5)
            
            VStack(spacing: 10) {
                // Recurrence
                if task.isRecurring, let frequency = task.recurrenceFrequency {
                    HStack(spacing: 12) {
                        Image(systemName: "repeat")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            .frame(width: 20)
                        
                        Text(frequency.rawValue.capitalized)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Spacer()
                    }
                }
                
                // Reminder
                if let reminderTime = task.reminderTime, reminderTime != .none {
                    HStack(spacing: 12) {
                        Image(systemName: reminderTime.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            .frame(width: 20)
                        
                        Text(reminderTime.displayName)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private func descriptionCard(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Description")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text(description)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private func locationCard(_ location: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                .textCase(.uppercase)
                .tracking(0.5)
            
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    .frame(width: 20)

                Text(location)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private var emailAttachmentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attached Email")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                .textCase(.uppercase)
                .tracking(0.5)
            
            VStack(spacing: 0) {
                // Email header with subject, sender, snippet, timestamp
                ReusableEmailHeaderView(
                    email: nil,
                    emailSubject: task.emailSubject,
                    emailSenderName: task.emailSenderName,
                    emailSenderEmail: task.emailSenderEmail,
                    emailTimestamp: task.emailTimestamp,
                    emailSnippet: task.emailSnippet,
                    showSnippet: !isEmailExpanded,
                    showTimestamp: true,
                    style: .embedded
                )
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ?
                            Color.white.opacity(0.05) :
                            Color.black.opacity(0.03))
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEmailExpanded.toggle()
                    }
                }

                // Email body when expanded
                if isEmailExpanded {
                    ReusableEmailBodyView(
                        htmlContent: task.emailBody,
                        plainTextContent: task.emailSnippet,
                        isExpanded: true,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEmailExpanded.toggle()
                            }
                        },
                        isLoading: false
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    

}

#Preview {
    NavigationView {
        ViewEventView(
            task: TaskItem(
                title: "Team Meeting",
                weekday: .monday,
                description: "Discuss project updates and next steps",
                scheduledTime: Date(),
                targetDate: Date(),
                reminderTime: .oneHour,
                isRecurring: true,
                recurrenceFrequency: .weekly
            ),
            onEdit: { print("Edit tapped") },
            onDelete: { _ in print("Delete tapped") },
            onDeleteRecurringSeries: { _ in print("Delete series tapped") }
        )
    }
}

struct EventShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
