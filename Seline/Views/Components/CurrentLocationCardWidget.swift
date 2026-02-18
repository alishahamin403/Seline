import SwiftUI

struct CurrentLocationCardWidget: View {
    typealias VisitSummary = (id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)

    @Environment(\.colorScheme) var colorScheme

    let currentLocationName: String
    let nearbyLocation: String?
    let nearbyLocationFolder: String?
    let nearbyLocationPlace: SavedPlace?
    let distanceToNearest: Double?
    let elapsedTimeString: String
    let todaysVisits: [VisitSummary]

    @Binding var selectedPlace: SavedPlace?
    @Binding var showAllLocationsSheet: Bool

    @StateObject private var locationsManager = LocationsManager.shared

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)
    }

    private var activeIndicatorColor: Color {
        Color(red: 0.2, green: 0.78, blue: 0.35)
    }

    private var cardHeadingFont: Font {
        FontManager.geist(size: 20, weight: .semibold)
    }

    private var currentLocationDisplay: String {
        nearbyLocation ?? currentLocationName
    }

    private var sortedVisits: [VisitSummary] {
        todaysVisits.sorted { lhs, rhs in
            let lhsActive = isVisitActive(lhs)
            let rhsActive = isVisitActive(rhs)
            if lhsActive != rhsActive { return lhsActive }
            return lhs.totalDurationMinutes > rhs.totalDurationMinutes
        }
    }

    private var activeVisit: VisitSummary? {
        sortedVisits.first(where: isVisitActive)
    }

    private var maxVisitMinutes: Int {
        max(sortedVisits.map(\.totalDurationMinutes).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let activeVisit {
                activeNowSection(activeVisit)
            }

            if !sortedVisits.isEmpty {
                todayVisitsSection
            }
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Location")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Button(action: {
                    HapticManager.shared.selection()
                    showAllLocationsSheet = true
                }) {
                    Text("All")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .allowsParentScrolling()
            }

            HStack(alignment: .firstTextBaseline) {
                Text(currentLocationDisplay)
                    .font(cardHeadingFont)
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                Spacer()

                Text("\(sortedVisits.count) places")
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
                    )
            }
        }
    }

    private func activeNowSection(_ visit: VisitSummary) -> some View {
        Button(action: {
            selectPlace(with: visit.id)
        }) {
            HStack(spacing: 8) {
                Image(systemName: locationSymbol(for: visit.displayName))
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(primaryTextColor)

                Text(visit.displayName)
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)

                Spacer()

                Text(elapsedTimeString.isEmpty ? durationLabel(for: visit.totalDurationMinutes) : elapsedTimeString)
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(activeIndicatorColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    private var todayVisitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(secondaryTextColor)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedVisits.prefix(12), id: \.id) { visit in
                        visitChip(visit)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            .allowsParentScrolling()
        }
    }

    private func visitChip(_ visit: VisitSummary) -> some View {
        let isCurrent = isVisitActive(visit)

        return Button(action: {
            selectPlace(with: visit.id)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isCurrent
                              ? activeIndicatorColor
                              : (colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.28)))
                        .frame(width: 6, height: 6)

                    Text(visit.displayName)
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                        .lineLimit(1)
                }

                Text(durationLabel(for: visit.totalDurationMinutes))
                    .font(FontManager.geist(size: 11, weight: .medium))
                    .foregroundColor(isCurrent ? activeIndicatorColor : secondaryTextColor)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12))
                        Capsule()
                            .fill(isCurrent
                                  ? activeIndicatorColor
                                  : (colorScheme == .dark ? Color.white.opacity(0.34) : Color.black.opacity(0.28)))
                            .frame(width: progressWidth(for: visit.totalDurationMinutes, in: geo.size.width))
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(width: 156, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    private func progressWidth(for minutes: Int, in totalWidth: CGFloat) -> CGFloat {
        CGFloat(minutes) / CGFloat(maxVisitMinutes) * totalWidth
    }

    private func isVisitActive(_ visit: VisitSummary) -> Bool {
        if visit.isActive { return true }
        if let nearby = nearbyLocation, !elapsedTimeString.isEmpty {
            return visit.displayName == nearby
        }
        return false
    }

    private func durationLabel(for minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }

    private func locationSymbol(for name: String) -> String {
        let lowercased = name.lowercased()
        if lowercased.contains("home") { return "house.fill" }
        if lowercased.contains("work") || lowercased.contains("office") { return "briefcase.fill" }
        if lowercased.contains("gym") || lowercased.contains("fitness") { return "dumbbell.fill" }
        if lowercased.contains("restaurant") || lowercased.contains("grill") || lowercased.contains("pizza") || lowercased.contains("hakka") {
            return "fork.knife"
        }
        if lowercased.contains("store") || lowercased.contains("shop") || lowercased.contains("mall") {
            return "bag.fill"
        }
        return "mappin.circle.fill"
    }

    private func selectPlace(with id: UUID) {
        if let place = locationsManager.savedPlaces.first(where: { $0.id == id }) {
            selectedPlace = place
            HapticManager.shared.light()
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CurrentLocationCardWidget(
            currentLocationName: "123 Main Street",
            nearbyLocation: "Home",
            nearbyLocationFolder: nil,
            nearbyLocationPlace: nil,
            distanceToNearest: nil,
            elapsedTimeString: "1h 57m",
            todaysVisits: [
                (id: UUID(), displayName: "Home", totalDurationMinutes: 973, isActive: true),
                (id: UUID(), displayName: "Chipotle Mexican Grill", totalDurationMinutes: 7, isActive: false),
                (id: UUID(), displayName: "LA Fitness", totalDurationMinutes: 53, isActive: false)
            ],
            selectedPlace: .constant(nil),
            showAllLocationsSheet: .constant(false)
        )
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
