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
        switch category {
        case "Food": return "🍔"
        case "Services": return "🔧"
        case "Transportation": return "🚗"
        case "Healthcare": return "🏥"
        case "Entertainment": return "🎬"
        case "Shopping": return "🛍️"
        default: return "📦"
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Food": return Color(red: 0.831, green: 0.647, blue: 0.455)
        case "Services": return Color(red: 0.639, green: 0.608, blue: 0.553)
        case "Transportation": return Color(red: 0.627, green: 0.533, blue: 0.408)
        case "Healthcare": return Color(red: 0.831, green: 0.710, blue: 0.627)
        case "Entertainment": return Color(red: 0.722, green: 0.627, blue: 0.537)
        case "Shopping": return Color(red: 0.792, green: 0.722, blue: 0.659)
        default: return Color.gray
        }
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
            GeometryReader { geometry in
                HStack(spacing: 12) {
                    // Spending Card (50%)
                    spendingCard(width: (geometry.size.width - 36) * 0.5)

                    // Navigation Card with 2x2 ETA grid (50%)
                    navigationCard2x2(width: (geometry.size.width - 36) * 0.5)
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(height: 130)
        .onAppear {
            locationService.requestLocationPermission()
            updateCategoryBreakdown()
            Task {
                do {
                    locationPreferences = try await supabaseManager.loadLocationPreferences()
                    updateETAs()
                } catch {
                    print("Failed to load location preferences: \(error)")
                }
            }
        }
        .onChange(of: locationService.currentLocation) { location in
            if let location = location {
                updateETAs()
            }
        }
        .onChange(of: notesManager.notes.count) { _ in
            updateCategoryBreakdown()
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
            ReceiptStatsView()
        }
    }

    private func spendingCard(width: CGFloat) -> some View {
        Button(action: { showReceiptStats = true }) {
            VStack(alignment: .leading, spacing: 6) {
                // Main amount
                VStack(alignment: .leading, spacing: 2) {
                    Text(CurrencyParser.formatAmount(monthlyTotal))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    // Trend indicator
                    HStack(spacing: 4) {
                        Image(systemName: monthOverMonthPercentage.isIncrease ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text(String(format: "%.0f%% %@ last month", monthOverMonthPercentage.percentage, monthOverMonthPercentage.isIncrease ? "more than" : "less than"))
                            .font(.system(size: 11, weight: .regular))
                    }
                    .foregroundColor(monthOverMonthPercentage.isIncrease ? Color(red: 0.4, green: 0.9, blue: 0.4) : Color(red: 0.9, green: 0.4, blue: 0.4))
                }

                // Top category only
                if let topCategory = categoryBreakdown.first {
                    HStack(spacing: 6) {
                        Text(categoryIcon(topCategory.category))
                            .font(.system(size: 12))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(topCategory.category)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            Text(CurrencyParser.formatAmount(topCategory.amount))
                                .font(.system(size: 9, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                        }

                        Spacer()

                        Text(String(format: "%.0f%%", topCategory.percentage))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .cornerRadius(6)
                }

                Spacer()
            }
            .padding(10)
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func navigationCard2x2(width: CGFloat) -> some View {
        VStack(spacing: 8) {
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
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }

    private func navigationETACircle(icon: String, eta: String?, isLocationSet: Bool, onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

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
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture {
            HapticManager.shared.selection()
            onLongPress()
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
