
//
//  CompletedEventsCalendarView.swift
//  Seline
//
//  Created by Gemini on 2025-09-05.
//

import SwiftUI

struct CompletedEventsCalendarView: View {
    @State private var date = Date()
    @StateObject private var calendarService = CalendarService.shared
    @State private var pastEvents: [CalendarEvent] = []
    @State private var selectedDate: Date?

    var body: some View {
        VStack(spacing: 0) {
            headerView
            calendarView
            eventsForSelectedDateView
        }
        .onAppear {
            fetchPastEvents()
        }
        .onChange(of: date) { _ in
            fetchPastEvents()
        }
    }

    private var headerView: some View {
        HStack {
            Button(action: {
                self.date = Calendar.current.date(byAdding: .month, value: -1, to: self.date) ?? self.date
            }) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            
            Spacer()
            
            Text(date, formatter: Self.monthYearFormatter)
                .font(.title2.bold())
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Spacer()
            
            Button(action: {
                self.date = Calendar.current.date(byAdding: .month, value: 1, to: self.date) ?? self.date
            }) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
        }
        .padding(.horizontal)
        .padding(.top)
    }

    private var calendarView: some View {
        let month = Calendar.current.dateComponents([.year, .month], from: date)
        let days = makeDays(for: month)

        return VStack {
            HStack {
                ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.bottom, 5)

            LazyVGrid(columns: Array(repeating: GridItem(), count: 7)) {
                ForEach(days, id: \.date) { day in
                    if day.isFromCurrentMonth {
                        dayView(day)
                    } else {
                        Rectangle().fill(Color.clear)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func dayView(_ day: Day) -> some View {
        let eventsOnDay = pastEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day.date) }
        let isSelected = selectedDate != nil && Calendar.current.isDate(selectedDate!, inSameDayAs: day.date)
        
        return VStack {
            Text(day.number)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
                .foregroundColor(isSelected ? .white : (day.isToday ? .white : DesignSystem.Colors.textPrimary))
                .background(
                    Circle()
                        .fill(isSelected ? DesignSystem.Colors.accent : (day.isToday ? DesignSystem.Colors.accent.opacity(0.5) : Color.clear))
                        .frame(width: 28, height: 28)
                )
            
            if !eventsOnDay.isEmpty {
                Circle()
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: 5, height: 5)
                    .padding(.top, 2)
            } else {
                Spacer().frame(height: 7)
            }
        }
        .padding(.vertical, 5)
        .frame(height: 50)
        .onTapGesture {
            selectedDate = day.date
        }
    }

    @ViewBuilder
    private var eventsForSelectedDateView: some View {
        if let selectedDate = selectedDate {
            let events = pastEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }
            
            VStack(alignment: .leading) {
                Text("Events on \(selectedDate, formatter: Self.dateFormatter)")
                    .font(.headline)
                    .padding()
                
                if events.isEmpty {
                    Text("No events for this day.")
                        .padding()
                    Spacer()
                } else {
                    List(events) { event in
                        EventCard(event: event)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func fetchPastEvents() {
        Task {
            do {
                let events = try await calendarService.fetchPastEvents(for: date)
                self.pastEvents = events
            } catch {
                // Handle error
                print("Error fetching past events: \(error)")
            }
        }
    }

    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    private static let weekdaySymbols = Calendar.current.shortWeekdaySymbols
}

private struct Day {
    let date: Date
    let number: String
    let isToday: Bool
    let isFromCurrentMonth: Bool
}

private func makeDays(for month: DateComponents) -> [Day] {
    guard let monthStartDate = Calendar.current.date(from: month),
          let monthEndDate = Calendar.current.date(byAdding: .month, value: 1, to: monthStartDate),
          let monthRange = Calendar.current.range(of: .day, in: .month, for: monthStartDate) else {
        return []
    }

    let firstDayOfMonth = monthStartDate
    let firstWeekday = Calendar.current.component(.weekday, from: firstDayOfMonth)
    
    var days: [Day] = []
    
    // Add padding days from previous month
    let emptyDays = (firstWeekday - Calendar.current.firstWeekday + 7) % 7
    for _ in 0..<emptyDays {
        days.append(Day(date: Date(), number: "", isToday: false, isFromCurrentMonth: false))
    }

    // Add days of the current month
    for day in monthRange {
        if let date = Calendar.current.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
            let isToday = Calendar.current.isDateInToday(date)
            days.append(Day(date: date, number: "\(day)", isToday: isToday, isFromCurrentMonth: true))
        }
    }
    
    return days
}

struct CompletedEventsCalendarView_Previews: PreviewProvider {
    static var previews: some View {
        CompletedEventsCalendarView()
    }
}
