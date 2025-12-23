import SwiftUI

struct RankingView: View {
    @ObservedObject var locationsManager: LocationsManager
    let colorScheme: ColorScheme
    let locationSearchText: String

    @State private var selectedCuisineFilter: String = "All Cuisines"
    @State private var expandedRatingSections: Set<String> = ["Top Rated"] // Default to expanded

    var restaurants: [SavedPlace] {
        locationsManager.savedPlaces.filter { place in
            place.category.lowercased().contains("restaurant")
        }
    }

    var filteredAndSortedRestaurants: [SavedPlace] {
        var filtered = restaurants

        // Apply location search filter
        if !locationSearchText.isEmpty {
            let searchLower = locationSearchText.lowercased()
            filtered = filtered.filter { place in
                (place.country?.lowercased().contains(searchLower) ?? false) ||
                (place.province?.lowercased().contains(searchLower) ?? false) ||
                (place.city?.lowercased().contains(searchLower) ?? false) ||
                place.address.lowercased().contains(searchLower) ||
                place.displayName.lowercased().contains(searchLower)
            }
        }

        // Apply cuisine filter
        if selectedCuisineFilter != "All Cuisines" {
            filtered = filtered.filter { place in
                if let userCuisine = place.userCuisine {
                    return userCuisine == selectedCuisineFilter
                }
                return place.name.lowercased().contains(selectedCuisineFilter.lowercased()) ||
                       place.category.lowercased().contains(selectedCuisineFilter.lowercased())
            }
        }

        // Sort by user rating (highest first, null ratings at end)
        return filtered.sorted { a, b in
            if let aRating = a.userRating, let bRating = b.userRating {
                return aRating > bRating
            } else if a.userRating != nil {
                return true
            } else {
                return false
            }
        }
    }
    
    var topRated: [SavedPlace] {
        filteredAndSortedRestaurants.filter { $0.userRating != nil && $0.userRating! >= 8 }
    }
    
    var goodRated: [SavedPlace] {
        filteredAndSortedRestaurants.filter { 
            if let rating = $0.userRating {
                return rating >= 5 && rating < 8
            }
            return false
        }
    }
    
    var needsRating: [SavedPlace] {
        filteredAndSortedRestaurants.filter { $0.userRating == nil }
    }
    
    var ratedRestaurants: [SavedPlace] {
        filteredAndSortedRestaurants.filter { $0.userRating != nil }
    }
    
    var averageRating: Double {
        guard !ratedRestaurants.isEmpty else { return 0 }
        let sum = ratedRestaurants.compactMap { $0.userRating }.reduce(0, +)
        return Double(sum) / Double(ratedRestaurants.count)
    }

    var availableCuisines: [String] {
        var cuisines = Set<String>()
        cuisines.insert("All Cuisines")

        for restaurant in restaurants {
            if let userCuisine = restaurant.userCuisine {
                cuisines.insert(userCuisine)
            } else {
                if restaurant.name.contains("Italian") || restaurant.category.contains("Italian") {
                    cuisines.insert("Italian")
                }
                if restaurant.name.contains("Chinese") || restaurant.category.contains("Chinese") {
                    cuisines.insert("Chinese")
                }
                if restaurant.name.contains("Japanese") || restaurant.category.contains("Japanese") {
                    cuisines.insert("Japanese")
                }
                if restaurant.name.contains("Thai") || restaurant.category.contains("Thai") {
                    cuisines.insert("Thai")
                }
                if restaurant.name.contains("Indian") || restaurant.category.contains("Indian") {
                    cuisines.insert("Indian")
                }
                if restaurant.name.contains("Mexican") || restaurant.category.contains("Mexican") {
                    cuisines.insert("Mexican")
                }
                if restaurant.name.contains("French") || restaurant.category.contains("French") {
                    cuisines.insert("French")
                }
                if restaurant.name.contains("Korean") || restaurant.category.contains("Korean") {
                    cuisines.insert("Korean")
                }
                if restaurant.name.contains("Shawarma") || restaurant.category.contains("Shawarma") {
                    cuisines.insert("Shawarma")
                }
                if restaurant.name.contains("Jamaican") || restaurant.category.contains("Jamaican") {
                    cuisines.insert("Jamaican")
                }
                if restaurant.name.contains("Pizza") || restaurant.category.contains("Pizza") {
                    cuisines.insert("Pizza")
                }
                if restaurant.name.contains("Burger") || restaurant.category.contains("Burger") {
                    cuisines.insert("Burger")
                }
                if restaurant.name.contains("Coffee") || restaurant.category.contains("Coffee") {
                    cuisines.insert("Cafe")
                }
            }
        }

        var sorted = Array(cuisines).sorted()
        if let index = sorted.firstIndex(of: "All Cuisines") {
            sorted.remove(at: index)
            sorted.insert("All Cuisines", at: 0)
        }
        return sorted
    }

    var body: some View {
        VStack(spacing: 0) {
            if filteredAndSortedRestaurants.isEmpty {
                emptyStateView
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Stats summary card
                        statsSummaryCard
                        
                        // Cuisine filter pills
                        filterPillsSection
                        
                        // Top Rated section
                        if !topRated.isEmpty {
                            ratingSection(
                                title: "Top Rated",
                                subtitle: "8-10",
                                restaurants: topRated,
                                accentColor: Color.green,
                                isExpanded: expandedRatingSections.contains("Top Rated"),
                                onToggle: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if expandedRatingSections.contains("Top Rated") {
                                            expandedRatingSections.remove("Top Rated")
                                        } else {
                                            expandedRatingSections.insert("Top Rated")
                                        }
                                    }
                                    HapticManager.shared.light()
                                }
                            )
                        }
                        
                        // Good section
                        if !goodRated.isEmpty {
                            ratingSection(
                                title: "Good",
                                subtitle: "5-7",
                                restaurants: goodRated,
                                accentColor: Color.orange,
                                isExpanded: expandedRatingSections.contains("Good"),
                                onToggle: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if expandedRatingSections.contains("Good") {
                                            expandedRatingSections.remove("Good")
                                        } else {
                                            expandedRatingSections.insert("Good")
                                        }
                                    }
                                    HapticManager.shared.light()
                                }
                            )
                        }
                        
                        // Needs Rating section
                        if !needsRating.isEmpty {
                            ratingSection(
                                title: "Needs Rating",
                                subtitle: "\(needsRating.count) unrated",
                                restaurants: needsRating,
                                accentColor: Color.gray,
                                isExpanded: expandedRatingSections.contains("Needs Rating"),
                                onToggle: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        if expandedRatingSections.contains("Needs Rating") {
                                            expandedRatingSections.remove("Needs Rating")
                                        } else {
                                            expandedRatingSections.insert("Needs Rating")
                                        }
                                    }
                                    HapticManager.shared.light()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            colorScheme == .dark ? Color.black : Color.white
        )
    }
    
    // MARK: - Stats Summary Card
    
    private var statsSummaryCard: some View {
        VStack(spacing: 12) {
            // Stats grid
            HStack(spacing: 16) {
                statItem(
                    value: "\(restaurants.count)",
                    label: "Total",
                    icon: "fork.knife"
                )
                
                statItem(
                    value: ratedRestaurants.isEmpty ? "—" : String(format: "%.1f", averageRating),
                    label: "Avg Rating",
                    icon: "star.fill"
                )
                
                statItem(
                    value: "\(needsRating.count)",
                    label: "Unrated",
                    icon: "star"
                )
            }
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private func statItem(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Filter Pills Section
    
    private var filterPillsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableCuisines, id: \.self) { cuisine in
                    filterPillButton(cuisine: cuisine)
                }
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func filterPillButton(cuisine: String) -> some View {
        let isSelected = selectedCuisineFilter == cuisine
        
        return Button(action: {
            HapticManager.shared.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedCuisineFilter = cuisine
            }
        }) {
            Text(cuisine)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .foregroundColor(pillForegroundColor(isSelected: isSelected))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(pillBackgroundColor(isSelected: isSelected))
                )
                .overlay(
                    Capsule()
                        .stroke(pillBorderColor(isSelected: isSelected), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func pillForegroundColor(isSelected: Bool) -> Color {
        if isSelected {
            return .white
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65)
        }
    }
    
    private func pillBackgroundColor(isSelected: Bool) -> Color {
        if isSelected {
            return colorScheme == .dark ? Color.white.opacity(0.2) : Color.black
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
        }
    }
    
    private func pillBorderColor(isSelected: Bool) -> Color {
        if isSelected {
            return Color.clear
        } else {
            return colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
        }
    }
    
    // MARK: - Rating Section
    
    private func ratingSection(title: String, subtitle: String, restaurants: [SavedPlace], accentColor: Color, isExpanded: Bool, onToggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header - clickable to expand/collapse
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Accent indicator
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accentColor)
                        .frame(width: 3, height: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                    
                    Spacer()
                    
                    // Chevron indicator
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                        .frame(width: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Restaurants list - only show when expanded
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(restaurants) { restaurant in
                        RankingCard(
                            restaurant: restaurant,
                            colorScheme: colorScheme,
                            onRatingUpdate: { newRating, newNotes, newCuisine in
                                locationsManager.updateRestaurantRating(restaurant.id, rating: newRating, notes: newNotes, cuisine: newCuisine)
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    colorScheme == .dark 
                        ? Color.white.opacity(0.08)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.04),
            radius: 20,
            x: 0,
            y: 4
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(.system(size: 56, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

            Text("No restaurants saved")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

            Text(restaurants.isEmpty ? "Search and save restaurants to rate them" : "No restaurants match this cuisine")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 80)
    }
}

#Preview {
    RankingView(
        locationsManager: LocationsManager.shared,
        colorScheme: .dark,
        locationSearchText: ""
    )
}
