import SwiftUI

struct LocationTimelineView: View {
    let colorScheme: ColorScheme

    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var locationsManager = LocationsManager.shared

    @State private var selectedDate: Date = Date()
    @State private var currentMonth: Date = Date()
    @State private var visitsForSelectedDay: [LocationVisitRecord] = []
    @State private var visitsForMonth: [Date: Int] = [:] // Date -> visit count
    @State private var isLoading = false
    @State private var showingPlaceDetail = false
    @State private var selectedPlace: SavedPlace? = nil

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Calendar section
            calendarSection

            // Timeline section for selected day
            if isLoading {
                ProgressView()
                    .padding(.top, 40)
            } else if visitsForSelectedDay.isEmpty {
                emptyDayView
            } else {
                timelineSection
            }

            Spacer()
        }
        .onAppear {
            loadVisitsForMonth()
            loadVisitsForSelectedDay()
        }
        .sheet(isPresented: $showingPlaceDetail) {
            if let place = selectedPlace {
                PlaceDetailSheet(place: place, onDismiss: { showingPlaceDetail = false })
                    .presentationBg()
            }
        }
    }

    // MARK: - Calendar Section

    @ViewBuilder
    private var calendarSection: some View {
        VStack(spacing: 6) {
            // Month navigation
            HStack(spacing: 8) {
                // Previous month button
                Button(action: {
                    withAnimation {
                        currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                        loadVisitsForMonth()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Month and year
                Text(dateFormatter.string(from: currentMonth))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .frame(maxWidth: .infinity)

                // Today button
                Button(action: {
                    withAnimation {
                        let today = Date()
                        currentMonth = today
                        selectedDate = today
                        loadVisitsForMonth()
                        loadVisitsForSelectedDay()
                    }
                }) {
                    Text("Today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())

                // Next month button
                Button(action: {
                    withAnimation {
                        currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                        loadVisitsForMonth()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            // Day headers
            HStack(spacing: 0) {
                ForEach(["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)

            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(daysInMonth(), id: \.self) { date in
                    if let date = date {
                        calendarDayCell(for: date)
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                .shadow(
                    color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.03),
                    radius: 12,
                    x: 0,
                    y: 2
                )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func calendarDayCell(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let visitCount = visitsForMonth[normalizeDate(date)] ?? 0
        let hasVisits = visitCount > 0
        let isInCurrentMonth = calendar.isDate(date, equalTo: currentMonth, toGranularity: .month)

        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedDate = date
                loadVisitsForSelectedDay()
            }
        }) {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13, weight: isToday ? .semibold : .regular))
                    .foregroundColor(
                        isSelected ? (colorScheme == .dark ? Color.black : Color.white) :
                        isToday ? (colorScheme == .dark ? Color.white : Color.black) :
                        !isInCurrentMonth ? (colorScheme == .dark ? Color.white : Color.black).opacity(0.4) :
                        (colorScheme == .dark ? Color.white : Color.black)
                    )

                // Visit indicator - show up to 3 dots
                if hasVisits {
                    HStack(spacing: 2) {
                        ForEach(0..<min(visitCount, 3), id: \.self) { _ in
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                .frame(width: 4, height: 4)
                        }
                    }
                } else {
                    // Empty space to maintain consistent height
                    HStack(spacing: 2) {}
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                isSelected ? (colorScheme == .dark ? Color.white : Color.black) :
                isToday ? (colorScheme == .dark ? Color.white : Color.black).opacity(0.1) :
                Color.clear
            )
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Timeline Section

    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Day summary
            HStack {
                Text(selectedDayString())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                Text(visitSummary())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Vertical timeline
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(visitsForSelectedDay.sorted(by: { $0.entryTime < $1.entryTime })) { visit in
                        visitCard(for: visit)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.white)
                .shadow(
                    color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.03),
                    radius: 12,
                    x: 0,
                    y: 2
                )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func visitCard(for visit: LocationVisitRecord) -> some View {
        if let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
            Button(action: {
                selectedPlace = place
                showingPlaceDetail = true
            }) {
                HStack(spacing: 0) {
                    // Timeline indicator
                    VStack(spacing: 0) {
                        Circle()
                            .fill(categoryColor(for: place.category))
                            .frame(width: 10, height: 10)

                        if visit.id != visitsForSelectedDay.sorted(by: { $0.entryTime < $1.entryTime }).last?.id {
                            Rectangle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                                .frame(width: 2)
                                .frame(minHeight: 40)
                        }
                    }
                    .frame(width: 30)

                    // Visit card
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            // Location icon/image
                            PlaceImageView(place: place, size: 40, cornerRadius: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.displayName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)

                                Text(place.category)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(categoryColor(for: place.category))
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                        }

                        // Time and duration
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 10))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                Text(timeRangeString(from: visit))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                            }

                            if let duration = visit.durationMinutes {
                                Text(durationString(minutes: duration))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                            }
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05),
                                lineWidth: 1
                            )
                    )
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    @ViewBuilder
    private var emptyDayView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

            Text("No visits on this day")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

            Text("Visit saved locations to see them here")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helper Functions

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            return []
        }

        let daysCount = calendar.component(.weekday, from: monthInterval.start) - 1
        var days: [Date?] = Array(repeating: nil, count: daysCount)

        var date = monthInterval.start
        while date < monthInterval.end {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        return days
    }

    private func normalizeDate(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? date
    }

    private func selectedDayString() -> String {
        let formatter = DateFormatter()
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: selectedDate)
        }
    }

    private func visitSummary() -> String {
        let count = visitsForSelectedDay.count
        let totalMinutes = visitsForSelectedDay.compactMap { $0.durationMinutes }.reduce(0, +)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return "\(count) visit\(count == 1 ? "" : "s") • \(hours)h \(minutes)m"
        } else {
            return "\(count) visit\(count == 1 ? "" : "s") • \(minutes)m"
        }
    }

    private func timeRangeString(from visit: LocationVisitRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        let entryString = formatter.string(from: visit.entryTime)

        if let exitTime = visit.exitTime {
            let exitString = formatter.string(from: exitTime)
            return "\(entryString) - \(exitString)"
        } else {
            return "\(entryString) - ongoing"
        }
    }

    private func durationString(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(mins)m"
        }
    }

    private func categoryColor(for category: String) -> Color {
        // Simple color mapping based on category
        switch category.lowercased() {
        case let c where c.contains("restaurant") || c.contains("food"):
            return Color.orange
        case let c where c.contains("coffee") || c.contains("cafe"):
            return Color.brown
        case let c where c.contains("gym") || c.contains("fitness"):
            return Color.red
        case let c where c.contains("shop") || c.contains("store"):
            return Color.purple
        case let c where c.contains("park") || c.contains("nature"):
            return Color.green
        case let c where c.contains("entertainment") || c.contains("movie"):
            return Color.pink
        default:
            return Color.blue
        }
    }

    // MARK: - Data Loading

    private func loadVisitsForMonth() {
        Task {
            guard let userId = supabaseManager.getCurrentUser()?.id else { return }

            // Get first and last day of month
            guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else { return }

            do {
                let client = await supabaseManager.getPostgrestClient()
                let response = try await client
                    .from("location_visits")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .gte("entry_time", value: monthInterval.start.ISO8601Format())
                    .lte("entry_time", value: monthInterval.end.ISO8601Format())
                    .execute()

                let decoder = JSONDecoder.supabaseDecoder()
                let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

                // Group by day
                var visitsByDay: [Date: Int] = [:]
                for visit in visits {
                    let normalizedDate = normalizeDate(visit.entryTime)
                    visitsByDay[normalizedDate, default: 0] += 1
                }

                await MainActor.run {
                    visitsForMonth = visitsByDay
                }
            } catch {
                print("Error loading visits for month: \(error)")
            }
        }
    }

    private func loadVisitsForSelectedDay() {
        Task {
            guard let userId = supabaseManager.getCurrentUser()?.id else { return }

            await MainActor.run {
                isLoading = true
            }

            // Get start and end of selected day
            let startOfDay = calendar.startOfDay(for: selectedDate)
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

            do {
                let client = await supabaseManager.getPostgrestClient()
                let response = try await client
                    .from("location_visits")
                    .select()
                    .eq("user_id", value: userId.uuidString)
                    .gte("entry_time", value: startOfDay.ISO8601Format())
                    .lt("entry_time", value: endOfDay.ISO8601Format())
                    .execute()

                let decoder = JSONDecoder.supabaseDecoder()
                let visits: [LocationVisitRecord] = try decoder.decode([LocationVisitRecord].self, from: response.data)

                await MainActor.run {
                    visitsForSelectedDay = visits
                    isLoading = false
                }
            } catch {
                print("Error loading visits for day: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    LocationTimelineView(colorScheme: .light)
}
