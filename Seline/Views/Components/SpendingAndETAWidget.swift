import SwiftUI
import CoreLocation

struct SpendingAndETAWidget: View {
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var navigationService = NavigationService.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @Environment(\.colorScheme) var colorScheme

    var isVisible: Bool = true

    @State private var locationPreferences: UserLocationPreferences?
    @State private var showLocationSetup = false
    @State private var setupLocationSlot: LocationSlot?
    @State private var showReceiptStats = false
    @State private var showETAEditModal = false
    @State private var upcomingRecurringExpenses: [(title: String, amount: Double, date: Date)] = []

    private var currentYearStats: YearlyReceiptSummary? {
        let year = Calendar.current.component(.year, from: Date())
        return notesManager.getReceiptStatistics(year: year).first
    }

    private var monthlyTotal: Double {
        guard let stats = currentYearStats else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        return stats.monthlySummaries.filter { summary in
            let month = calendar.component(.month, from: summary.monthDate)
            let year = calendar.component(.year, from: summary.monthDate)
            return month == currentMonth && year == currentYear
        }.reduce(0) { $0 + $1.monthlyTotal }
    }

    private var previousMonthTotal: Double {
        guard let stats = currentYearStats else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let previousMonth = currentMonth - 1
        let previousYear = previousMonth <= 0 ? calendar.component(.year, from: now) - 1 : calendar.component(.year, from: now)
        let adjustedPreviousMonth = previousMonth <= 0 ? 12 : previousMonth

        return stats.monthlySummaries.filter { summary in
            let month = calendar.component(.month, from: summary.monthDate)
            let year = calendar.component(.year, from: summary.monthDate)
            return month == adjustedPreviousMonth && year == previousYear
        }.reduce(0) { $0 + $1.monthlyTotal }
    }

    private var monthOverMonthPercentage: (percentage: Double, isIncrease: Bool) {
        guard previousMonthTotal > 0 else { return (0, false) }
        let change = ((monthlyTotal - previousMonthTotal) / previousMonthTotal) * 100
        return (abs(change), change >= 0)
    }

    @State private var categoryBreakdownCache: [(category: String, amount: Double, percentage: Double)] = []

    private var categoryBreakdown: [(category: String, amount: Double, percentage: Double)] {
        return categoryBreakdownCache
    }

    private func categoryIcon(_ category: String) -> String {
        return CategoryIconProvider.icon(for: category)
    }

    private func categoryColor(_ category: String) -> Color {
        return CategoryIconProvider.color(for: category)
    }

    private func openNavigation(to coordinate: CLLocationCoordinate2D?, address: String?) {
        guard let coordinate = coordinate, let address = address else { return }
        let url = "comgooglemaps://?q=\(address)&center=\(coordinate.latitude),\(coordinate.longitude)"
        if let encodedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encodedUrl) {
            UIApplication.shared.open(url)
        }
    }

    private func updateETAs() {
        guard let preferences = locationPreferences else { return }

        if locationService.currentLocation == nil {
            locationService.requestLocationPermission()
            return
        }

        guard let currentLocation = locationService.currentLocation else { return }

        Task {
            await navigationService.updateETAs(
                currentLocation: currentLocation,
                location1: preferences.location1Coordinate,
                location2: preferences.location2Coordinate,
                location3: preferences.location3Coordinate,
                location4: preferences.location4Coordinate
            )
        }
    }

    private func updateCategoryBreakdown() {
        Task {
            guard let stats = currentYearStats else { return }
            let calendar = Calendar.current
            let now = Date()
            let currentMonth = calendar.component(.month, from: now)
            let currentYear = calendar.component(.year, from: now)

            // Get all receipts for current month and year
            var monthReceipts: [ReceiptStat] = []
            for monthlySummary in stats.monthlySummaries {
                let month = calendar.component(.month, from: monthlySummary.monthDate)
                let year = calendar.component(.year, from: monthlySummary.monthDate)
                if month == currentMonth && year == currentYear {
                    monthReceipts.append(contentsOf: monthlySummary.receipts)
                }
            }

            // Categorize receipts using the service
            var categoryTotals: [String: Double] = [:]
            for receipt in monthReceipts {
                let category = await ReceiptCategorizationService.shared.categorizeReceipt(receipt.title)
                let current = categoryTotals[category] ?? 0
                categoryTotals[category] = current + receipt.amount
            }

            // Convert to sorted array with percentages
            let total = categoryTotals.values.reduce(0, +)
            let result = categoryTotals
                .map { (category: $0.key, amount: $0.value, percentage: total > 0 ? ($0.value / total) * 100 : 0) }
                .sorted { $0.amount > $1.amount }
                .prefix(5)
                .map { $0 }

            DispatchQueue.main.async {
                self.categoryBreakdownCache = result
                // Update widget with spending data
                self.updateWidgetWithSpendingData()
            }
        }
    }

    private func updateWidgetWithSpendingData() {
        // Write spending data to shared UserDefaults for widget display
        if let userDefaults = UserDefaults(suiteName: "group.seline") {
            userDefaults.set(monthlyTotal, forKey: "widgetMonthlySpending")
            userDefaults.set(monthOverMonthPercentage.percentage, forKey: "widgetMonthOverMonthPercentage")
            userDefaults.set(monthOverMonthPercentage.isIncrease, forKey: "widgetIsSpendingIncreasing")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            spendingCard()
        }
        .frame(height: 150)
        .onAppear {
            locationService.requestLocationPermission()
            updateCategoryBreakdown()
            loadUpcomingRecurringExpenses()
            Task {
                do {
                    locationPreferences = try await supabaseManager.loadLocationPreferences()

                    // Initial refresh or check if 5km moved since last refresh
                    if let currentLocation = locationService.currentLocation, let preferences = locationPreferences {
                        await navigationService.checkAndRefreshIfNeeded(
                            currentLocation: currentLocation,
                            location1: preferences.location1Coordinate,
                            location2: preferences.location2Coordinate,
                            location3: preferences.location3Coordinate,
                            location4: preferences.location4Coordinate
                        )
                    } else {
                        // Fallback to direct update if no location yet
                        updateETAs()
                    }
                } catch {
                    print("Failed to load location preferences: \(error)")
                }
            }
        }
        .onChange(of: locationService.currentLocation) { location in
            // Auto-refresh ETAs when user moves 5km+
            guard let currentLocation = location, let preferences = locationPreferences else { return }

            Task {
                await navigationService.checkAndRefreshIfNeeded(
                    currentLocation: currentLocation,
                    location1: preferences.location1Coordinate,
                    location2: preferences.location2Coordinate,
                    location3: preferences.location3Coordinate,
                    location4: preferences.location4Coordinate
                )
            }
        }
        .onChange(of: notesManager.notes.count) { _ in
            updateCategoryBreakdown()
            loadUpcomingRecurringExpenses()
        }
        .onChange(of: showETAEditModal) { isShowing in
            if !isShowing {
                // Reload location preferences when edit sheet closes
                Task {
                    do {
                        locationPreferences = try await supabaseManager.loadLocationPreferences()
                        updateETAs()
                    } catch {
                        print("Failed to reload location preferences: \(error)")
                    }
                }
            }
        }
        .sheet(isPresented: $showETAEditModal) {
            AllLocationsEditView(currentPreferences: locationPreferences)
        }
        .sheet(isPresented: $showLocationSetup) {
            LocationSetupView()
        }
        .sheet(isPresented: $showReceiptStats) {
            ReceiptStatsView(isPopup: true)
                .presentationDetents([.large])
        }
    }

    private func spendingCard() -> some View {
        Button(action: { showReceiptStats = true }) {
            VStack(alignment: .leading, spacing: 5) {
                // Monthly spending amount
                Text(CurrencyParser.formatAmountNoDecimals(monthlyTotal))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.25))

                // Month over month percentage
                HStack(spacing: 4) {
                    Image(systemName: monthOverMonthPercentage.isIncrease ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text(String(format: "%.0f%% last month", monthOverMonthPercentage.percentage))
                        .font(.system(size: 11, weight: .regular))
                }
                .foregroundColor(monthOverMonthPercentage.isIncrease ? Color(red: 0.9, green: 0.4, blue: 0.4) : (colorScheme == .dark ? Color(red: 0.4, green: 0.9, blue: 0.4) : Color(red: 0.2, green: 0.65, blue: 0.2)))

                // Categories - below % text
                topCategoryView

                // Recent transactions
                recentTransactionsView
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
        )
        .cornerRadius(12)
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.05),
            radius: 8,
            x: 0,
            y: 2
        )
    }

    private var daysLeftInMonth: Int {
        let calendar = Calendar.current
        let now = Date()
        let range = calendar.range(of: .day, in: .month, for: now)!
        let numDays = range.count
        let currentDay = calendar.component(.day, from: now)
        return numDays - currentDay
    }

    private var nextMonthName: String {
        let calendar = Calendar.current
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: nextMonth)
    }

    private func formatExpenseDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let expenseDay = calendar.startOfDay(for: date)

        if expenseDay == today {
            return "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), expenseDay == tomorrow {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func loadUpcomingRecurringExpenses() {
        Task {
            do {
                let recurringExpenses = try await RecurringExpenseService.shared.fetchActiveRecurringExpenses()
                let calendar = Calendar.current
                let now = Date()
                var expenses: [(title: String, amount: Double, date: Date)] = []

                // Get next 7 days
                let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: now)!

                for expense in recurringExpenses {
                    let instances = try await RecurringExpenseService.shared.fetchInstances(for: expense.id)

                    for instance in instances {
                        let instanceDay = calendar.startOfDay(for: instance.occurrenceDate)
                        let nowStart = calendar.startOfDay(for: now)
                        let sevenDaysStart = calendar.startOfDay(for: sevenDaysFromNow)

                        // Check if instance is within next 7 days and is pending
                        if instanceDay >= nowStart && instanceDay <= sevenDaysStart {
                            if instance.status == .pending {
                                expenses.append((title: expense.title, amount: Double(truncating: expense.amount as NSDecimalNumber), date: instance.occurrenceDate))
                            }
                        }
                    }
                }

                // Sort by date ascending (earliest first)
                expenses.sort { $0.date < $1.date }

                await MainActor.run {
                    upcomingRecurringExpenses = expenses
                }
            } catch {
                print("Error loading recurring expenses: \(error)")
            }
        }
    }

    private var topCategoryView: some View {
        Group {
            if !categoryBreakdown.isEmpty {
                HStack(spacing: 4) {
                    ForEach(categoryBreakdown.prefix(2), id: \.category) { category in
                        HStack(spacing: 2) {
                            Text(categoryIcon(category.category))
                                .font(.system(size: 11))

                            VStack(alignment: .leading, spacing: 0) {
                                Text(category.category)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Text(String(format: "%.0f%%", category.percentage))
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                            }

                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    private var recentTransactionsView: some View {
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        let currentMonthNotes = notesManager.notes.filter { note in
            let noteMonth = calendar.component(.month, from: note.dateCreated ?? Date())
            let noteYear = calendar.component(.year, from: note.dateCreated ?? Date())
            return noteMonth == currentMonth && noteYear == currentYear
        }.sorted { ($0.dateCreated ?? Date()) > ($1.dateCreated ?? Date()) }.prefix(3)

        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(currentMonthNotes), id: \.id) { note in
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    Spacer()

                    Text(formatExpenseDate(note.dateCreated ?? Date()))
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                    if let amount = extractAmount(from: note.content ?? "") {
                        Text(CurrencyParser.formatAmountNoDecimals(amount))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
        }
    }

    private func extractAmount(from text: String) -> Double? {
        let pattern = "\\$[0-9,]+(?:\\.[0-9]{2})?"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text) {
                    let amountStr = String(text[range]).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
                    return Double(amountStr)
                }
            }
        }
        return nil
    }

    private func navigationCard2x2(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            Spacer()

            // Top row - Location 1 and Location 2
            HStack(spacing: 8) {
                // Location 1
                navigationETACircle(
                    icon: locationPreferences?.location1Icon ?? "house.fill",
                    eta: navigationService.location1ETA,
                    isLocationSet: locationPreferences?.location1Coordinate != nil,
                    onTap: {
                        if locationPreferences?.location1Coordinate != nil {
                            openNavigation(to: locationPreferences?.location1Coordinate, address: locationPreferences?.location1Address)
                        }
                    },
                    onLongPress: {
                        showETAEditModal = true
                    }
                )

                // Location 2
                navigationETACircle(
                    icon: locationPreferences?.location2Icon ?? "briefcase.fill",
                    eta: navigationService.location2ETA,
                    isLocationSet: locationPreferences?.location2Coordinate != nil,
                    onTap: {
                        if locationPreferences?.location2Coordinate != nil {
                            openNavigation(to: locationPreferences?.location2Coordinate, address: locationPreferences?.location2Address)
                        }
                    },
                    onLongPress: {
                        showETAEditModal = true
                    }
                )
            }

            // Bottom row - Location 3 and Location 4
            HStack(spacing: 8) {
                // Location 3
                navigationETACircle(
                    icon: locationPreferences?.location3Icon ?? "fork.knife",
                    eta: navigationService.location3ETA,
                    isLocationSet: locationPreferences?.location3Coordinate != nil,
                    onTap: {
                        if locationPreferences?.location3Coordinate != nil {
                            openNavigation(to: locationPreferences?.location3Coordinate, address: locationPreferences?.location3Address)
                        }
                    },
                    onLongPress: {
                        showETAEditModal = true
                    }
                )

                // Location 4
                navigationETACircle(
                    icon: locationPreferences?.location4Icon ?? "dumbbell.fill",
                    eta: navigationService.location4ETA,
                    isLocationSet: locationPreferences?.location4Coordinate != nil,
                    onTap: {
                        if locationPreferences?.location4Coordinate != nil {
                            openNavigation(to: locationPreferences?.location4Coordinate, address: locationPreferences?.location4Address)
                        }
                    },
                    onLongPress: {
                        showETAEditModal = true
                    }
                )
            }

            Spacer()
        }
        .padding(10)
        .frame(maxWidth: width, maxHeight: .infinity)
    }

    private func navigationETACircle(icon: String, eta: String?, isLocationSet: Bool, onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.25))

                if navigationService.isLoading && isLocationSet {
                    ProgressView()
                        .scaleEffect(0.6, anchor: .center)
                        .frame(height: 12)
                } else if let eta = eta, isLocationSet {
                    Text(eta)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                        .lineLimit(1)
                } else {
                    Text("--")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.03))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                HapticManager.shared.selection()
                onLongPress()
            }) {
                Label("Edit Locations", systemImage: "pencil")
            }
        }
    }

    private func navigationCard(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Location 1
            NavigationETARow(
                icon: locationPreferences?.location1Icon ?? "house.fill",
                eta: navigationService.location1ETA,
                isLocationSet: locationPreferences?.location1Coordinate != nil,
                isLoading: navigationService.isLoading,
                colorScheme: colorScheme,
                onTap: {
                    if locationPreferences?.location1Coordinate != nil {
                        openNavigation(to: locationPreferences?.location1Coordinate, address: locationPreferences?.location1Address)
                    } else {
                        setupLocationSlot = .location1
                        showLocationSetup = true
                    }
                },
                onLongPress: {
                    setupLocationSlot = .location1
                    showLocationSetup = true
                }
            )

            // Location 2
            NavigationETARow(
                icon: locationPreferences?.location2Icon ?? "briefcase.fill",
                eta: navigationService.location2ETA,
                isLocationSet: locationPreferences?.location2Coordinate != nil,
                isLoading: navigationService.isLoading,
                colorScheme: colorScheme,
                onTap: {
                    if locationPreferences?.location2Coordinate != nil {
                        openNavigation(to: locationPreferences?.location2Coordinate, address: locationPreferences?.location2Address)
                    } else {
                        setupLocationSlot = .location2
                        showLocationSetup = true
                    }
                },
                onLongPress: {
                    setupLocationSlot = .location2
                    showLocationSetup = true
                }
            )

            // Location 3
            NavigationETARow(
                icon: locationPreferences?.location3Icon ?? "fork.knife",
                eta: navigationService.location3ETA,
                isLocationSet: locationPreferences?.location3Coordinate != nil,
                isLoading: navigationService.isLoading,
                colorScheme: colorScheme,
                onTap: {
                    if locationPreferences?.location3Coordinate != nil {
                        openNavigation(to: locationPreferences?.location3Coordinate, address: locationPreferences?.location3Address)
                    } else {
                        setupLocationSlot = .location3
                        showLocationSetup = true
                    }
                },
                onLongPress: {
                    setupLocationSlot = .location3
                    showLocationSetup = true
                }
            )

            // Location 4
            NavigationETARow(
                icon: locationPreferences?.location4Icon ?? "dumbbell.fill",
                eta: navigationService.location4ETA,
                isLocationSet: locationPreferences?.location4Coordinate != nil,
                isLoading: navigationService.isLoading,
                colorScheme: colorScheme,
                onTap: {
                    if locationPreferences?.location4Coordinate != nil {
                        openNavigation(to: locationPreferences?.location4Coordinate, address: locationPreferences?.location4Address)
                    } else {
                        setupLocationSlot = .location4
                        showLocationSetup = true
                    }
                },
                onLongPress: {
                    setupLocationSlot = .location4
                    showLocationSetup = true
                }
            )
        }
        .padding(10)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
}

#Preview {
    SpendingAndETAWidget(isVisible: true)
        .padding()
}
