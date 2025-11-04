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

    private var categoryBreakdown: [(category: String, amount: Double, percentage: Double)] {
        guard let stats = currentYearStats else { return [] }
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)

        var categoryTotals: [String: Double] = [:]

        // Get all receipts for current month from monthly summaries
        for monthlySummary in stats.monthlySummaries {
            let month = calendar.component(.month, from: monthlySummary.monthDate)
            if month == currentMonth {
                for receipt in monthlySummary.receipts {
                    let current = categoryTotals[receipt.category] ?? 0
                    categoryTotals[receipt.category] = current + receipt.amount
                }
            }
        }

        // Convert to sorted array with percentages
        let total = categoryTotals.values.reduce(0, +)
        return categoryTotals
            .map { (category: $0.key, amount: $0.value, percentage: total > 0 ? ($0.value / total) * 100 : 0) }
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { $0 }
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

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 8) {
                // Spending Card (60%)
                spendingCard(width: (geometry.size.width - 8) * 0.6)

                // Navigation Card (40%)
                navigationCard(width: (geometry.size.width - 8) * 0.4)
            }
        }
        .frame(height: 130)
        .onAppear {
            Task {
                do {
                    locationPreferences = try await supabaseManager.loadLocationPreferences()
                } catch {
                    print("Failed to load location preferences: \(error)")
                }
            }
        }
    }

    private func spendingCard(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)

                    Text("MONTHLY SPENDING")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()
            }

            // Main amount
            VStack(alignment: .leading, spacing: 4) {
                Text(CurrencyParser.formatAmount(monthlyTotal))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                // Trend indicator
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                    Text("12% from last month")
                        .font(.system(size: 12, weight: .regular))
                }
                .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))
            }

            // Category breakdown
            VStack(spacing: 6) {
                ForEach(categoryBreakdown.prefix(3), id: \.category) { item in
                    HStack(spacing: 6) {
                        Text(categoryIcon(item.category))
                            .font(.system(size: 12))

                        Text(item.category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)

                        Spacer()

                        Text(String(format: "%.0f%%", item.percentage))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(categoryColor(item.category).opacity(0.3))
                    .cornerRadius(6)
                }
            }

            Spacer()
        }
        .padding(12)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }

    private func navigationCard(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "location.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)

                Text("NAVIGATION")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // ETA Rows
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
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
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
