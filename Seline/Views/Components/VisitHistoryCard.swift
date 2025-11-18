import SwiftUI

struct VisitHistoryCard: View {
    let place: SavedPlace
    @StateObject private var analytics = LocationVisitAnalytics.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var visitHistory: [VisitHistoryItem] = []
    @State private var isLoading = false
    @State private var isExpanded = false

    let maxVisitsToShow = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20))
                        .foregroundColor(
                            colorScheme == .dark ?
                                Color.white :
                                Color.black
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Visit History")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        if visitHistory.isEmpty {
                            if isLoading {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading...")
                                        .font(.system(size: 14))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                }
                            } else {
                                Text("No visits yet")
                                    .font(.system(size: 14))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            }
                        } else {
                            Text("\(visitHistory.count) visit\(visitHistory.count == 1 ? "" : "s")")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Visit List
            if isExpanded && !visitHistory.isEmpty {
                VStack(spacing: 8) {
                    ForEach(visitHistory.prefix(maxVisitsToShow), id: \.visit.id) { item in
                        VisitHistoryRow(
                            visit: item.visit,
                            colorScheme: colorScheme
                        )

                        if item.visit.id != visitHistory.prefix(maxVisitsToShow).last?.visit.id {
                            Divider()
                                .padding(.vertical, 4)
                        }
                    }

                    if visitHistory.count > maxVisitsToShow {
                        Text("Showing latest \(maxVisitsToShow) of \(visitHistory.count) visits")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
            }
        }
        .onAppear {
            loadVisitHistory()
        }
    }

    private func loadVisitHistory() {
        isLoading = true
        Task {
            visitHistory = await analytics.fetchVisitHistory(for: place.id)
            isLoading = false
        }
    }
}

// MARK: - Visit History Row

struct VisitHistoryRow: View {
    let visit: LocationVisitRecord
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Date and Duration
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.entryTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    HStack(spacing: 8) {
                        Text(visit.dayOfWeek)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Text("•")
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))

                        Text(visit.timeOfDay)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                }

                Spacer()

                if let duration = visit.durationMinutes {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDuration(duration))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("Duration")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Active")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                        Text("In Progress")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                }
            }

            // Time Range
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                Text(formatTimeRange(entry: visit.entryTime, exit: visit.exitTime))
                    .font(.system(size: 12))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                Spacer()
            }
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(remainingMinutes)m"
            }
        }
    }

    private func formatTimeRange(entry: Date, exit: Date?) -> String {
        let entryFormatter = DateFormatter()
        entryFormatter.timeStyle = .short

        let entryStr = entryFormatter.string(from: entry)

        if let exit = exit {
            let exitStr = entryFormatter.string(from: exit)
            return "\(entryStr) - \(exitStr)"
        } else {
            return "Started at \(entryStr)"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        VisitHistoryCard(
            place: SavedPlace(
                googlePlaceId: "test1",
                name: "Test Location",
                address: "123 Main St",
                latitude: 37.7749,
                longitude: -122.4194
            )
        )
        .padding()
    }
    .background(Color.black)
}
