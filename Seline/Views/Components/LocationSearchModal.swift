import SwiftUI
import CoreLocation

struct LocationSearchModal: View {
    private struct SelectedPlaceContext: Identifiable {
        let id: String
        let details: PlaceDetails
    }

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var mapsService = GoogleMapsService.shared
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var locationService = LocationService.shared

    @State private var searchText = ""
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var isSearching = false
    @State private var selectedPlaceContext: SelectedPlaceContext? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(.gray)

                    TextField("Search for a place...", text: $searchText)
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .focused($isSearchFieldFocused)
                        .onChange(of: searchText) { newValue in
                            // Cancel previous search task
                            searchTask?.cancel()

                            if newValue.isEmpty {
                                searchResults = []
                                isSearching = false
                                return
                            }

                            // Debounce search - wait 0.5s for user to finish typing
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                                if !Task.isCancelled {
                                    await performSearch(query: newValue)
                                }
                            }
                        }
                        .onSubmit {
                            if !searchText.isEmpty {
                                Task {
                                    await performSearch(query: searchText)
                                }
                            }
                        }

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                            searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(FontManager.geist(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Search Results
                if isSearching {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Searching...")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !searchText.isEmpty && searchResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(FontManager.geist(size: 48, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                        Text("No results found")
                            .font(FontManager.geist(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                        Text("Try searching for a different location")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
                } else if searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(FontManager.geist(size: 48, weight: .light))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                        Text("Search for places")
                            .font(FontManager.geist(size: 18, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                        Text("Find restaurants, cafes, stores, and more")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Mini map showing search result locations
                            SearchResultsMapView(
                                searchResults: searchResults,
                                currentLocation: locationService.currentLocation,
                                onResultTap: { result in
                                    loadPlaceDetails(placeId: result.id)
                                }
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            
                            // Search results list
                            LazyVStack(spacing: 0) {
                                ForEach(searchResults) { result in
                                    PlaceSearchResultRow(
                                        result: result,
                                        isSaved: locationsManager.isPlaceSaved(googlePlaceId: result.id),
                                        currentLocation: locationService.currentLocation,
                                        onSave: {
                                            // Save handled in detail view
                                        },
                                        onTap: {
                                            loadPlaceDetails(placeId: result.id)
                                        }
                                    )

                                    if result.id != searchResults.last?.id {
                                        Rectangle()
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                                            .frame(height: 1)
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .background(
                (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                    .ignoresSafeArea()
            )
            .navigationTitle("Find Location")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Auto-focus search field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isSearchFieldFocused = true
                }
            }
        }
        .sheet(item: $selectedPlaceContext) { context in
            LocationDetailViewWrapper(googlePlaceId: context.id, initialPlaceDetails: context.details)
        }
        .presentationBg()
    }

    // MARK: - Actions

    private func performSearch(query: String) async {
        await MainActor.run {
            isSearching = true
        }

        do {
            var results = try await mapsService.searchPlaces(
                query: query,
                currentLocation: locationService.currentLocation
            )

            await MainActor.run {
                // Sort results by distance (closest to furthest)
                // Prioritize nearby locations (within 50km) over far away ones
                if let currentLocation = locationService.currentLocation {
                    results = results.sorted { result1, result2 in
                        let location1 = CLLocation(latitude: result1.latitude, longitude: result1.longitude)
                        let location2 = CLLocation(latitude: result2.latitude, longitude: result2.longitude)
                        
                        let distance1 = currentLocation.distance(from: location1)
                        let distance2 = currentLocation.distance(from: location2)
                        
                        // Prioritize nearby locations (within 50km) - they come first
                        let isNearby1 = distance1 <= 50000 // 50km in meters
                        let isNearby2 = distance2 <= 50000
                        
                        if isNearby1 && !isNearby2 {
                            return true // result1 is nearby, result2 is not
                        } else if !isNearby1 && isNearby2 {
                            return false // result2 is nearby, result1 is not
                        } else {
                            // Both are nearby or both are far - sort by distance
                            return distance1 < distance2
                        }
                    }
                }
                
                searchResults = results
                isSearching = false

                // Save to search history
                if let firstResult = results.first {
                    locationsManager.addToSearchHistory(firstResult)
                }
            }
        } catch {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
        }
    }

    private func loadPlaceDetails(placeId: String) {
        Task {
            do {
                let details = try await mapsService.getPlaceDetails(placeId: placeId)

                await MainActor.run {
                    selectedPlaceContext = SelectedPlaceContext(id: placeId, details: details)
                }
            } catch {
                // Handle error silently
            }
        }
    }
}

// MARK: - Location Detail View Wrapper

struct LocationDetailViewWrapper: View {
    let googlePlaceId: String
    let initialPlaceDetails: PlaceDetails?
    @StateObject private var mapsService = GoogleMapsService.shared
    @State private var placeDetails: PlaceDetails?
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @Environment(\.dismiss) var dismiss

    init(googlePlaceId: String, initialPlaceDetails: PlaceDetails?) {
        self.googlePlaceId = googlePlaceId
        self.initialPlaceDetails = initialPlaceDetails
        // Initialize placeDetails with initialPlaceDetails to avoid blank screen
        _placeDetails = State(initialValue: initialPlaceDetails)
    }

    var body: some View {
        LocationDetailView(placeDetails: placeDetails, googlePlaceId: googlePlaceId)
            .onAppear {
                // Only fetch if we don't have initial data
                if placeDetails == nil {
                    loadPlaceDetails()
                }
            }
    }

    private func loadPlaceDetails() {
        guard !isLoading else { return }

        isLoading = true
        Task {
            do {
                let details = try await mapsService.getPlaceDetails(placeId: googlePlaceId)
                await MainActor.run {
                    placeDetails = details
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                    isLoading = false
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Place Search Result Row

private struct PlaceSearchResultRow: View {
    let result: PlaceSearchResult
    let isSaved: Bool
    let currentLocation: CLLocation?
    let onSave: () -> Void
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme

    private var initials: String {
        let words = result.name.split(separator: " ")
        if words.count >= 2 {
            let first = String(words[0].prefix(1))
            let second = String(words[1].prefix(1))
            return (first + second).uppercased()
        } else if let firstWord = words.first {
            return String(firstWord.prefix(2)).uppercased()
        }
        return "?"
    }

    private var distanceText: String? {
        guard let currentLocation else { return nil }
        let placeLocation = CLLocation(latitude: result.latitude, longitude: result.longitude)
        let distanceInMeters = currentLocation.distance(from: placeLocation)
        let distanceInKm = distanceInMeters / 1000.0

        if distanceInKm < 1.0 {
            return String(format: "%.0fm", distanceInMeters)
        } else {
            return String(format: "%.1f km", distanceInKm)
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let photoURL = result.photoURL {
                    CachedAsyncImage(url: photoURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(colorScheme == .dark ? Color(white: 0.85) : Color(white: 0.25))
                            Text(initials)
                                .font(FontManager.geist(size: 14, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                        }
                        .frame(width: 44, height: 44)
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color(white: 0.85) : Color(white: 0.25))
                        Text(initials)
                            .font(FontManager.geist(size: 14, weight: .bold))
                            .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                    }
                    .frame(width: 44, height: 44)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.name)
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(result.address)
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                            .lineLimit(1)

                        if let distance = distanceText {
                            Text("• \(distance)")
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        }
                    }
                }

                Spacer()

                if !isSaved {
                    Button(action: onSave) {
                        Image(systemName: "bookmark")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    Image(systemName: "checkmark")
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LocationSearchModal()
}
