import SwiftUI

struct LocationSearchModal: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var mapsService = GoogleMapsService.shared
    @StateObject private var locationsManager = LocationsManager.shared

    @State private var searchText = ""
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var isSearching = false
    @State private var selectedPlaceDetails: PlaceDetails? = nil
    @State private var selectedGooglePlaceId: String? = nil
    @State private var showLocationDetail = false
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                    TextField("Search for a place...", text: $searchText)
                        .font(.shadcnTextBase)
                        .foregroundColor(Color.shadcnForeground(colorScheme))
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
                                .font(.system(size: 16))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                        .fill(
                            colorScheme == .dark ?
                                Color.black.opacity(0.3) : Color.gray.opacity(0.1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                .stroke(
                                    colorScheme == .dark ?
                                        Color.white.opacity(0.1) : Color.black.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // Search Results
                if isSearching {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Searching...")
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !searchText.isEmpty && searchResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))

                        Text("No results found")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                        Text("Try searching for a different location")
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
                } else if searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                        Text("Search for places")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                        Text("Find restaurants, cafes, stores, and more")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 60)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults) { result in
                                PlaceSearchResultRow(
                                    result: result,
                                    isSaved: locationsManager.isPlaceSaved(googlePlaceId: result.id),
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
                        .padding(.top, 8)
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
        .fullScreenCover(isPresented: $showLocationDetail) {
            if let placeId = selectedGooglePlaceId {
                LocationDetailViewWrapper(googlePlaceId: placeId, initialPlaceDetails: selectedPlaceDetails)
            }
        }
    }

    // MARK: - Actions

    private func performSearch(query: String) async {
        await MainActor.run {
            isSearching = true
        }

        do {
            print("🔍 Searching for: \(query)")
            let results = try await mapsService.searchPlaces(query: query)
            print("✅ Found \(results.count) results")

            await MainActor.run {
                searchResults = results
                isSearching = false

                // Save to search history
                if let firstResult = results.first {
                    locationsManager.addToSearchHistory(firstResult)
                }
            }
        } catch {
            await MainActor.run {
                print("❌ Search failed: \(error)")
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
                    selectedPlaceDetails = details
                    selectedGooglePlaceId = placeId
                    showLocationDetail = true
                }
            } catch {
                print("❌ Failed to load place details: \(error)")
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
                    print("❌ Failed to load place details: \(error)")
                    loadError = error.localizedDescription
                    isLoading = false
                    // Dismiss on error
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    LocationSearchModal()
}
