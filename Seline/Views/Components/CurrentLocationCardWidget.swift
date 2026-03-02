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
    let onCurrentLocationTap: (() -> Void)? = nil

    @Binding var selectedPlace: SavedPlace?
    @Binding var showAllLocationsSheet: Bool

    @StateObject private var locationsManager = LocationsManager.shared

    private var activeBadgeColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var currentLocationDisplay: String {
        nearbyLocation ?? cityOnlyLocationName
    }

    private var cityOnlyLocationName: String {
        let trimmed = currentLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Current Location" }

        switch trimmed {
        case "Finding location...", "Location not available", "Unknown Location", "Current Location":
            return trimmed
        default:
            if let city = trimmed.split(separator: ",").first {
                let cityString = city.trimmingCharacters(in: .whitespacesAndNewlines)
                return cityString.isEmpty ? trimmed : cityString
            }
            return trimmed
        }
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

    private var currentTimeLabel: String {
        if let activeVisit {
            return elapsedTimeString.isEmpty
                ? durationLabel(for: activeVisit.totalDurationMinutes)
                : elapsedTimeString
        }
        if !elapsedTimeString.isEmpty {
            return elapsedTimeString
        }
        return "--"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Location")
                        .font(FontManager.geist(size: 24, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                }

                Spacer(minLength: 0)

                if activeVisit != nil {
                    Text("Active")
                        .font(FontManager.geist(size: 10, weight: .semibold))
                        .foregroundColor(activeBadgeColor)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.appChip(colorScheme))
                        )
                }
            }

            currentLocationDisplayCard

            HStack(spacing: 10) {
                locationMetricTile(title: "Visits", value: "\(sortedVisits.count)")
                locationMetricTile(title: activeVisit != nil ? "Time here" : "Nearest", value: activeVisit != nil ? currentTimeLabel : formattedDistanceToNearest)
                locationMetricTile(title: "Folder", value: nearbyLocationFolder ?? "Saved")
            }

            if !sortedVisits.isEmpty {
                todayVisitsSection
            }
        }
        .padding(16)
        .homeGlassCardStyle(colorScheme: colorScheme, cornerRadius: 24)
    }

    private var todayVisitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(sortedVisits.prefix(12), id: \.id) { visit in
                        visitChip(visit)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
    }

    private func visitChip(_ visit: VisitSummary) -> some View {
        let isCurrent = isVisitActive(visit)

        return Button(action: {
            selectPlace(with: visit.id)
        }) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isCurrent ? homeAccentColor : Color.appBorder(colorScheme))
                        .frame(width: 7, height: 7)

                    Text(visit.displayName)
                        .font(FontManager.geist(size: 13, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .lineLimit(1)
                }

                Text(durationLabel(for: visit.totalDurationMinutes))
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(isCurrent ? Color.appTextPrimary(colorScheme) : Color.appTextSecondary(colorScheme))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 1 : 0.75))
                        Capsule()
                            .fill(isCurrent ? homeAccentColor : Color.appTextSecondary(colorScheme).opacity(0.4))
                            .frame(width: progressWidth(for: visit.totalDurationMinutes, in: geo.size.width))
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(width: 170, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        isCurrent
                            ? homeAccentColor.opacity(colorScheme == .dark ? 0.16 : 0.2)
                            : Color.homeGlassInnerTint(colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isCurrent ? homeAccentColor.opacity(colorScheme == .dark ? 0.28 : 0.22) : Color.homeGlassInnerBorder(colorScheme),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private var currentLocationDisplayCard: some View {
        let content = VStack(alignment: .leading, spacing: 6) {
            Text(currentLocationDisplay)
                .font(FontManager.geist(size: 22, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(2)

            Text(locationStatusLine)
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if canOpenCurrentLocationDetails {
            Button(action: handleCurrentLocationTap) {
                content
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            content
        }
    }

    private func locationMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .lineLimit(1)

            Text(value)
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .homeGlassInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
    }

    private var homeAccentColor: Color {
        Color.homeGlassAccent
    }

    private var locationHeroCardBackground: some View {
        HomeGlassCardBackground(
            colorScheme: colorScheme,
            cornerRadius: 24,
            highlightStrength: 1
        )
    }

    private var canOpenCurrentLocationDetails: Bool {
        onCurrentLocationTap != nil || activeVisit != nil
    }

    private var formattedDistanceToNearest: String {
        guard let distanceToNearest else { return "--" }
        if distanceToNearest >= 1000 {
            return String(format: "%.1f km", distanceToNearest / 1000)
        }
        return "\(Int(distanceToNearest.rounded())) m"
    }

    private var locationStatusLine: String {
        if activeVisit != nil, currentTimeLabel != "--" {
            return "\(currentTimeLabel) here now"
        }

        if distanceToNearest != nil {
            return "\(formattedDistanceToNearest) from nearest saved place"
        }

        return currentLocationName
    }

    private func progressWidth(for minutes: Int, in totalWidth: CGFloat) -> CGFloat {
        guard totalWidth > 0 else { return 0 }
        let ratio = min(max(CGFloat(minutes) / CGFloat(maxVisitMinutes), 0), 1)
        return ratio * totalWidth
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

    private func selectPlace(with id: UUID) {
        if let place = locationsManager.savedPlaces.first(where: { $0.id == id }) {
            selectedPlace = place
            HapticManager.shared.light()
        }
    }

    private func handleCurrentLocationTap() {
        if let onCurrentLocationTap {
            onCurrentLocationTap()
            HapticManager.shared.light()
            return
        }

        if let activeVisit {
            selectPlace(with: activeVisit.id)
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
