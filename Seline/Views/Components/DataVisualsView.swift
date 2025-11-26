import SwiftUI

/// Progress bar visualization for completion percentage
struct ProgressBarView: View {
    let completed: Int
    let total: Int
    let backgroundColor: Color
    let fillColor: Color
    var height: CGFloat = 6

    var percentage: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(backgroundColor.opacity(0.3))

                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(fillColor)
                        .frame(width: geometry.size.width * percentage)
                }
            }
            .frame(height: height)

            // Percentage text
            HStack {
                Text("\(completed)/\(total)")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(Int(percentage * 100))%")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(fillColor)
        }
    }
}

/// Sparkline chart for trends
struct SparklineView: View {
    let dataPoints: [Double]
    let lineColor: Color
    let backgroundColor: Color
    var height: CGFloat = 30

    var minValue: Double {
        dataPoints.min() ?? 0
    }

    var maxValue: Double {
        dataPoints.max() ?? 1
    }

    var normalizedPoints: [Double] {
        let range = maxValue - minValue
        return range == 0
            ? dataPoints.map { _ in 0.5 }
            : dataPoints.map { ($0 - minValue) / range }
    }

    var body: some View {
        Canvas { context in
            guard !dataPoints.isEmpty else { return }

            let width = CGFloat(dataPoints.count - 1)
            let xStep = 1 / (width > 0 ? width : 1)

            // Draw line
            var path = Path()
            for (index, normalizedPoint) in normalizedPoints.enumerated() {
                let x = CGFloat(index) * xStep * 100
                let y = (1 - normalizedPoint) * height

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(lineColor), lineWidth: 2)

            // Draw points
            for (index, normalizedPoint) in normalizedPoints.enumerated() {
                let x = CGFloat(index) * xStep * 100
                let y = (1 - normalizedPoint) * height

                var pointPath = Path()
                pointPath.addEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                context.fill(pointPath, with: .color(lineColor))
            }
        }
        .frame(height: height)
    }
}

/// Stat box for displaying metrics
struct StatBoxView: View {
    let title: String
    let value: String
    let emoji: String?
    let trendIndicator: String?
    let backgroundColor: Color
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let emoji = emoji {
                    Text(emoji)
                        .font(.system(size: 16))
                }

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                Spacer()
            }

            HStack(alignment: .bottom, spacing: 6) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                if let trend = trendIndicator {
                    Text(trend)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(trend.contains("📈") ? .green : trend.contains("📉") ? .red : .orange)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(backgroundColor.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(backgroundColor.opacity(0.2), lineWidth: 0.5)
        )
    }
}

/// Category breakdown view (like expense breakdown)
struct CategoryBreakdownView: View {
    struct Category {
        let name: String
        let amount: Double
        let emoji: String
        let color: Color
    }

    let categories: [Category]
    @Environment(\.colorScheme) var colorScheme

    var total: Double {
        categories.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Horizontal bar chart
            ForEach(categories, id: \.name) { category in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(category.emoji)
                            .font(.system(size: 12))
                        Text(category.name)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        let percentage = (category.amount / total) * 100
                        Text(String(format: "%.0f%%", percentage))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(category.color)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))

                            let percentage = (category.amount / total)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(category.color.opacity(0.7))
                                .frame(width: geometry.size.width * percentage)
                        }
                    }
                    .frame(height: 6)
                }
            }

            // Total
            Divider()
                .padding(.vertical, 4)

            HStack {
                Text("Total")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(String(format: "$%.2f", total))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.blue)
            }
        }
        .padding(10)
        .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.gray.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Previews

#Preview("Progress Bar") {
    ProgressBarView(completed: 8, total: 12, backgroundColor: .gray, fillColor: .green)
        .padding()
}

#Preview("Sparkline") {
    SparklineView(dataPoints: [1, 3, 2, 5, 4, 7, 6, 8], lineColor: .blue, backgroundColor: .gray)
        .padding()
}

#Preview("Stat Box") {
    VStack(spacing: 12) {
        StatBoxView(
            title: "Tasks Completed",
            value: "8/12",
            emoji: "✅",
            trendIndicator: "📈 +2",
            backgroundColor: .green
        )
        StatBoxView(
            title: "This Month",
            value: "$287",
            emoji: "💰",
            trendIndicator: "📉 -5%",
            backgroundColor: .blue
        )
    }
    .padding()
}

#Preview("Category Breakdown") {
    CategoryBreakdownView(
        categories: [
            .init(name: "Shopping", amount: 92, emoji: "🛒", color: .blue),
            .init(name: "Dining", amount: 105, emoji: "☕", color: .orange),
            .init(name: "Transport", amount: 90, emoji: "🚗", color: .green)
        ]
    )
    .padding()
}
