import SwiftUI
import Charts

struct CategoryBreakdownView: View {
    let categoryBreakdown: YearlyCategoryBreakdown
    @State private var isExpanded = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Collapsible header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spending by Category")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Breakdown of \(categoryBreakdown.year)")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.gray)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(16)
            }

            if isExpanded {
                Divider()
                    .opacity(0.3)

                VStack(spacing: 0) {
                    // Category list
                    ForEach(Array(categoryBreakdown.sortedCategories.enumerated()), id: \.element.category) { index, categoryStat in
                        CategoryRow(categoryStat: categoryStat)

                        if index < categoryBreakdown.sortedCategories.count - 1 {
                            Divider()
                                .opacity(0.2)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 12)

                Divider()
                    .opacity(0.3)

                // Pie chart (iOS 17.0+)
                if !categoryBreakdown.sortedCategories.isEmpty {
                    VStack(spacing: 12) {
                        if #available(iOS 17.0, *) {
                            Chart(categoryBreakdown.sortedCategories, id: \.category) { category in
                                SectorMark(
                                    angle: .value("Percentage", category.percentage)
                                )
                                .foregroundStyle(by: .value("Category", category.category))
                                .opacity(0.9)
                            }
                            .frame(height: 200)
                            .padding(.horizontal, 16)
                        } else {
                            // Fallback for older iOS versions - show simplified bar chart
                            VStack(spacing: 12) {
                                ForEach(categoryBreakdown.sortedCategories.prefix(5), id: \.category) { category in
                                    HStack(spacing: 8) {
                                        Text(category.category)
                                            .font(.system(size: 12, weight: .regular))
                                            .frame(width: 70, alignment: .leading)

                                        GeometryReader { geometry in
                                            ZStack(alignment: .leading) {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(Color.gray.opacity(0.2))

                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(colorForCategory(category.category))
                                                    .frame(width: geometry.size.width * (category.percentage / 100))
                                            }
                                        }
                                        .frame(height: 20)

                                        Text(category.formattedPercentage)
                                            .font(.system(size: 11, weight: .semibold))
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Legend
                        VStack(spacing: 8) {
                            ForEach(categoryBreakdown.sortedCategories, id: \.category) { category in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(colorForCategory(category.category))
                                        .frame(width: 8, height: 8)

                                    Text(category.category)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Text(category.formattedPercentage)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Food":
            return Color(red: 1.0, green: 0.59, blue: 0.35) // Orange
        case "Services":
            return Color(red: 0.5, green: 0.8, blue: 0.9) // Light blue
        case "Transportation":
            return Color(red: 0.4, green: 0.8, blue: 0.4) // Green
        case "Healthcare":
            return Color(red: 1.0, green: 0.4, blue: 0.4) // Red
        case "Entertainment":
            return Color(red: 0.8, green: 0.4, blue: 0.9) // Purple
        case "Shopping":
            return Color(red: 1.0, green: 0.8, blue: 0.3) // Yellow
        default:
            return Color.gray
        }
    }
}

// MARK: - Category Row Component

struct CategoryRow: View {
    let categoryStat: CategoryStatWithPercentage
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(categoryStat.category)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                ProgressView(value: categoryStat.percentage / 100)
                    .frame(height: 4)
                    .tint(colorForCategory(categoryStat.category))
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text(categoryStat.formattedAmount)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text(categoryStat.formattedPercentage)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
    }

    private func colorForCategory(_ category: String) -> Color {
        switch category {
        case "Food":
            return Color(red: 1.0, green: 0.59, blue: 0.35) // Orange
        case "Services":
            return Color(red: 0.5, green: 0.8, blue: 0.9) // Light blue
        case "Transportation":
            return Color(red: 0.4, green: 0.8, blue: 0.4) // Green
        case "Healthcare":
            return Color(red: 1.0, green: 0.4, blue: 0.4) // Red
        case "Entertainment":
            return Color(red: 0.8, green: 0.4, blue: 0.9) // Purple
        case "Shopping":
            return Color(red: 1.0, green: 0.8, blue: 0.3) // Yellow
        default:
            return Color.gray
        }
    }
}

#Preview {
    CategoryBreakdownView(
        categoryBreakdown: YearlyCategoryBreakdown(
            year: 2025,
            categories: [
                CategoryStat(category: "Food", total: 450.50, count: 15),
                CategoryStat(category: "Services", total: 320.00, count: 8),
                CategoryStat(category: "Transportation", total: 280.75, count: 10),
                CategoryStat(category: "Healthcare", total: 150.00, count: 3),
                CategoryStat(category: "Entertainment", total: 200.25, count: 5),
            ],
            yearlyTotal: 1400.50
        )
    )
}
