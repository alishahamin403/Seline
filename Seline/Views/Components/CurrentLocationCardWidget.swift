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
    
    @State private var isExpanded: Bool = false
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
        VStack(alignment: .leading, spacing: 0) {
            // Header Section - Always visible
            headerView
            
            // Expanded Content
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isExpanded)
        .task {
            // Initial load
            await loadWeeklyStats()
        }
        .onChange(of: isExpanded) { expanded in
            if expanded {
                Task {
                    await loadWeeklyStats()
                }
            }
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
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 14) {
            // Location Icon
            ZStack {
                Circle()
                    .fill(activeIndicatorColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "location.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(activeIndicatorColor)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let place = nearbyLocationPlace {
                    selectedPlace = place
                }
            }
            
            // Location Info with Progress Bar
            VStack(alignment: .leading, spacing: 6) {
                // Location name
                Text(currentLocationDisplay)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(1)
                
                // Progress bar with time
                HStack(spacing: 8) {
                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 3)
                                .fill(progressBarBackground)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 3)
                                .fill(activeIndicatorColor)
                                .frame(width: min(geo.size.width, geo.size.width * progressPercentage))
                        }
                    }
                    .frame(height: 6)
                    .frame(maxWidth: 100)
                    
                    // Time
                    Text(elapsedTimeString.isEmpty ? "Just arrived" : elapsedTimeString)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let place = nearbyLocationPlace {
                    selectedPlace = place
                }
            }
            
            Spacer()
            
            // Expand/Collapse Button
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                HapticManager.shared.light()
            }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tertiaryTextColor)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var progressPercentage: CGFloat {
        // Calculate progress as percentage of a typical day (16 waking hours = 960 minutes)
        let maxMinutes: CGFloat = 480 // 8 hours max for visual purposes
        return min(1.0, CGFloat(currentTimeMinutes) / maxMinutes)
    }
    
    // MARK: - Expanded Content
    
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Divider
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                .frame(height: 1)
                .padding(.top, 12)
            
            // Today's Activity Section
            if !todaysVisits.isEmpty {
                todaysActivitySection
            }
            
            // Weekly Insights Section
            weeklyInsightsSection
        }
    }
    
    // MARK: - Today's Activity Section
    
    private var todaysActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section Header
            HStack {
                Text("Today's Activity")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                // Total time pill
                Text(formatDuration(totalTodayMinutes))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06))
                    )
            }
            
            // Activity Bars
            VStack(spacing: 8) {
                ForEach(Array(todaysVisits.prefix(5).enumerated()), id: \.element.id) { index, visit in
                    activityRow(visit: visit, index: index)
                }
            }
        }
    }
    
    private func activityRow(visit: (id: UUID, displayName: String, totalDurationMinutes: Int, isActive: Bool), index: Int) -> some View {
        HStack(spacing: 10) {
            // Name
            Text(visit.displayName)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            
            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressBarBackground)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorForIndex(index))
                        .frame(width: barWidth(for: visit.totalDurationMinutes, in: geo.size.width))
                }
            }
            .frame(height: 8)
            
            // Duration
            Text(formatDuration(visit.totalDurationMinutes))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(visit.isActive ? activeIndicatorColor : secondaryTextColor)
                .frame(width: 55, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Find and select the place
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
                .font(.system(size: 12, weight: .semibold))
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
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(tertiaryTextColor)
            
            Text(value)
                .font(.system(size: 13, weight: .semibold))
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
                    .font(.system(size: 16, weight: .semibold))
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
                                .font(.system(size: 30))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Text(place.category)
                        .font(.system(size: 12))
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
