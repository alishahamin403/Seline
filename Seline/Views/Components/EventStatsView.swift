import SwiftUI

struct EventStatsView: View {
    @StateObject private var taskManager = TaskManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedMonth: Date = Date()
    @State private var viewMode: ViewMode = .month

    enum ViewMode: String {
        case month = "Month"
        case year = "Year"
    }

    // Get the earliest event date (first event created)
    private var earliestEventDate: Date {
        let allTasks = taskManager.tasks.values.flatMap { $0 }
        guard !allTasks.isEmpty else { return Date() }

        return allTasks.map { $0.createdAt }.min() ?? Date()
    }

    // Generate months for the picker based on view mode
    private var availableMonths: [Date] {
        let calendar = Calendar.current
        let today = Date()

        if viewMode == .year {
            // When in year mode, show all 12 months of the selected year
            let selectedYear = calendar.component(.year, from: selectedMonth)
            let earliestYear = calendar.component(.year, from: earliestEventDate)
            let earliestMonth = calendar.component(.month, from: earliestEventDate)

            return (1...12).compactMap { month in
                var components = DateComponents()
                components.year = selectedYear
                components.month = month
                components.day = 1
                guard let date = calendar.date(from: components) else { return nil }

                // Only show months that are >= earliest event date and <= today
                if selectedYear == earliestYear && month < earliestMonth {
                    return nil
                }
                if date > today {
                    return nil
                }
                return date
            }
        } else {
            // When in month mode, show months from earliest event to current month
            var months: [Date] = []
            var currentDate = calendar.date(from: calendar.dateComponents([.year, .month], from: earliestEventDate))!
            let endDate = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!

            while currentDate <= endDate {
                months.append(currentDate)
                currentDate = calendar.date(byAdding: .month, value: 1, to: currentDate)!
            }

            return months.reversed()
        }
    }

    // Generate years from first event to current year
    private var availableYears: [Date] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let earliestYear = calendar.component(.year, from: earliestEventDate)

        return (earliestYear...currentYear).compactMap { year in
            var components = DateComponents()
            components.year = year
            components.month = 1
            components.day = 1
            return calendar.date(from: components)
        }
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    private var yearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }

    private var shortMonthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }

    private var viewModeBinding: Binding<String> {
        Binding(
            get: { viewMode.rawValue },
            set: { newValue in
                if let mode = ViewMode(rawValue: newValue) {
                    viewMode = mode
                    // When switching to Year mode, set selectedMonth to first month of current year
                    if mode == .year {
                        let calendar = Calendar.current
                        let currentYear = calendar.component(.year, from: Date())
                        var components = DateComponents()
                        components.year = currentYear
                        components.month = 1
                        components.day = 1
                        if let firstMonthOfYear = calendar.date(from: components) {
                            selectedMonth = firstMonthOfYear
                        }
                    }
                }
            }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // Monthly Summary with AI Insights (top)
                    MonthlySummaryCard(selectedMonth: selectedMonth)

                    // AI Summary for Missed Recurring Events
                    MissedRecurringEventsSummary()

                    // Date Picker (Year and Month Dropdowns)
                    datePicker

                    // Completion Stats
                    completionStatsSection

                    // Recurring Events Breakdown
                    recurringEventsSection

                    // Bottom spacing
                    Spacer()
                        .frame(height: 100)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            .background(
                colorScheme == .dark ?
                    Color.black : Color.white
            )
        }
    }

    // MARK: - Date Picker

    private var datePicker: some View {
        HStack(spacing: 12) {
            // Year Dropdown
            Menu {
                ForEach(availableYears, id: \.self) { year in
                    Button(action: {
                        HapticManager.shared.selection()
                        selectedMonth = year
                    }) {
                        Text(yearFormatter.string(from: year))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(yearFormatter.string(from: selectedMonth))
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                )
            }

            // Month Dropdown
            Menu {
                ForEach(availableMonths, id: \.self) { month in
                    Button(action: {
                        HapticManager.shared.selection()
                        selectedMonth = month
                    }) {
                        Text(shortMonthFormatter.string(from: month))
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(shortMonthFormatter.string(from: selectedMonth))
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                )
            }

            Spacer()
        }
    }

    // MARK: - Completion Stats Section

    private var completionStatsSection: some View {
        let breakdown = taskManager.getMonthlyEventBreakdown(selectedMonth)

        return ShadcnCard {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Events Completed")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text(monthFormatter.string(from: selectedMonth))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }

                    Spacer()
                }

                // Main stats
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(breakdown.completed)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.green)

                        Text("Completed")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }

                    Divider()
                        .frame(height: 50)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(breakdown.total)")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("Total")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                }

                // Completion percentage
                if breakdown.total > 0 {
                    let percentage = Int((Double(breakdown.completed) / Double(breakdown.total)) * 100)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(percentage)% Complete")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))

                            Spacer()
                        }

                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.green)
                                    .frame(width: geometry.size.width * (Double(percentage) / 100.0), height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Recurring Events Section

    private var recurringEventsSection: some View {
        let recurringStats = taskManager.getRecurringEventBreakdownForMonth(selectedMonth)

        return VStack(alignment: .leading, spacing: 12) {
            if !recurringStats.isEmpty {
                // Section header
                HStack {
                    Text("Recurring Events Breakdown")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Spacer()

                    ShadcnBadge("\(recurringStats.count)", variant: .count)
                }
                .padding(.horizontal, 4)

                // Breakdown
                RecurringEventBreakdown(recurringStats: recurringStats)
            }
        }
    }
}

#Preview {
    EventStatsView()
}
