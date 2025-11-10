import SwiftUI

struct RankingView: View {
    @ObservedObject var locationsManager: LocationsManager
    let colorScheme: ColorScheme

    @State private var selectedCuisineFilter: String = "All Cuisines"
    @State private var selectedCountry: String?
    @State private var selectedProvince: String?
    @State private var selectedCity: String?

    var restaurants: [SavedPlace] {
        locationsManager.savedPlaces.filter { place in
            place.category.lowercased().contains("restaurant")
        }
    }

    var provinces: Set<String> {
        selectedCountry.map { locationsManager.getProvinces(in: $0) } ?? locationsManager.provinces
    }

    var cities: Set<String> {
        if let country = selectedCountry, let province = selectedProvince {
            return locationsManager.getCities(in: country, andProvince: province)
        } else if let country = selectedCountry {
            return locationsManager.getCities(in: country)
        } else {
            return []
        }
    }

    var filteredAndSortedRestaurants: [SavedPlace] {
        var filtered = restaurants

        // Apply location filters
        if let country = selectedCountry, !country.isEmpty {
            filtered = filtered.filter { $0.country == country }
        }

        if let province = selectedProvince, !province.isEmpty {
            filtered = filtered.filter { $0.province == province }
        }

        if let city = selectedCity, !city.isEmpty {
            filtered = filtered.filter { $0.city == city }
        }

        // Apply cuisine filter
        if selectedCuisineFilter != "All Cuisines" {
            filtered = filtered.filter { place in
                // Check user-assigned cuisine first, then fall back to name/category detection
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

    var availableCuisines: [String] {
        var cuisines = Set<String>()
        cuisines.insert("All Cuisines")

        for restaurant in restaurants {
            // Use user-assigned cuisine if available
            if let userCuisine = restaurant.userCuisine {
                cuisines.insert(userCuisine)
            } else {
                // Otherwise extract cuisine from name or category
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
            // Location filters (dropdowns)
            HStack(spacing: 12) {
                // Country filter dropdown
                CompactDropdown(
                    label: selectedCountry ?? "Country",
                    options: ["All"] + Array(locationsManager.countries).sorted(),
                    selectedOption: selectedCountry,
                    onSelect: { option in
                        selectedCountry = option == "All" ? nil : option
                    },
                    colorScheme: colorScheme
                )

                // Province filter dropdown
                CompactDropdown(
                    label: selectedProvince ?? "Province",
                    options: ["All"] + Array(provinces).sorted(),
                    selectedOption: selectedProvince,
                    onSelect: { option in
                        selectedProvince = option == "All" ? nil : option
                    },
                    colorScheme: colorScheme
                )

                // City filter dropdown
                CompactDropdown(
                    label: selectedCity ?? "City",
                    options: ["All"] + Array(cities).sorted(),
                    selectedOption: selectedCity,
                    onSelect: { option in
                        selectedCity = option == "All" ? nil : option
                    },
                    colorScheme: colorScheme
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            // Cuisine filter (pills)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableCuisines, id: \.self) { cuisine in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedCuisineFilter = cuisine
                            }
                        }) {
                            Text(cuisine)
                                .font(.system(size: 12, weight: selectedCuisineFilter == cuisine ? .semibold : .medium))
                                .foregroundColor(selectedCuisineFilter == cuisine ? .white : .gray)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(
                                            selectedCuisineFilter == cuisine ?
                                                Color(red: 0.2, green: 0.2, blue: 0.2) : Color.clear
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            selectedCuisineFilter == cuisine ? Color.clear : Color.gray.opacity(0.3),
                                            lineWidth: 1
                                        )
                                )
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)

            // Restaurants list
            if filteredAndSortedRestaurants.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                    Text("No restaurants saved")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                    Text(restaurants.isEmpty ? "Search and save restaurants to rate them" : "No restaurants match this cuisine")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(filteredAndSortedRestaurants) { restaurant in
                            RankingCard(
                                restaurant: restaurant,
                                colorScheme: colorScheme,
                                onRatingUpdate: { newRating, newNotes, newCuisine in
                                    locationsManager.updateRestaurantRating(restaurant.id, rating: newRating, notes: newNotes, cuisine: newCuisine)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 0)
                    .padding(.bottom, 20)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(
            colorScheme == .dark ? Color.black : Color.white
        )
    }
}

#Preview {
    RankingView(
        locationsManager: LocationsManager.shared,
        colorScheme: .dark
    )
}
