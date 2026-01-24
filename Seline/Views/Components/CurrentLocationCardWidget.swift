import SwiftUI

struct CurrentLocationCardWidget: View {
    @Environment(\.colorScheme) var colorScheme

    let currentLocationName: String
    let nearbyLocation: String?
    let nearbyLocationFolder: String?
    let nearbyLocationPlace: SavedPlace?
    let distanceToNearest: Double?
    let elapsedTimeString: String
    let todaysVisits: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)]

    @Binding var selectedPlace: SavedPlace?
    @Binding var showAllLocationsSheet: Bool
    
    @StateObject private var locationsManager = LocationsManager.shared

    // MARK: - Colors
    
    private var cardBackground: Color {
        Color.shadcnTileBackground(colorScheme)
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)
    }
    
    private var tertiaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4)
    }
    
    private var activeIndicatorColor: Color {
        Color(red: 0.2, green: 0.78, blue: 0.35)
    }
    
    private var progressBarBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }
    
    // MARK: - Computed Properties
    
    private var currentLocationDisplay: String {
        nearbyLocation ?? currentLocationName
    }
    
    private var totalTodayMinutes: Int {
        todaysVisits.reduce(0) { $0 + $1.totalDurationMinutes }
    }
    
    private var currentTimeMinutes: Int {
        // Parse elapsed time string to minutes
        let components = elapsedTimeString.lowercased()
        var totalMinutes = 0
        
        // Handle "Xh Ym" format
        if let hourRange = components.range(of: #"(\d+)h"#, options: .regularExpression) {
            let hourStr = String(components[hourRange]).replacingOccurrences(of: "h", with: "")
            totalMinutes += (Int(hourStr) ?? 0) * 60
        }
        if let minRange = components.range(of: #"(\d+)m"#, options: .regularExpression) {
            let minStr = String(components[minRange]).replacingOccurrences(of: "m", with: "")
            totalMinutes += Int(minStr) ?? 0
        }
        
        return max(totalMinutes, 1)
    }
    
    @State private var weeklyStats: (mostVisited: String, totalPlaces: Int, totalMinutes: Int) = ("Home", 0, 0)
    @State private var weeklyPlaces: [SavedPlace] = []
    @State private var showWeeklyPlacesSheet = false
    
    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Today's Activity Section - always visible
            if !todaysVisits.isEmpty {
                todaysActivitySection
            }

            // Weekly Insights Section
            weeklyInsightsSection
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
        .task {
            await loadWeeklyStats()
        }
        .sheet(isPresented: $showWeeklyPlacesSheet) {
            WeeklyPlacesSheet(places: weeklyPlaces, selectedPlace: $selectedPlace)
        }
    }
    
    private func loadWeeklyStats() async {
        // Calculate the start of the week (Monday)
        let calendar = Calendar.current
        let today = Date()
        
        // Get the current weekday (1 = Sunday, 2 = Monday, ..., 7 = Saturday)
        let currentWeekday = calendar.component(.weekday, from: today)
        // Calculate days since Monday (Monday = 2, so days back = (weekday - 2 + 7) % 7)
        let daysFromMonday = (currentWeekday - 2 + 7) % 7
        
        guard let mondayOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: today)) else {
            return
        }
        
        // Fetch real data asynchronously
        let weeklyVisits = await locationsManager.getWeeklyVisitsSummary(from: mondayOfWeek)
        
        await MainActor.run {
            if weeklyVisits.isEmpty {
                // Fallback to today's data if no weekly data yet
                let placeCount = Set(todaysVisits.map { $0.displayName }).count
                let mostVisited = todaysVisits.max(by: { $0.totalDurationMinutes < $1.totalDurationMinutes })?.displayName ?? "Home"
                self.weeklyStats = (mostVisited, max(placeCount, 1), totalTodayMinutes)
                
                // Populate weeklyPlaces with today's places for fallback compatibility
                let todayIds = todaysVisits.map { $0.id }
                self.weeklyPlaces = locationsManager.savedPlaces.filter { todayIds.contains($0.id) }
            } else {
                let totalWeeklyMinutes = weeklyVisits.reduce(0) { $0 + $1.totalMinutes }
                let uniquePlaces = Set(weeklyVisits.map { $0.placeName }).count
                let mostVisited = weeklyVisits.max(by: { $0.totalMinutes < $1.totalMinutes })?.placeName ?? "Home"
                self.weeklyStats = (mostVisited, uniquePlaces, totalWeeklyMinutes)
                
                // Populate weeklyPlaces from actual weekly data
                let weeklyIds = weeklyVisits.map { $0.placeId }
                self.weeklyPlaces = locationsManager.savedPlaces.filter { weeklyIds.contains($0.id) }
            }
        }
    }
    
    
    // MARK: - Today's Activity Section

    private var todaysActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section Header
            HStack {
                Text("Today's Activity")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                // Total time pill
                Text(formatDuration(totalTodayMinutes))
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                    )
            }

            // Activity Bars - sort to show active location first
            VStack(spacing: 6) {
                ForEach(Array(sortedVisits.prefix(5).enumerated()), id: \.element.id) { index, visit in
                    activityRow(visit: visit, index: index)
                }
            }
        }
    }

    // Check if a visit is active (either via isActive flag OR via nearbyLocation match with elapsed time)
    private func isVisitActive(_ visit: (id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)) -> Bool {
        // Primary check: isActive flag from GeofenceManager
        if visit.isActive { return true }
        // Fallback: if nearbyLocation matches this visit and we have elapsed time, it's active
        if let nearby = nearbyLocation, !elapsedTimeString.isEmpty, visit.displayName == nearby {
            return true
        }
        return false
    }

    // Sort visits with active one first
    private var sortedVisits: [(id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool)] {
        todaysVisits.sorted { visit1, visit2 in
            let active1 = isVisitActive(visit1)
            let active2 = isVisitActive(visit2)
            if active1 && !active2 { return true }
            if !active1 && active2 { return false }
            return visit1.totalDurationMinutes > visit2.totalDurationMinutes
        }
    }

    private func activityRow(visit: (id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool), index: Int) -> some View {
        // Use the helper function to determine if this is the current active location
        let isCurrentLocation = isVisitActive(visit)
        // Neutral bar color for all locations (dark gray in light mode, light gray in dark mode)
        let neutralBarColor = colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.25)

        return HStack(spacing: 10) {
            // Name - highlighted if current location
            Text(visit.displayName)
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(isCurrentLocation ? activeIndicatorColor : secondaryTextColor)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            // Progress Bar - green only for active session, gray for everything else
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressBarBackground)

                    if isCurrentLocation {
                        // For active location: show previous time in gray, current session in green
                        let previousMinutes = max(0, visit.totalDurationMinutes - currentTimeMinutes)
                        let previousWidth = barWidth(for: previousMinutes, in: geo.size.width)
                        let currentWidth = barWidth(for: currentTimeMinutes, in: geo.size.width)

                        // Previous accumulated time (gray)
                        if previousMinutes > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(neutralBarColor)
                                .frame(width: previousWidth)
                        }

                        // Current session time (green - active)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(activeIndicatorColor)
                            .frame(width: currentWidth)
                            .offset(x: previousWidth)
                    } else {
                        // Non-active locations: gray bar
                        RoundedRectangle(cornerRadius: 3)
                            .fill(neutralBarColor)
                            .frame(width: barWidth(for: visit.totalDurationMinutes, in: geo.size.width))
                    }
                }
            }
            .frame(height: 8)

            // Duration - show total and current session for active location
            if isCurrentLocation && currentTimeMinutes > 0 {
                // Show current session time (green) and total time
                VStack(alignment: .trailing, spacing: 1) {
                    Text(elapsedTimeString)
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(activeIndicatorColor)
                    if visit.totalDurationMinutes > currentTimeMinutes {
                        Text(formatDuration(visit.totalDurationMinutes))
                            .font(FontManager.geist(size: 9, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                .frame(width: 55, alignment: .trailing)
            } else {
                Text(formatDuration(visit.totalDurationMinutes))
                    .font(FontManager.geist(size: 11, weight: .medium))
                    .foregroundColor(isCurrentLocation ? activeIndicatorColor : secondaryTextColor)
                    .frame(width: 55, alignment: .trailing)
            }
        }
        .padding(.vertical, isCurrentLocation ? 6 : 0)
        .background(
            GeometryReader { geo in
                if isCurrentLocation {
                    Rectangle()
                        .fill(activeIndicatorColor.opacity(0.1))
                        .frame(width: geo.size.width + 32) // Add 16px on each side
                        .offset(x: -16) // Shift left to align with widget edge
                }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let place = locationsManager.savedPlaces.first(where: { $0.id == visit.id }) {
                selectedPlace = place
                HapticManager.shared.light()
            }
        }
    }
    
    private func barWidth(for minutes: Int, in totalWidth: CGFloat) -> CGFloat {
        guard totalTodayMinutes > 0 else { return 0 }
        let percentage = CGFloat(minutes) / CGFloat(totalTodayMinutes)
        return max(8, totalWidth * percentage)
    }
    
    // MARK: - Weekly Insights Section
    
    private var weeklyInsightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section Header
            Text("This Week")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(secondaryTextColor)
                .textCase(.uppercase)
                .tracking(0.5)
            
            // Stats Row
            HStack(spacing: 12) {
                // Most Time
                insightCard(
                    title: "Most time",
                    value: weeklyStats.mostVisited
                )
                .onTapGesture {
                    // Find place with matching name and select it
                    // Note: This matches by name which isn't perfect but works for this summary view
                    if let place = locationsManager.savedPlaces.first(where: { $0.displayName == weeklyStats.mostVisited }) {
                        selectedPlace = place
                        HapticManager.shared.light()
                    }
                }
                
                // Places Visited
                insightCard(
                    title: "Places",
                    value: "\(weeklyStats.totalPlaces)"
                )
                .onTapGesture {
                    showWeeklyPlacesSheet = true
                    HapticManager.shared.light()
                }
                
                // Total Time
                insightCard(
                    title: "Tracked",
                    value: formatDuration(weeklyStats.totalMinutes)
                )
            }
        }
    }
    
    private func insightCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(FontManager.geist(size: 10, weight: .medium))
                .foregroundColor(tertiaryTextColor)
            
            Text(value)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        )
    }
    
    // MARK: - Helper Functions
    
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
    
    private func colorForIndex(_ index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.2, green: 0.78, blue: 0.35),  // Green
            Color(red: 0.35, green: 0.55, blue: 0.95), // Blue
            Color(red: 0.95, green: 0.55, blue: 0.25), // Orange
            Color(red: 0.85, green: 0.35, blue: 0.55), // Pink
            Color(red: 0.65, green: 0.45, blue: 0.95), // Purple
        ]
        return colors[index % colors.count]
    }
    
    private func iconForPlace(_ name: String) -> String {
        let lowercased = name.lowercased()
        if lowercased.contains("home") { return "house.fill" }
        if lowercased.contains("work") || lowercased.contains("office") { return "briefcase.fill" }
        if lowercased.contains("gym") || lowercased.contains("fitness") { return "dumbbell.fill" }
        if lowercased.contains("pizza") || lowercased.contains("restaurant") || lowercased.contains("grill") || 
           lowercased.contains("chipotle") || lowercased.contains("noodle") || lowercased.contains("hakka") ||
           lowercased.contains("jerk") { return "fork.knife" }
        if lowercased.contains("haircut") || lowercased.contains("barber") { return "scissors" }
        if lowercased.contains("store") || lowercased.contains("shop") || lowercased.contains("mall") { return "bag.fill" }
        if lowercased.contains("school") || lowercased.contains("university") { return "graduationcap.fill" }
        if lowercased.contains("hospital") || lowercased.contains("clinic") { return "cross.fill" }
        if lowercased.contains("park") { return "leaf.fill" }
        return "mappin.circle.fill"
    }
}

// MARK: - Weekly Places Sheet
struct WeeklyPlacesSheet: View {
    let places: [SavedPlace]
    @Binding var selectedPlace: SavedPlace?
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(places) { place in
                        WeeklyPlaceGridItem(place: place, colorScheme: colorScheme) {
                            selectedPlace = place
                            dismiss()
                        }
                    }
                }
                .padding(16)
            }
            .background(colorScheme == .dark ? Color.black : Color(red: 0.98, green: 0.98, blue: 0.98))
            .navigationTitle("Places Visited")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(FontManager.geist(size: 16, weight: .semibold))
                }
            }
        }
    }
}

struct WeeklyPlaceGridItem: View {
    let place: SavedPlace
    let colorScheme: ColorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                // Image
                ZStack {
                    if let firstPhoto = place.photos.first, let url = URL(string: firstPhoto) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Color.gray.opacity(0.2)
                        }
                    } else {
                        ZStack {
                            Color.gray.opacity(0.1)
                            Image(systemName: place.getDisplayIcon())
                                .font(FontManager.geist(size: 30, weight: .regular))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color.gray.opacity(0.1))
                
                // Details
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.displayName)
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text(place.category)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(12)
            }
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

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
