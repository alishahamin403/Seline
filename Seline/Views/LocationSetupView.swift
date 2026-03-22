import SwiftUI
import CoreLocation

struct LocationSetupView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var googleMapsService = GoogleMapsService.shared
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var locationService = LocationService.shared

    @State private var homeSearchQuery = ""
    @State private var workSearchQuery = ""
    @State private var homeSearchResults: [PlaceSearchResult] = []
    @State private var workSearchResults: [PlaceSearchResult] = []
    @State private var selectedHome: PlaceSearchResult?
    @State private var selectedWork: PlaceSearchResult?
    @State private var isSearchingHome = false
    @State private var isSearchingWork = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var isSetupComplete: Bool {
        selectedHome != nil || selectedWork != nil
    }

    var body: some View {
        NavigationView {
            ZStack {
                AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .bottomLeading)

                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Image(systemName: "house.fill")
                                .font(FontManager.geist(size: 46, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.82))

                            Text("Set Up Your Locations")
                                .font(FontManager.geist(size: 28, weight: .semibold))
                                .foregroundColor(Color.appTextPrimary(colorScheme))

                            Text("We’ll surface travel times and visit context around the places you use most.")
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(Color.appTextSecondary(colorScheme))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .appAmbientCardStyle(
                            colorScheme: colorScheme,
                            variant: .topTrailing,
                            cornerRadius: 28,
                            highlightStrength: 0.76
                        )
                        .padding(.top, 8)

                        VStack(spacing: 20) {
                            LocationInput(
                                title: "Home",
                                icon: "house.fill",
                                searchQuery: $homeSearchQuery,
                                searchResults: $homeSearchResults,
                                selectedLocation: $selectedHome,
                                isSearching: $isSearchingHome,
                                onSearch: { query in
                                    await searchLocation(query: query, isHome: true)
                                }
                            )

                            LocationInput(
                                title: "Work",
                                icon: "briefcase.fill",
                                searchQuery: $workSearchQuery,
                                searchResults: $workSearchResults,
                                selectedLocation: $selectedWork,
                                isSearching: $isSearchingWork,
                                onSearch: { query in
                                    await searchLocation(query: query, isHome: false)
                                }
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                        .appAmbientCardStyle(
                            colorScheme: colorScheme,
                            variant: .topLeading,
                            cornerRadius: 28,
                            highlightStrength: 0.56
                        )

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                        }

                        VStack(spacing: 12) {
                            Button(action: saveLocations) {
                                HStack {
                                    if isSaving {
                                        ShadcnSpinner(size: .medium, color: .white)
                                    } else {
                                        Text("Save & Continue")
                                            .font(FontManager.geist(size: 16, weight: .semibold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(isSetupComplete ? Color.black.opacity(colorScheme == .dark ? 0.92 : 0.84) : Color.gray.opacity(0.35))
                                )
                                .foregroundColor(.white)
                            }
                            .disabled(!isSetupComplete || isSaving)

                            Button(action: skipSetup) {
                                Text("Skip for now")
                                    .font(FontManager.geist(size: 14, weight: .regular))
                                    .foregroundColor(Color.appTextSecondary(colorScheme))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Welcome")
                        .font(FontManager.geist(size: 16, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Actions

    private func searchLocation(query: String, isHome: Bool) async {
        guard !query.isEmpty else {
            if isHome {
                homeSearchResults = []
            } else {
                workSearchResults = []
            }
            return
        }

        await MainActor.run {
            if isHome {
                isSearchingHome = true
            } else {
                isSearchingWork = true
            }
        }

        do {
            let results = try await googleMapsService.searchPlaces(
                query: query,
                currentLocation: locationService.currentLocation
            )
            await MainActor.run {
                if isHome {
                    homeSearchResults = results
                    isSearchingHome = false
                } else {
                    workSearchResults = results
                    isSearchingWork = false
                }
            }
        } catch {
            print("❌ Search error: \(error)")
            await MainActor.run {
                if isHome {
                    isSearchingHome = false
                } else {
                    isSearchingWork = false
                }
                errorMessage = "Failed to search locations. Please try again."
            }
        }
    }

    private func saveLocations() {
        Task {
            await MainActor.run {
                isSaving = true
                errorMessage = nil
            }

            do {
                var preferences = UserLocationPreferences()
                preferences.isFirstTimeSetup = false

                if let home = selectedHome {
                    preferences.location1Address = home.address
                    preferences.location1Latitude = home.latitude
                    preferences.location1Longitude = home.longitude
                    preferences.location1Icon = "house.fill"
                }

                if let work = selectedWork {
                    preferences.location2Address = work.address
                    preferences.location2Latitude = work.latitude
                    preferences.location2Longitude = work.longitude
                    preferences.location2Icon = "briefcase.fill"
                }

                try await supabaseManager.saveLocationPreferences(preferences)

                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save locations. Please try again."
                }
                print("❌ Save error: \(error)")
            }
        }
    }

    private func skipSetup() {
        Task {
            do {
                var preferences = UserLocationPreferences()
                preferences.isFirstTimeSetup = false
                try await supabaseManager.saveLocationPreferences(preferences)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("❌ Skip setup error: \(error)")
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Location Input Component

struct LocationInput: View {
    let title: String
    let icon: String
    @Binding var searchQuery: String
    @Binding var searchResults: [PlaceSearchResult]
    @Binding var selectedLocation: PlaceSearchResult?
    @Binding var isSearching: Bool
    let onSearch: (String) async -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack {
                Image(systemName: icon)
                    .font(FontManager.geist(size: 16, weight: .regular))
                    .foregroundColor(.gray)
                Text(title)
                    .font(FontManager.geist(size: 16, weight: .semibold))
            }

            // Search Field or Selected Location
            if let selected = selectedLocation {
                // Show selected location
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.name)
                            .font(FontManager.geist(size: 14, weight: .medium))
                        Text(selected.address)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button(action: {
                        selectedLocation = nil
                        searchQuery = ""
                        searchResults = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 20, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }
                .padding(12)
                .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 14)
            } else {
                // Search field
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(.gray)

                        TextField("Search for \(title.lowercased()) address", text: $searchQuery)
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .onChange(of: searchQuery) { newValue in
                                // Debounce search
                                searchTask?.cancel()
                                searchTask = Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                    if !Task.isCancelled {
                                        await onSearch(newValue)
                                    }
                                }
                            }

                        if isSearching {
                            ShadcnSpinner(size: .small)
                        }
                    }
                    .padding(12)
                    .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 14)

                    // Search Results
                    if !searchResults.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(searchResults.prefix(5)) { result in
                                Button(action: {
                                    selectedLocation = result
                                    searchResults = []
                                    searchQuery = result.name
                                }) {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(FontManager.geist(size: 16, weight: .regular))
                                            .foregroundColor(.gray)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.name)
                                                .font(FontManager.geist(size: 13, weight: .medium))
                                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                            Text(result.address)
                                                .font(FontManager.geist(size: 11, weight: .regular))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }

                                        Spacer()
                                    }
                                    .padding(12)
                                }
                                .buttonStyle(PlainButtonStyle())

                                if result.id != searchResults.prefix(5).last?.id {
                                    Divider()
                                }
                            }
                        }
                        .searchResultsCardStyle(colorScheme: colorScheme, cornerRadius: 16)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

#Preview {
    LocationSetupView()
}
