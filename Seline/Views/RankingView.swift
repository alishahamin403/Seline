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
                // Auto-detect cuisine from name/category
                let name = restaurant.name.lowercased()
                let category = restaurant.category.lowercased()
                
                if name.contains("italian") || category.contains("italian") || name.contains("pasta") {
                    cuisines.insert("Italian")
                }
                if name.contains("chinese") || category.contains("chinese") {
                    cuisines.insert("Chinese")
                }
                if name.contains("japanese") || category.contains("japanese") || name.contains("sushi") || name.contains("ramen") {
                    cuisines.insert("Japanese")
                }
                if name.contains("thai") || category.contains("thai") {
                    cuisines.insert("Thai")
                }
                if name.contains("indian") || category.contains("indian") || name.contains("curry") {
                    cuisines.insert("Indian")
                }
                if name.contains("pakistani") || category.contains("pakistani") || name.contains("biryani") {
                    cuisines.insert("Pakistani")
                }
                if name.contains("mexican") || category.contains("mexican") || name.contains("taco") || name.contains("burrito") {
                    cuisines.insert("Mexican")
                }
                if name.contains("french") || category.contains("french") || name.contains("bistro") {
                    cuisines.insert("French")
                }
                if name.contains("korean") || category.contains("korean") || name.contains("bbq") {
                    cuisines.insert("Korean")
                }
                if name.contains("shawarma") || name.contains("kebab") || name.contains("falafel") || name.contains("middle eastern") || name.contains("lebanese") || name.contains("persian") {
                    cuisines.insert("Middle Eastern")
                }
                if name.contains("jamaican") || category.contains("jamaican") || name.contains("jerk") {
                    cuisines.insert("Jamaican")
                }
                if name.contains("pizza") || category.contains("pizza") {
                    cuisines.insert("Pizza")
                }
                if name.contains("burger") || category.contains("burger") {
                    cuisines.insert("Burger")
                }
                if name.contains("coffee") || category.contains("coffee") || name.contains("cafe") {
                    cuisines.insert("Cafe")
                }
                if name.contains("vietnamese") || category.contains("vietnamese") || name.contains("pho") || name.contains("banh mi") {
                    cuisines.insert("Vietnamese")
                }
                if name.contains("greek") || category.contains("greek") || name.contains("gyro") || name.contains("souvlaki") {
                    cuisines.insert("Greek")
                }
                if name.contains("mediterranean") || category.contains("mediterranean") {
                    cuisines.insert("Mediterranean")
                }
                if name.contains("turkish") || category.contains("turkish") || name.contains("doner") {
                    cuisines.insert("Turkish")
                }
                if name.contains("seafood") || category.contains("seafood") || name.contains("fish") || name.contains("lobster") || name.contains("oyster") {
                    cuisines.insert("Seafood")
                }
                if name.contains("american") || name.contains("diner") {
                    cuisines.insert("American")
                }
                if name.contains("bbq") || name.contains("barbecue") || name.contains("smokehouse") {
                    cuisines.insert("BBQ")
                }
                if name.contains("caribbean") || category.contains("caribbean") {
                    cuisines.insert("Caribbean")
                }
                if name.contains("vegan") || name.contains("vegetarian") || name.contains("plant-based") {
                    cuisines.insert("Vegetarian")
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
                    VStack(spacing: 24) {
                        // Cuisine filter pills
                        filterPillsSection
                        
                        // Top Rated section
                        if !topRated.isEmpty {
                            ratingSection(
                                title: "Top Rated",
                                subtitle: "Rating 8.0 - 10.0",
                                icon: "crown.fill",
                                count: topRated.count,
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
                                subtitle: "Rating 5.0 - 7.0",
                                icon: "hand.thumbsup.fill",
                                count: goodRated.count,
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
                                subtitle: "Not yet reviewed",
                                icon: "star.bubble.fill",
                                count: needsRating.count,
                                restaurants: needsRating,
                                accentColor: Color.blue,
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
                    .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 100)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            colorScheme == .dark ? Color.black : Color.white
        )
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
                .font(FontManager.geist(size: 13, systemWeight: isSelected ? .semibold : .medium))
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
    
    private func ratingSection(title: String, subtitle: String, icon: String, count: Int, restaurants: [SavedPlace], accentColor: Color, isExpanded: Bool, onToggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header - clickable to expand/collapse
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(FontManager.geist(size: 16, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        
                        Text(subtitle)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                    }
                    
                    Spacer()
                    
                    // Count Badge - Oval shaped circle matching all locations widget
                    Text("\(count)")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(minWidth: 24, minHeight: 24)
                        .padding(.horizontal, 6)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                        )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Restaurants list - only show when expanded
            if isExpanded {
                VStack(spacing: 14) {
                    Divider()
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        .padding(.bottom, 4)
                        
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
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "fork.knife")
                .font(FontManager.geist(size: 56, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

            Text("No restaurants saved")
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

            Text(restaurants.isEmpty ? "Search and save restaurants to rate them" : "No restaurants match this cuisine")
                .font(FontManager.geist(size: 14, weight: .regular))
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
