import SwiftUI

struct PlaceDetailSheet: View {
    let place: SavedPlace
    let onDismiss: () -> Void
    var isFromRanking: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var mapsService = GoogleMapsService.shared
    @State private var isLoading = true
    @State private var showingMapSelection = false

    var isPlaceDataComplete: Bool {
        !place.name.isEmpty && !place.address.isEmpty && !place.displayName.isEmpty
    }

    private var pageBackgroundColor: Color {
        colorScheme == .dark ? Color.gmailDarkBackground : Color.white
    }

    private var sectionFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
    }

    private var sectionBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isPlaceDataComplete {
                // Show loading state if place data is incomplete
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("Loading location details...")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                        .ignoresSafeArea()
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Spacer()
                            .frame(height: 8)

                        sectionCard {
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(place.displayName)
                                        .font(FontManager.geist(size: 34, weight: .bold))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)

                                    HStack(spacing: 8) {
                                        Text(place.category)
                                            .font(FontManager.geist(size: 12, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                Capsule()
                                                    .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                                            )

                                        if let rating = place.rating {
                                            HStack(spacing: 4) {
                                                Image(systemName: "star.fill")
                                                    .font(FontManager.geist(size: 12, weight: .semibold))
                                                    .foregroundColor(.yellow)
                                                Text(String(format: "%.1f", rating))
                                                    .font(FontManager.geist(size: 14, weight: .semibold))
                                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                            }
                                        }
                                    }
                                }

                                Text(place.address)
                                    .font(FontManager.geist(size: 16, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.82))

                                HStack(spacing: 10) {
                                    if let phone = place.phone {
                                        Button(action: { callPhone(phone) }) {
                                            Text("Call")
                                                .font(FontManager.geist(size: 14, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? .black : .white)
                                                .padding(.horizontal, 18)
                                                .padding(.vertical, 9)
                                                .background(
                                                    Capsule()
                                                        .fill(colorScheme == .dark ? Color.white : Color.black)
                                                )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }

                                    Button(action: { openInMaps(place: place) }) {
                                        Text("Directions")
                                            .font(FontManager.geist(size: 14, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 9)
                                            .background(
                                                Capsule()
                                                    .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06))
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }

                        if let hours = place.openingHours, !hours.isEmpty {
                            sectionCard {
                                OpeningHoursSection(hours: hours, colorScheme: colorScheme)
                            }
                        }

                        sectionCard {
                            LocationMemorySection(place: place, colorScheme: colorScheme)
                        }

                        if !isFromRanking {
                            PlaceVisitCalendarHistoryCard(place: place)
                        }

                        Spacer()
                            .frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                }
                .background(pageBackgroundColor)
            }
        }
        .background(pageBackgroundColor.ignoresSafeArea())
        .alert("Choose Map App", isPresented: $showingMapSelection) {
            Button("Google Maps") {
                UserDefaults.standard.set("google", forKey: "preferredMapApp")
                mapsService.openInGoogleMaps(place: place, preferGoogle: true)
            }
            Button("Apple Maps") {
                UserDefaults.standard.set("apple", forKey: "preferredMapApp")
                mapsService.openInGoogleMaps(place: place, preferGoogle: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Which map app would you like to use? This will be your default choice.")
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(sectionFillColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(sectionBorderColor, lineWidth: 1)
                    )
            )
    }

    private func callPhone(_ phone: String) {
        // Remove formatting from phone number
        let cleanedPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        if let phoneURL = URL(string: "tel://\(cleanedPhone)"),
           UIApplication.shared.canOpenURL(phoneURL) {
            UIApplication.shared.open(phoneURL)
        }
    }
    
    private func openInMaps(place: SavedPlace) {
        // Check if user has a preferred map app
        let userDefaults = UserDefaults.standard
        let preferredMapKey = "preferredMapApp"
        
        if let preferredMap = userDefaults.string(forKey: preferredMapKey) {
            // User has a preference, use it
            if preferredMap == "google" {
                mapsService.openInGoogleMaps(place: place, preferGoogle: true)
            } else {
                mapsService.openInGoogleMaps(place: place, preferGoogle: false)
            }
        } else {
            // First time - show selection
            showingMapSelection = true
        }
    }
}

// MARK: - Calendar Visit History

struct PlaceVisitCalendarHistoryCard: View {
    let place: SavedPlace
    @Environment(\.colorScheme) var colorScheme

    @State private var visitHistory: [VisitHistoryItem] = []
    @State private var stats: LocationVisitStats?
    @State private var isLoading = false
    @State private var currentMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var monthPageSelection: Int = 1

    private let calendar = Calendar.current
    private let rowHeight: CGFloat = 50

    private var cardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62)
    }

    private var groupedByDay: [Date: [VisitHistoryItem]] {
        Dictionary(grouping: visitHistory) { item in
            normalizeDate(item.visit.entryTime)
        }
    }

    private var selectedDayVisits: [VisitHistoryItem] {
        groupedByDay[normalizeDate(selectedDate)]?
            .sorted { $0.visit.entryTime > $1.visit.entryTime } ?? []
    }

    private var selectedDayDurationMinutes: Int {
        selectedDayVisits.reduce(0) { total, item in
            total + effectiveDurationMinutes(for: item.visit)
        }
    }

    private var monthVisitCount: Int {
        let interval = calendar.dateInterval(of: .month, for: currentMonth)
        return visitHistory.filter { item in
            guard let interval else { return false }
            return interval.contains(item.visit.entryTime)
        }.count
    }

    private var monthAverageDuration: String {
        let interval = calendar.dateInterval(of: .month, for: currentMonth)
        let monthly = visitHistory.filter { item in
            guard let interval else { return false }
            return interval.contains(item.visit.entryTime)
        }
        guard !monthly.isEmpty else { return "0 min" }
        let total = monthly.reduce(0) { $0 + effectiveDurationMinutes(for: $1.visit) }
        return formatDuration(max(total / monthly.count, 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Visit History")
                    .font(FontManager.geist(size: 18, weight: .semibold))
                    .foregroundColor(primaryText)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("\(visitHistory.count) total")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.05))
                        )
                }
            }

            monthInsightsRow
            calendarSection
            selectedDaySection
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
        .onAppear {
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("VisitHistoryUpdated"))) { _ in
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeofenceVisitCreated"))) { _ in
            loadData()
        }
    }

    private var monthInsightsRow: some View {
        HStack(spacing: 10) {
            summaryTile(title: "This month", value: "\(monthVisitCount) visits")
            summaryTile(title: "Avg duration", value: monthAverageDuration)
            summaryTile(title: "All visits", value: "\(stats?.totalVisits ?? visitHistory.count)")
        }
    }

    private func summaryTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(secondaryText)
            Text(value)
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
        )
    }

    private var calendarSection: some View {
        VStack(spacing: 0) {
            calendarHeader
            weekdayHeader
            swipeableMonthGrid
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(cardBorder, lineWidth: 1)
                )
        )
    }

    private var calendarHeader: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    shiftMonth(by: -1)
                }
                HapticManager.shared.selection()
            }) {
                Image(systemName: "chevron.left")
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(primaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            Text(monthHeaderFormatter.string(from: currentMonth))
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(primaryText)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    let today = calendar.startOfDay(for: Date())
                    currentMonth = today
                    selectedDate = today
                    monthPageSelection = 1
                }
                HapticManager.shared.selection()
            }) {
                Text("Today")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())

            Button(action: {
                withAnimation(.easeInOut(duration: 0.25)) {
                    shiftMonth(by: 1)
                }
                HapticManager.shared.selection()
            }) {
                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(primaryText)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["S", "M", "T", "W", "T", "F", "S"], id: \.self) { day in
                Text(day)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var swipeableMonthGrid: some View {
        TabView(selection: $monthPageSelection) {
            monthGrid(for: monthOffset(-1))
                .frame(height: CGFloat(weeksInMonth(for: monthOffset(-1)).count) * rowHeight, alignment: .top)
                .tag(0)

            monthGrid(for: currentMonth)
                .frame(height: CGFloat(weeksInMonth(for: currentMonth).count) * rowHeight, alignment: .top)
                .tag(1)

            monthGrid(for: monthOffset(1))
                .frame(height: CGFloat(weeksInMonth(for: monthOffset(1)).count) * rowHeight, alignment: .top)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: CGFloat(weeksInMonth(for: currentMonth).count) * rowHeight)
        .padding(.bottom, 10)
        .onChange(of: monthPageSelection) { newValue in
            guard newValue != 1 else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                shiftMonth(by: newValue == 0 ? -1 : 1)
            }
            DispatchQueue.main.async {
                monthPageSelection = 1
            }
        }
    }

    private func monthGrid(for month: Date) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(weeksInMonth(for: month).enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if let date {
                            calendarDayCell(for: date, in: month)
                                .frame(maxWidth: .infinity)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: rowHeight)
            }
        }
    }

    private func calendarDayCell(for date: Date, in month: Date) -> some View {
        let normalized = normalizeDate(date)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let inCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let dots = min(groupedByDay[normalized]?.count ?? 0, 3)

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = normalized
            }
            HapticManager.shared.selection()
        }) {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(FontManager.geist(size: 12, weight: isToday || isSelected ? .semibold : .regular))
                    .foregroundColor(
                        isSelected ? (colorScheme == .dark ? .black : .white) :
                        !inCurrentMonth ? secondaryText.opacity(0.55) :
                        primaryText
                    )
                    .frame(width: 24, height: 24)
                    .background(
                        Group {
                            if isSelected {
                                Circle().fill(colorScheme == .dark ? Color.white : Color.black)
                            } else if isToday {
                                Circle()
                                    .stroke(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.3), lineWidth: 1.5)
                            }
                        }
                    )

                if dots > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<dots, id: \.self) { _ in
                            Circle()
                                .fill(isSelected ? (colorScheme == .dark ? Color.black : Color.white) : primaryText.opacity(0.8))
                                .frame(width: 3.5, height: 3.5)
                        }
                    }
                } else {
                    Color.clear.frame(height: 3.5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedDayTitle)
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(primaryText)

                Spacer()

                Text("\(selectedDayVisits.count) visit\(selectedDayVisits.count == 1 ? "" : "s") · \(formatDuration(selectedDayDurationMinutes))")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(secondaryText)
            }

            if selectedDayVisits.isEmpty {
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                    .frame(height: 86)
                    .overlay(
                        Text("No visits on this day")
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(secondaryText)
                    )
            } else {
                VStack(spacing: 8) {
                    ForEach(selectedDayVisits, id: \.visit.id) { item in
                        PlaceDayVisitRow(visit: item.visit)
                    }
                }
            }
        }
    }

    private func loadData() {
        isLoading = true
        Task {
            await LocationVisitAnalytics.shared.fetchStats(for: place.id)
            let fetched = await LocationVisitAnalytics.shared.fetchVisitHistory(for: place.id, limit: 500)

            await MainActor.run {
                visitHistory = fetched
                stats = LocationVisitAnalytics.shared.visitStats[place.id]

                if groupedByDay[normalizeDate(selectedDate)] == nil,
                   let latest = fetched.first?.visit.entryTime {
                    selectedDate = normalizeDate(latest)
                }

                if !calendar.isDate(currentMonth, equalTo: selectedDate, toGranularity: .month) {
                    currentMonth = selectedDate
                }

                monthPageSelection = 1
                isLoading = false
            }
        }
    }

    private func normalizeDate(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components) ?? date
    }

    private func monthOffset(_ value: Int) -> Date {
        calendar.date(byAdding: .month, value: value, to: currentMonth) ?? currentMonth
    }

    private func shiftMonth(by value: Int) {
        currentMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) ?? currentMonth
    }

    private func weeksInMonth(for month: Date) -> [[Date?]] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = calendar.startOfDay(for: interval.start)
        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leading)
        var current = firstDay
        let monthEnd = calendar.startOfDay(for: interval.end)

        while current < monthEnd {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }

        while days.count % 7 != 0 {
            days.append(nil)
        }

        return stride(from: 0, to: days.count, by: 7).map { index in
            Array(days[index..<index+7])
        }
    }

    private var selectedDayTitle: String {
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    private var monthHeaderFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    private func effectiveDurationMinutes(for visit: LocationVisitRecord) -> Int {
        if let duration = visit.durationMinutes {
            return max(duration, 1)
        }
        if let exit = visit.exitTime {
            return max(Int(exit.timeIntervalSince(visit.entryTime) / 60), 1)
        }
        return max(Int(Date().timeIntervalSince(visit.entryTime) / 60), 1)
    }

    private func formatDuration(_ minutes: Int) -> String {
        let hrs = minutes / 60
        let mins = minutes % 60
        if hrs > 0 && mins > 0 { return "\(hrs)h \(mins)m" }
        if hrs > 0 { return "\(hrs)h" }
        return "\(mins)m"
    }
}

struct PlaceDayVisitRow: View {
    let visit: LocationVisitRecord
    @Environment(\.colorScheme) var colorScheme

    private var primaryText: Color { colorScheme == .dark ? .white : .black }
    private var secondaryText: Color { colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entryTime)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(secondaryText)

                Text(timeRange)
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(primaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(durationLabel)
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(primaryText)

                if let notes = visit.visitNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(notes)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
        )
    }

    private var entryTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: visit.entryTime)
    }

    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = formatter.string(from: visit.entryTime)
        if let exit = visit.exitTime {
            return "\(start) - \(formatter.string(from: exit))"
        }
        return "\(start) - Active"
    }

    private var durationLabel: String {
        let minutes: Int
        if let duration = visit.durationMinutes {
            minutes = max(duration, 1)
        } else if let exit = visit.exitTime {
            minutes = max(Int(exit.timeIntervalSince(visit.entryTime) / 60), 1)
        } else {
            minutes = max(Int(Date().timeIntervalSince(visit.entryTime) / 60), 1)
        }

        let hrs = minutes / 60
        let mins = minutes % 60
        if hrs > 0 && mins > 0 { return "\(hrs)h \(mins)m" }
        if hrs > 0 { return "\(hrs)h" }
        return "\(mins)m"
    }
}

// MARK: - Location Memory Section

struct LocationMemorySection: View {
    let place: SavedPlace
    let colorScheme: ColorScheme
    
    @StateObject private var memoryService = LocationMemoryService.shared
    @State private var memories: [LocationMemory] = []
    @State private var isLoading = false
    @State private var showingPurchaseInput = false
    @State private var showingPurposeInput = false
    @State private var purchaseText = ""
    @State private var purposeText = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // General reasons for visiting this location (higher level)
                    if let purposeMemory = memories.first(where: { $0.memoryType == .purpose }) {
                        Button(action: {
                            purposeText = purposeMemory.content
                            showingPurposeInput = true
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Why it matters")
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                    Text(purposeMemory.content)
                                        .font(FontManager.geist(size: 15, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(nil)
                                }

                                Spacer()

                                // Edit chevron
                                Image(systemName: "chevron.right")
                                    .font(FontManager.geist(size: 12, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Button(action: {
                            purposeText = ""
                            showingPurposeInput = true
                        }) {
                            HStack(spacing: 12) {
                                Text("Why is this location important to you?")
                                    .font(FontManager.geist(size: 15, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                    .multilineTextAlignment(.leading)

                                Spacer()

                                Image(systemName: "plus.circle.fill")
                                    .font(FontManager.geist(size: 20, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1),
                                        lineWidth: 1.5,
                                        antialiased: true
                                    )
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // What user usually gets (optional secondary info)
                    if let purchaseMemory = memories.first(where: { $0.memoryType == .purchase }) {
                        Button(action: {
                            purchaseText = purchaseMemory.content
                            showingPurchaseInput = true
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "cart.fill")
                                    .font(FontManager.geist(size: 20, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Usually get")
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                    Text(purchaseMemory.content)
                                        .font(FontManager.geist(size: 15, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(nil)

                                    if let items = purchaseMemory.items, !items.isEmpty {
                                        Text("Items: \(items.joined(separator: ", "))")
                                            .font(FontManager.geist(size: 12, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                            .padding(.top, 2)
                                    }
                                }

                                Spacer()

                                // Edit chevron
                                Image(systemName: "chevron.right")
                                    .font(FontManager.geist(size: 12, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .onAppear {
            loadMemories()
        }
        .sheet(isPresented: $showingPurchaseInput) {
            LocationMemoryInputSheet(
                place: place,
                memoryType: .purchase,
                question: "What do you usually get?",
                placeholder: "e.g., vitamins, allergy meds, groceries...",
                initialText: purchaseText,
                colorScheme: colorScheme,
                onSave: { text in
                    await savePurchaseMemory(text: text)
                    showingPurchaseInput = false
                    purchaseText = ""
                },
                onDismiss: {
                    showingPurchaseInput = false
                    purchaseText = ""
                }
            )
        }
        .sheet(isPresented: $showingPurposeInput) {
            LocationMemoryInputSheet(
                place: place,
                memoryType: .purpose,
                question: "Why is this location important to you?",
                placeholder: "e.g., family time, routine errands, a place you recharge...",
                initialText: purposeText,
                colorScheme: colorScheme,
                onSave: { text in
                    await savePurposeMemory(text: text)
                    showingPurposeInput = false
                    purposeText = ""
                },
                onDismiss: {
                    showingPurposeInput = false
                    purposeText = ""
                }
            )
        }
    }
    
    private func loadMemories() {
        isLoading = true
        Task {
            do {
                memories = try await memoryService.getMemories(for: place.id)
            } catch {
                print("❌ Failed to load location memories: \(error)")
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func savePurchaseMemory(text: String) async {
        let extraction = NaturalLanguageExtractionService.shared.extractInfo(from: text)
        
        do {
            try await memoryService.saveMemory(
                placeId: place.id,
                type: .purchase,
                content: extraction.rawText,
                items: extraction.items.isEmpty ? nil : extraction.items,
                frequency: extraction.frequency
            )
            await loadMemories()
        } catch {
            print("❌ Failed to save purchase memory: \(error)")
        }
    }
    
    private func savePurposeMemory(text: String) async {
        do {
            try await memoryService.saveMemory(
                placeId: place.id,
                type: .purpose,
                content: text
            )
            await loadMemories()
        } catch {
            print("❌ Failed to save purpose memory: \(error)")
        }
    }
}

struct MemoryRow: View {
    let icon: String
    let label: String
    let content: String
    let items: [String]?
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(FontManager.geist(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                
                Text(content)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                if let items = items, !items.isEmpty {
                    Text("Items: \(items.joined(separator: ", "))")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Edit indicator
            Image(systemName: "pencil")
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
        }
    }
}

struct LocationMemoryInputSheet: View {
    let place: SavedPlace
    let memoryType: MemoryType
    let question: String
    let placeholder: String
    let initialText: String
    let colorScheme: ColorScheme
    let onSave: (String) async -> Void
    let onDismiss: () -> Void

    @State private var inputText: String
    @FocusState private var isFocused: Bool

    enum MemoryType {
        case purpose
        case purchase
    }

    init(place: SavedPlace, memoryType: MemoryType, question: String, placeholder: String, initialText: String = "", colorScheme: ColorScheme, onSave: @escaping (String) async -> Void, onDismiss: @escaping () -> Void) {
        self.place = place
        self.memoryType = memoryType
        self.question = question
        self.placeholder = placeholder
        self.initialText = initialText
        self.colorScheme = colorScheme
        self.onSave = onSave
        self.onDismiss = onDismiss
        _inputText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Location name
                Text(place.displayName)
                    .font(FontManager.geist(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Divider()

                // Question
                Text(question)
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.top, 8)

                // Input field
                TextField(placeholder, text: $inputText, axis: .vertical)
                    .font(FontManager.geist(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
                    .lineLimit(3...6)
                    .focused($isFocused)

                Spacer()
            }
            .padding(20)
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle(memoryType == .purpose ? "Location Memory" : "What You Get")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await onSave(inputText.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

// MARK: - Opening Hours Section
struct OpeningHoursSection: View {
    let hours: [String]
    let colorScheme: ColorScheme
    @State private var isExpanded = false
    
    // Get current day abbreviation (Mon, Tue, etc.)
    private var currentDayPrefix: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"  // Short weekday name
        return formatter.string(from: Date())
    }
    
    // Find today's hours from the array
    private var todayHours: String? {
        let dayPrefixes = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let todayPrefix = currentDayPrefix
        
        // Try to find matching day
        for hour in hours {
            for prefix in dayPrefixes {
                if hour.hasPrefix(prefix) && todayPrefix.hasPrefix(prefix.prefix(3)) {
                    return hour
                }
            }
        }
        
        // If no match, return first hour as fallback
        return hours.first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row - tappable to expand/collapse
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.fill")
                        .font(FontManager.geist(size: 20, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hours")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        
                        if let today = todayHours {
                            Text(today)
                                .font(FontManager.geist(size: 15, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded hours list
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(hours, id: \.self) { hour in
                        HStack {
                            Text(hour)
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.85))
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 32)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    PlaceDetailSheet(
        place: SavedPlace(
            googlePlaceId: "test1",
            name: "Blue Bottle Coffee",
            address: "1355 Market St, San Francisco, CA 94103",
            latitude: 37.7749,
            longitude: -122.4194,
            phone: "(415) 555-1234",
            photos: [
                "https://via.placeholder.com/280x200",
                "https://via.placeholder.com/280x200"
            ],
            rating: 4.5,
            openingHours: [
                "Monday: 7:00 AM – 6:00 PM",
                "Tuesday: 7:00 AM – 6:00 PM",
                "Wednesday: 7:00 AM – 6:00 PM",
                "Thursday: 7:00 AM – 6:00 PM",
                "Friday: 7:00 AM – 6:00 PM",
                "Saturday: 8:00 AM – 5:00 PM",
                "Sunday: 8:00 AM – 5:00 PM"
            ]
        ),
        onDismiss: {}
    )
}
