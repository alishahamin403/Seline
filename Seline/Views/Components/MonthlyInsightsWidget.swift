import SwiftUI

/// Horizontally scrollable spending insights widget for the home page
struct MonthlyInsightsWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var insightsService = SpendingInsightsService.shared
    @State private var insights: [SpendingInsightsService.SpendingInsight] = []
    @State private var isLoading = true

    // Receipt data injected from parent
    let currentMonthReceipts: [ReceiptStat]
    let previousMonthReceipts: [ReceiptStat]
    let allTimeReceipts: [ReceiptStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.yellow)

                Text("Insights")
                    .font(FontManager.geist(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                if !insights.isEmpty {
                    Text("\(insights.count)")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        )
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(height: 80)
            } else if insights.isEmpty {
                emptyState
            } else {
                // Horizontally scrollable insight cards
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(insights) { insight in
                            InsightCard(insight: insight)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
        .onAppear {
            generateInsights()
        }
        .onChange(of: currentMonthReceipts.count) { _ in
            generateInsights()
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                Text("Add more receipts for insights")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            Spacer()
        }
        .frame(height: 80)
    }

    private func generateInsights() {
        isLoading = true

        Task {
            let generated = insightsService.generateInsights(
                currentMonthReceipts: currentMonthReceipts,
                previousMonthReceipts: previousMonthReceipts,
                allTimeReceipts: allTimeReceipts
            )

            await MainActor.run {
                insights = generated
                isLoading = false
            }
        }
    }
}

// MARK: - Individual Insight Card

struct InsightCard: View {
    let insight: SpendingInsightsService.SpendingInsight
    @Environment(\.colorScheme) var colorScheme

    private var accentColor: Color {
        switch insight.accentColor {
        case .green: return .green
        case .red: return .red
        case .blue: return .blue
        case .orange: return .primary
        case .purple: return .purple
        case .gray: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title
            Text(insight.title)
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(2)

            // Subtitle
            Text(insight.subtitle)
                .font(FontManager.geist(size: 11, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Trend indicator at bottom if exists
            if let trend = insight.trend {
                HStack(spacing: 4) {
                    Image(systemName: trend == .up ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(trend == .up ? .red : .green)

                    Text(trend == .up ? "Up" : "Down")
                        .font(FontManager.geist(size: 9, weight: .medium))
                        .foregroundColor(trend == .up ? .red : .green)
                }
            }
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Simplified Version (Auto-loads data)

struct MonthlyInsightsWidgetAuto: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var insightsService = SpendingInsightsService.shared
    @State private var insights: [SpendingInsightsService.SpendingInsight] = []
    @State private var isLoading = true

    // Inject the notes manager to get receipts
    @StateObject private var notesManager = NotesManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.yellow)

                Text("Spending Insights")
                    .font(FontManager.geist(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                if !insights.isEmpty {
                    Text("\(insights.count)")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        )
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(height: 80)
            } else if insights.isEmpty {
                emptyState
            } else {
                // Horizontally scrollable insight cards
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(insights) { insight in
                            InsightCard(insight: insight)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
        .onAppear {
            loadAndGenerateInsights()
        }
    }

    private var emptyState: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                Text("Add receipts for insights")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            Spacer()
        }
        .frame(height: 80)
    }

    private func loadAndGenerateInsights() {
        isLoading = true

        Task {
            let calendar = Calendar.current
            let now = Date()
            let currentYear = calendar.component(.year, from: now)
            let currentMonth = calendar.component(.month, from: now)

            // Get receipt statistics from NotesManager (properly filtered from Receipts folder)
            let yearlyStats = notesManager.getReceiptStatistics()

            // Flatten all receipts
            var allReceipts: [ReceiptStat] = []
            for yearly in yearlyStats {
                for monthly in yearly.monthlySummaries {
                    allReceipts.append(contentsOf: monthly.receipts)
                }
            }

            // Current month receipts
            let currentMonthReceipts = allReceipts.filter { receipt in
                let components = calendar.dateComponents([.year, .month], from: receipt.date)
                return components.year == currentYear && components.month == currentMonth
            }

            // Previous month receipts
            let previousMonth = calendar.date(byAdding: .month, value: -1, to: now)!
            let prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
            let previousMonthReceipts = allReceipts.filter { receipt in
                let components = calendar.dateComponents([.year, .month], from: receipt.date)
                return components.year == prevComponents.year && components.month == prevComponents.month
            }

            // Last 6 months for streak detection
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now)!
            let allTimeReceipts = allReceipts.filter { $0.date >= sixMonthsAgo }

            let generated = insightsService.generateInsights(
                currentMonthReceipts: currentMonthReceipts,
                previousMonthReceipts: previousMonthReceipts,
                allTimeReceipts: allTimeReceipts
            )

            await MainActor.run {
                insights = generated
                isLoading = false
            }
        }
    }
}

#Preview {
    VStack {
        MonthlyInsightsWidgetAuto()
            .padding(.horizontal, 12)
        Spacer()
    }
    .background(Color.shadcnBackground(.dark))
}
