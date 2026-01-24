import SwiftUI

struct CalendarWeekView: View {
    @Binding var selectedDate: Date
    let selectedTagId: String?
    let onTapEvent: (TaskItem) -> Void
    let onAddEvent: ((String, String?, Date, Date?, Date?, ReminderTime?, Bool, RecurrenceFrequency?, String?) -> Void)?
    
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @Environment(\.colorScheme) var colorScheme
    
    @State private var isCreatingEvent = false
    
    private let calendar = Calendar.current
    
    // MARK: - Filtered Tasks
    
    private var allTasksForDate: [TaskItem] {
        taskManager.getAllTasks(for: selectedDate)
    }
    
    private func applyFilter(to tasks: [TaskItem]) -> [TaskItem] {
        if let tagId = selectedTagId {
            if tagId == "" {
                // Personal filter - show events with nil tagId (default/personal events)
                return tasks.filter { $0.tagId == nil && !$0.id.hasPrefix("cal_") }
            } else if tagId == "cal_sync" {
                // Personal - Sync filter - show only synced calendar events
                return tasks.filter { $0.id.hasPrefix("cal_") }
            } else {
                // Specific tag filter
                return tasks.filter { $0.tagId == tagId }
            }
        } else {
            // No filter - show all tasks
            return tasks
        }
    }
    
    private var filteredTasksForDate: [TaskItem] {
        applyFilter(to: allTasksForDate)
    }
    
    // MARK: - Colors
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    // MARK: - Date Range for Smooth Scrolling
    
    // Generate a wide range of dates for smooth scrolling (60 days total)
    private var dateRange: [Date] {
        let startDate = calendar.date(byAdding: .day, value: -30, to: selectedDate) ?? selectedDate
        let endDate = calendar.date(byAdding: .day, value: 30, to: selectedDate) ?? selectedDate
        
        var dates: [Date] = []
        var currentDate = startDate
        while currentDate <= endDate {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        return dates
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Week day selector (sliding scale)
            weekDaySelector
                .padding(.bottom, 6)
            
            // All day events section
            AllDayEventsSection(
                tasks: filteredTasksForDate,
                date: selectedDate,
                onTapTask: onTapEvent,
                onToggleCompletion: { task in
                    taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                }
            )
            .id("\(selectedDate.timeIntervalSince1970)-\(selectedTagId ?? "nil")") // Force refresh when date or filter changes
            
            // Timeline view for selected day
            TimelineView(
                date: selectedDate,
                selectedTagId: selectedTagId,
                isCreatingEvent: $isCreatingEvent,
                onTapTask: onTapEvent,
                onToggleCompletion: { task in
                    taskManager.toggleTaskCompletion(task, forDate: selectedDate)
                },
                onAddEvent: onAddEvent,
                onEditEvent: nil,
                onDeleteEvent: nil,
                onDateChange: { newDate in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = newDate
                    }
                }
            )
            .id("\(selectedDate.timeIntervalSince1970)-\(selectedTagId ?? "nil")") // Force refresh when date or filter changes
        }
        .background(backgroundColor)
    }
    
    // MARK: - Week Day Selector (Smooth Scrollable Slider)
    
    private var weekDaySelector: some View {
        GeometryReader { geometry in
            let dayWidth = geometry.size.width / 7 // Each day takes 1/7th of available width
            
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(dateRange, id: \.self) { date in
                            dayCell(date: date)
                                .frame(width: dayWidth) // Fixed width for each day
                                .id(date)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onAppear {
                    // Auto-scroll to selected date on appear
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo(selectedDate, anchor: .center)
                        }
                    }
                }
                .onChange(of: selectedDate) { newDate in
                    // Smoothly scroll to new selected date
                    withAnimation {
                        proxy.scrollTo(newDate, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 58) // Fixed height for the week selector
    }
    
    private func dayCell(date: Date) -> some View {
        let isToday = calendar.isDateInToday(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = date
            }
            HapticManager.shared.selection()
        }) {
            VStack(spacing: 6) {
                // Day letter (S, M, T, W, T, F, S)
                Text(dayLetter(date))
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? primaryTextColor : secondaryTextColor)
                
                // Day number with highlight
                ZStack {
                    if isToday {
                        // Today: circle outline (no fill) - thinner stroke
                        Circle()
                            .stroke(Color(red: 0.2, green: 0.2, blue: 0.2), lineWidth: 1.5)
                            .frame(width: 30, height: 30)
                    } else if isSelected {
                        // Selected (not today): filled circle
                        Circle()
                            .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                            .frame(width: 30, height: 30)
                    }
                    
                    Text(dayNumber(date))
                        .font(FontManager.geist(size: 15, systemWeight: isToday || isSelected ? .semibold : .regular))
                        .foregroundColor(
                            isToday ? primaryTextColor : // Regular text color for today (outline only)
                            isSelected ? Color.white : // White text on dark background when selected
                            secondaryTextColor
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
    private func dayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return String(formatter.string(from: date).prefix(1)).uppercased()
    }
    
    private func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
    
}

#Preview {
    CalendarWeekView(
        selectedDate: .constant(Date()),
        selectedTagId: nil,
        onTapEvent: { _ in },
        onAddEvent: nil
    )
}
