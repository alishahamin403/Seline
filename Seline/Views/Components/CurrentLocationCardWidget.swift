import SwiftUI

struct CurrentLocationCardWidget: View {
    typealias VisitSummary = (id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)

    @Environment(\.colorScheme) var colorScheme

    let currentLocationName: String
    let nearbyLocation: String?
    let nearbyLocationFolder: String?
    let nearbyLocationPlace: SavedPlace?
    let distanceToNearest: Double?
    let todaysVisits: [VisitSummary]
    var isVisible: Bool = true
    let onCurrentLocationTap: (() -> Void)? = nil

    @Binding var selectedPlace: SavedPlace?
    @Binding var showAllLocationsSheet: Bool

    @StateObject private var locationsManager = LocationsManager.shared
    @State private var aiDaySummary: String?
    @State private var isGeneratingDaySummary = false
    @State private var lastGeneratedSummaryKey: String?

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
            return durationLabel(for: activeVisit.totalDurationMinutes)
        }
        return "--"
    }

    private var featuredVisits: [VisitSummary] {
        Array(sortedVisits.prefix(12))
    }

    private var summaryPatternSignature: String {
        let visitFingerprint = sortedVisits.map { visit in
            "\(visit.id.uuidString):\(visit.displayName):\(visit.isActive)"
        }
        .joined(separator: "|")

        return [
            Calendar.current.startOfDay(for: Date()).formatted(date: .numeric, time: .omitted),
            currentLocationDisplay,
            visitFingerprint
        ]
        .joined(separator: "||")
    }

    private var summaryTaskToken: String {
        "\(summaryPatternSignature)|visible:\(isVisible)"
    }

    private var summaryCacheKey: String {
        "cache.location.daySummary.\(summaryPatternSignature)"
    }

    private var displayedDaySummary: String {
        let trimmedSummary = aiDaySummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSummary.isEmpty ? fallbackDaySummary : trimmedSummary
    }

    private var fallbackDaySummary: String {
        if let activeVisit {
            let supportingStops = sortedVisits
                .filter { $0.id != activeVisit.id }
                .prefix(2)
                .map(\.displayName)

            if supportingStops.isEmpty {
                return "The day has stayed centered around \(currentLocationDisplay), with \(currentTimeLabel) spent there so far."
            }

            return "The day has been anchored by \(currentLocationDisplay) for \(currentTimeLabel), with shorter stops at \(joinedPlaceList(Array(supportingStops)))."
        }

        guard let leadVisit = sortedVisits.first else {
            if distanceToNearest != nil {
                return "The day is still taking shape, and the nearest saved place is \(formattedDistanceToNearest) away."
            }
            return locationStatusLine
        }

        let supportingStops = Array(sortedVisits.dropFirst().prefix(2).map(\.displayName))
        if supportingStops.isEmpty {
            return "\(leadVisit.displayName) has been the main stop so far, taking up \(durationLabel(for: leadVisit.totalDurationMinutes))."
        }

        return "\(leadVisit.displayName) has led the day so far, with time also spent at \(joinedPlaceList(supportingStops))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("CURRENT LOCATION")
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .tracking(0.9)

                Spacer(minLength: 12)
            }

            currentLocationDisplayCard

            locationInsightsSection

            if !featuredVisits.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(featuredVisits, id: \.id) { visit in
                            featuredVisitCard(visit)
                        }
                    }
                }
                .padding(.horizontal, -18)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .homeGlassCardStyle(colorScheme: colorScheme, cornerRadius: 24)
        .task(id: summaryTaskToken) {
            guard isVisible else { return }
            await refreshDaySummaryIfNeeded()
        }
    }

    private func featuredVisitCard(_ visit: VisitSummary) -> some View {
        let isCurrent = isVisitActive(visit)

        return Button(action: {
            selectPlace(with: visit.id)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(visit.displayName)
                        .font(FontManager.geist(size: 15, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .lineLimit(2)
                        .layoutPriority(1)

                    Spacer(minLength: 6)

                    Text(durationLabel(for: visit.totalDurationMinutes))
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .lineLimit(1)
                }

                Text(featuredVisitDescription(for: visit, isCurrent: isCurrent))
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.26 : 0.2))

                        Capsule()
                            .fill(isCurrent ? homeAccentColor : Color.appTextPrimary(colorScheme))
                            .frame(width: progressWidth(for: visit.totalDurationMinutes, in: geo.size.width))
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minWidth: 220, maxWidth: 220, minHeight: 132, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        isCurrent
                            ? homeAccentColor.opacity(colorScheme == .dark ? 0.16 : 0.18)
                            : Color.homeGlassInnerTint(colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        isCurrent ? homeAccentColor.opacity(colorScheme == .dark ? 0.28 : 0.22) : Color.homeGlassInnerBorder(colorScheme),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func featuredVisitDescription(for visit: VisitSummary, isCurrent: Bool) -> String {
        if isCurrent {
            return "Live visit right now."
        }

        if visit.totalDurationMinutes == maxVisitMinutes {
            return "Longest stop in today's route."
        }

        if visit.totalDurationMinutes <= 15 {
            return "Quick stop in today's loop."
        }

        return "Part of today's saved places."
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
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(currentLocationDisplay)
                .font(FontManager.geist(size: 22, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(2)
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

    private var locationInsightsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayedDaySummary)
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            if isGeneratingDaySummary && (aiDaySummary?.isEmpty ?? true) {
                Text("Summarizing day so far...")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.72))
            }
        }
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
        let timeLabel = currentTimeLabel
        if activeVisit != nil, timeLabel != "--" {
            return "\(timeLabel) here now"
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
        if let nearbyId = nearbyLocationPlace?.id {
            return visit.id == nearbyId
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

    private func refreshDaySummaryIfNeeded() async {
        if lastGeneratedSummaryKey == summaryPatternSignature, aiDaySummary != nil {
            return
        }

        if let cachedSummary: String = CacheManager.shared.get(forKey: summaryCacheKey),
           !cachedSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await MainActor.run {
                aiDaySummary = cachedSummary
                lastGeneratedSummaryKey = summaryPatternSignature
                isGeneratingDaySummary = false
            }
            return
        }

        await MainActor.run {
            isGeneratingDaySummary = true
        }

        let fallbackSummary = fallbackDaySummary
        let prompt = buildDaySummaryPrompt()

        do {
            let response = try await GeminiService.shared.generateText(
                systemPrompt: "You are a concise assistant who summarizes movement patterns from a user's day. Write naturally, avoid generic filler, and output only the summary.",
                userPrompt: prompt,
                maxTokens: 90,
                temperature: 0.45,
                operationType: "location_day_summary"
            )

            let sanitizedSummary = sanitizeDaySummary(response)
            await MainActor.run {
                let finalSummary = sanitizedSummary.isEmpty ? fallbackSummary : sanitizedSummary
                aiDaySummary = finalSummary
                lastGeneratedSummaryKey = summaryPatternSignature
                isGeneratingDaySummary = false
                CacheManager.shared.set(finalSummary, forKey: summaryCacheKey, ttl: CacheManager.TTL.persistent)
            }
        } catch {
            await MainActor.run {
                aiDaySummary = fallbackSummary
                lastGeneratedSummaryKey = summaryPatternSignature
                isGeneratingDaySummary = false
                CacheManager.shared.set(fallbackSummary, forKey: summaryCacheKey, ttl: CacheManager.TTL.persistent)
            }
        }
    }

    private func buildDaySummaryPrompt() -> String {
        let visitsBlock: String
        if sortedVisits.isEmpty {
            visitsBlock = "No saved-place visits have been recorded yet today."
        } else {
            visitsBlock = sortedVisits
                .prefix(6)
                .enumerated()
                .map { index, visit in
                    let activeSuffix = isVisitActive(visit) ? " | active now" : ""
                    return "\(index + 1). \(visit.displayName) | duration: \(durationLabel(for: visit.totalDurationMinutes))\(activeSuffix)"
                }
                .joined(separator: "\n")
        }

        return """
        Write a 1-2 sentence summary of the day so far based on the user's saved-place visits.

        Requirements:
        - Be observant and concise.
        - Do not use first-person.
        - Do not say "you are currently at" or "you are at home."
        - Capture the rhythm or pattern of the day so far.
        - Mention the current location only if it helps the summary feel grounded.
        - Output only the summary text.

        Context:
        Current location label: \(currentLocationDisplay)
        Current status line: \(locationStatusLine)
        Active-stop duration: \(currentTimeLabel)
        Distance to nearest saved place: \(distanceToNearest != nil ? formattedDistanceToNearest : "n/a")
        Today's visits:
        \(visitsBlock)
        """
    }

    private func sanitizeDaySummary(_ summary: String) -> String {
        summary
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"(?i)^summary\s*[:#-]*\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "")
    }

    private func joinedPlaceList(_ places: [String]) -> String {
        switch places.count {
        case 0:
            return ""
        case 1:
            return places[0]
        case 2:
            return "\(places[0]) and \(places[1])"
        default:
            let head = places.dropLast().joined(separator: ", ")
            return "\(head), and \(places.last ?? "")"
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
            todaysVisits: [
                (id: UUID(), displayName: "Home", totalDurationMinutes: 973, isActive: true),
                (id: UUID(), displayName: "Chipotle Mexican Grill", totalDurationMinutes: 7, isActive: false),
                (id: UUID(), displayName: "LA Fitness", totalDurationMinutes: 53, isActive: false)
            ],
            isVisible: true,
            selectedPlace: .constant(nil),
            showAllLocationsSheet: .constant(false)
        )
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
