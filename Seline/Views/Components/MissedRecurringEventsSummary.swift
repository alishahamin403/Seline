import SwiftUI

struct MissedRecurringEventsSummary: View {
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var openAIService = DeepSeekService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var aiSummary: String = ""
    @State private var isLoading: Bool = false
    @State private var isExpanded: Bool = true
    @State private var lastWeekSummary: WeeklyMissedEventSummary?

    var body: some View {
        if let summary = lastWeekSummary, !summary.missedEvents.isEmpty {
            ShadcnCard {
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

                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(
                                    colorScheme == .dark ?
                                        Color.white :
                                        Color.black
                                )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Weekly Insights")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            Text("Last week's patterns")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }

                        Spacer()

                        // Refresh button
                        Button(action: {
                            Task {
                                await generateSummary()
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
                        if isLoading {
                            HStack {
                                Spacer()
                                ShadcnSpinner()
                                Spacer()
                            }
                            .padding(.vertical, 20)
                        } else if !aiSummary.isEmpty {
                            Text(aiSummary)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
                                .lineSpacing(4)
                        } else {
                            Text("Tap refresh to generate insights")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                .italic()
                        }

                        // Stats summary
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(summary.totalMissedCount)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(Color.red.opacity(0.8))

                                Text("Missed")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                            }

                            Divider()
                                .frame(height: 40)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(summary.missedEvents.count)")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                            Color.white :
                                            Color.black
                                    )

                                Text("Events")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                            }
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                }
            }
            .onAppear {
                Task {
                    await loadData()
                }
            }
        }
    }

    private func loadData() async {
        let calendar = Calendar.current
        let today = Date()
        guard let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: today)) else {
            return
        }

        lastWeekSummary = taskManager.getMissedRecurringEventsForWeek(lastWeekStart)

        // Auto-generate summary on first load
        if aiSummary.isEmpty, let summary = lastWeekSummary, !summary.missedEvents.isEmpty {
            await generateSummary()
        }
    }

    private func generateSummary() async {
        guard let summary = lastWeekSummary, !summary.missedEvents.isEmpty else {
            return
        }

        isLoading = true

        do {
            let generatedSummary = try await openAIService.generateRecurringEventsSummary(missedEvents: summary.missedEvents)
            await MainActor.run {
                aiSummary = generatedSummary
                isLoading = false
            }
        } catch {
            await MainActor.run {
                aiSummary = "You missed \(summary.totalMissedCount) recurring event\(summary.totalMissedCount == 1 ? "" : "s") last week. Try setting reminders to stay on track!"
                isLoading = false
            }
            print("❌ Failed to generate AI summary: \(error)")
        }
    }
}
