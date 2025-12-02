import SwiftUI

struct MonthlySummaryCard: View {
    let selectedMonth: Date
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var openAIService = OpenAIService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var aiInsights: String = ""
    @State private var isLoading: Bool = false
    @State private var isExpanded: Bool = true
    @State private var monthlySummary: MonthlySummary?

    var body: some View {
        if let summary = monthlySummary, summary.hasSignificantActivity {
            VStack {
                // Header
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                        HapticManager.shared.selection()
                    }
                }) {
                    HStack(spacing: 12) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(
                                    colorScheme == .dark ?
                                        Color.white.opacity(0.2) :
                                        Color.black.opacity(0.1)
                                )
                                .frame(width: 40, height: 40)

                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(
                                    colorScheme == .dark ?
                                        Color.white :
                                        Color.black
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Monthly Summary")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            Text(monthFormatter.string(from: selectedMonth))
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }

                        Spacer()

                        // Refresh button
                        Button(action: {
                            Task {
                                await generateInsights()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isLoading)

                        // Chevron
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(16)
                }
                .buttonStyle(PlainButtonStyle())

                if isExpanded {
                    Divider()
                        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))

                    // Content
                    VStack(alignment: .leading, spacing: 16) {
                        // AI Insights
                        if isLoading {
                            HStack {
                                Spacer()
                                ShadcnSpinner()
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else if !aiInsights.isEmpty {
                            Text(aiInsights)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
                                .lineSpacing(4)
                        }

                        // Stats Grid
                        VStack(spacing: 12) {
                            // Main completion number
                            VStack(spacing: 4) {
                                Text("\(summary.completedEvents)")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                            Color.white :
                                            Color.black
                                    )

                                Text("Events Completed")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)

                            // Breakdown
                            if summary.recurringCompletedCount > 0 || summary.oneTimeCompletedCount > 0 {
                                HStack(spacing: 12) {
                                    // Recurring events
                                    if summary.recurringCompletedCount > 0 {
                                        StatBadge(
                                            value: summary.recurringCompletedCount,
                                            label: "Recurring",
                                            colorScheme: colorScheme
                                        )
                                    }

                                    // One-time events
                                    if summary.oneTimeCompletedCount > 0 {
                                        StatBadge(
                                            value: summary.oneTimeCompletedCount,
                                            label: "One-time",
                                            colorScheme: colorScheme
                                        )
                                    }

                                    Spacer()
                                }
                            }

                            // Top Events
                            if !summary.topCompletedEvents.isEmpty {
                                Divider()
                                    .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Top Completed Events")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))

                                        Spacer()
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(summary.topCompletedEvents.prefix(3).enumerated()), id: \.offset) { index, eventName in
                                            HStack(spacing: 8) {
                                                Text("\(index + 1).")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                                                    .frame(width: 20, alignment: .leading)

                                                Text(eventName)
                                                    .font(.system(size: 13, weight: .regular))
                                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            .onAppear {
                Task {
                    await loadData()
                }
            }
            .onChange(of: selectedMonth) { _ in
                Task {
                    await loadData()
                }
            }
        }
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    private func loadData() async {
        monthlySummary = taskManager.getMonthlySummary(selectedMonth)

        // Auto-generate insights on first load
        if aiInsights.isEmpty, let summary = monthlySummary, summary.hasSignificantActivity {
            await generateInsights()
        }
    }

    private func generateInsights() async {
        guard let summary = monthlySummary, summary.hasSignificantActivity else {
            return
        }

        isLoading = true

        do {
            let generatedInsights = try await openAIService.generateMonthlySummary(summary: summary)
            await MainActor.run {
                aiInsights = generatedInsights
                isLoading = false
            }
        } catch {
            await MainActor.run {
                // Provide a fallback insight based on the data
                if summary.completionRate >= 0.8 {
                    aiInsights = "Great work this month! You completed \(summary.completionPercentage)% of your events. Keep up the excellent momentum!"
                } else if summary.completionRate >= 0.5 {
                    aiInsights = "You completed \(summary.completedEvents) out of \(summary.totalEvents) events this month. Consider focusing on your most important recurring tasks to improve consistency."
                } else {
                    aiInsights = "You had \(summary.totalEvents) events this month with \(summary.completedEvents) completed. Try breaking down larger tasks and setting realistic daily goals."
                }
                isLoading = false
            }
            print("❌ Failed to generate AI insights: \(error)")
        }
    }
}

// Helper view for stat badges
struct StatBadge: View {
    let value: Int
    let label: String
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
}

#Preview {
    MonthlySummaryCard(selectedMonth: Date())
}
