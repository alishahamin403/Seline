import SwiftUI

// MARK: - Event Creation Card for Chat
/// A tappable card that shows event details for confirmation before creating

struct EventCreationCard: View {
    let events: [EventCreationInfo]
    let onConfirm: ([EventCreationInfo]) -> Void
    let onCancel: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedEvents: Set<UUID>
    @State private var isCreating = false

    init(
        events: [EventCreationInfo],
        onConfirm: @escaping ([EventCreationInfo]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.events = events
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // Select all events by default
        self._selectedEvents = State(initialValue: Set(events.map { $0.id }))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            eventListView
            actionButtonsView
        }
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.03))
        .cornerRadius(12)
        .overlay(borderView)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
    
    private var headerView: some View {
        HStack {
            Text(events.count == 1 ? "Create Event" : "Create \(events.count) Events")
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(Color.shadcnForeground(colorScheme))
            
            Spacer()
            
            if events.count > 1 {
                Text("\(selectedEvents.count) selected")
                    .font(FontManager.geist(size: 11, weight: .regular))
                    .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.05))
    }
    
    private var eventListView: some View {
        VStack(spacing: 8) {
            ForEach(events) { event in
                EventRowView(
                    event: event,
                    isSelected: selectedEvents.contains(event.id),
                    showCheckbox: events.count > 1,
                    colorScheme: colorScheme,
                    onToggle: {
                        toggleSelection(event.id)
                    }
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedEvents.contains(id) {
            selectedEvents.remove(id)
        } else {
            selectedEvents.insert(id)
        }
    }
    
    private var actionButtonsView: some View {
        HStack(spacing: 10) {
            cancelButton
            confirmButton
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
    
    private var cancelButton: some View {
        Button(action: {
            HapticManager.shared.selection()
            onCancel()
        }) {
            Text("Cancel")
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
    }

    private var confirmButton: some View {
        Button(action: {
            HapticManager.shared.medium()
            isCreating = true
            let eventsToCreate = events.filter { selectedEvents.contains($0.id) }
            onConfirm(eventsToCreate)
        }) {
            HStack(spacing: 6) {
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(isCreating ? "Creating..." : "Confirm")
                    .font(FontManager.geist(size: 13, weight: .semibold))
            }
            .foregroundColor(confirmButtonForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(confirmButtonBackground)
            .cornerRadius(8)
        }
        .disabled(selectedEvents.isEmpty || isCreating)
    }
    
    private var confirmButtonBackground: Color {
        if selectedEvents.isEmpty {
            return Color.gray
        }
        return colorScheme == .dark ? Color.white : Color.black
    }
    
    private var confirmButtonForeground: Color {
        if selectedEvents.isEmpty {
            return Color.white.opacity(0.7)
        }
        return colorScheme == .dark ? Color.black : Color.white
    }
    
    private var borderView: some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.15), lineWidth: 1)
    }
}

// MARK: - Event Row View

private struct EventRowView: View {
    let event: EventCreationInfo
    let isSelected: Bool
    let showCheckbox: Bool
    let colorScheme: ColorScheme
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                if showCheckbox {
                    checkboxIcon
                }
                eventDetails
                Spacer()
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(rowBackground)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var checkboxIcon: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18))
            .foregroundColor(isSelected 
                ? (colorScheme == .dark ? .white : .black) 
                : Color.shadcnForeground(colorScheme).opacity(0.3))
    }
    
    private var eventDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleText
            dateTimeRow
            badgesRow
        }
    }
    
    private var titleText: some View {
        Text(event.title)
            .font(FontManager.geist(size: 14, weight: .semibold))
            .foregroundColor(Color.shadcnForeground(colorScheme))
            .lineLimit(2)
    }
    
    private var dateTimeRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                Text(event.formattedDate)
                    .font(FontManager.geist(size: 11, weight: .regular))
            }
            
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(event.formattedTime)
                    .font(FontManager.geist(size: 11, weight: .regular))
            }
        }
        .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.6))
    }
    
    private var badgesRow: some View {
        HStack(spacing: 8) {
            categoryBadge
            if event.reminderMinutes != nil {
                reminderBadge
            }
        }
        .foregroundColor(Color.shadcnForeground(colorScheme).opacity(0.5))
    }
    
    private var categoryBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "tag")
                .font(.system(size: 9))
            Text(event.category)
                .font(FontManager.geist(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(4)
    }
    
    private var reminderBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "bell")
                .font(.system(size: 9))
            Text(event.reminderText)
                .font(FontManager.geist(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(4)
    }
    
    private var rowBackground: Color {
        if isSelected && showCheckbox {
            return colorScheme == .dark ? Color.white.opacity(0.08) : Color.gray.opacity(0.08)
        }
        return Color.clear
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        EventCreationCard(
            events: [
                EventCreationInfo(
                    title: "Team standup meeting",
                    date: Date().addingTimeInterval(86400),
                    hasTime: true,
                    reminderMinutes: 15,
                    category: "Work"
                )
            ],
            onConfirm: { _ in },
            onCancel: {}
        )
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
