import SwiftUI
import CoreLocation

struct AllLocationsEditView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var googleMapsService = GoogleMapsService.shared
    @StateObject private var supabaseManager = SupabaseManager.shared

    var currentPreferences: UserLocationPreferences?

    @State private var location1Address: String = ""
    @State private var location1Icon: String = "house.fill"
    @State private var location1SearchQuery: String = ""
    @State private var location1SearchResults: [PlaceSearchResult] = []
    @State private var location1Coords: CLLocationCoordinate2D?

    @State private var location2Address: String = ""
    @State private var location2Icon: String = "briefcase.fill"
    @State private var location2SearchQuery: String = ""
    @State private var location2SearchResults: [PlaceSearchResult] = []
    @State private var location2Coords: CLLocationCoordinate2D?

    @State private var location3Address: String = ""
    @State private var location3Icon: String = "fork.knife"
    @State private var location3SearchQuery: String = ""
    @State private var location3SearchResults: [PlaceSearchResult] = []
    @State private var location3Coords: CLLocationCoordinate2D?

    @State private var location4Address: String = ""
    @State private var location4Icon: String = "mappin.circle.fill"
    @State private var location4SearchQuery: String = ""
    @State private var location4SearchResults: [PlaceSearchResult] = []
    @State private var location4Coords: CLLocationCoordinate2D?

    @State private var isSaving = false
    @State private var showIconPicker1 = false
    @State private var showIconPicker2 = false
    @State private var showIconPicker3 = false
    @State private var showIconPicker4 = false

    init(currentPreferences: UserLocationPreferences?) {
        self.currentPreferences = currentPreferences
    }

    private func getLocationName(_ index: Int) -> String {
        switch index {
        case 1: return "Location 1"
        case 2: return "Location 2"
        case 3: return "Location 3"
        case 4: return "Location 4"
        default: return "Location"
        }
    }

    private func searchPlace(query: String, index: Int) {
        guard !query.isEmpty else {
            switch index {
            case 1: location1SearchResults = []
            case 2: location2SearchResults = []
            case 3: location3SearchResults = []
            case 4: location4SearchResults = []
            default: break
            }
            return
        }

        Task {
            do {
                let results = try await googleMapsService.searchPlaces(query: query)
                switch index {
                case 1: location1SearchResults = results
                case 2: location2SearchResults = results
                case 3: location3SearchResults = results
                case 4: location4SearchResults = results
                default: break
                }
            } catch {
                print("Error searching places: \(error)")
            }
        }
    }

    private func selectPlace(_ place: PlaceSearchResult, index: Int) {
        switch index {
        case 1:
            location1Address = place.name
            location1Coords = place.coordinate
            location1SearchResults = []
            location1SearchQuery = ""
        case 2:
            location2Address = place.name
            location2Coords = place.coordinate
            location2SearchResults = []
            location2SearchQuery = ""
        case 3:
            location3Address = place.name
            location3Coords = place.coordinate
            location3SearchResults = []
            location3SearchQuery = ""
        case 4:
            location4Address = place.name
            location4Coords = place.coordinate
            location4SearchResults = []
            location4SearchQuery = ""
        default: break
        }
    }

    private func saveLocations() async {
        isSaving = true

        var updatedPrefs = currentPreferences ?? UserLocationPreferences()

        // Update location 1
        updatedPrefs.location1Address = location1Address.isEmpty ? nil : location1Address
        updatedPrefs.location1Icon = location1Icon
        updatedPrefs.location1Latitude = location1Coords?.latitude
        updatedPrefs.location1Longitude = location1Coords?.longitude

        // Update location 2
        updatedPrefs.location2Address = location2Address.isEmpty ? nil : location2Address
        updatedPrefs.location2Icon = location2Icon
        updatedPrefs.location2Latitude = location2Coords?.latitude
        updatedPrefs.location2Longitude = location2Coords?.longitude

        // Update location 3
        updatedPrefs.location3Address = location3Address.isEmpty ? nil : location3Address
        updatedPrefs.location3Icon = location3Icon
        updatedPrefs.location3Latitude = location3Coords?.latitude
        updatedPrefs.location3Longitude = location3Coords?.longitude

        // Update location 4
        updatedPrefs.location4Address = location4Address.isEmpty ? nil : location4Address
        updatedPrefs.location4Icon = location4Icon
        updatedPrefs.location4Latitude = location4Coords?.latitude
        updatedPrefs.location4Longitude = location4Coords?.longitude

        do {
            try await supabaseManager.saveLocationPreferences(updatedPrefs)
            isSaving = false
            dismiss()
        } catch {
            print("Error saving locations: \(error)")
            isSaving = false
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Location 1
                    locationEditCard(
                        title: "Location 1",
                        address: $location1Address,
                        icon: $location1Icon,
                        searchQuery: $location1SearchQuery,
                        searchResults: $location1SearchResults,
                        showIconPicker: $showIconPicker1,
                        onSelectPlace: { place in selectPlace(place, index: 1) },
                        onSearch: { query in searchPlace(query: query, index: 1) }
                    )

                    // Location 2
                    locationEditCard(
                        title: "Location 2",
                        address: $location2Address,
                        icon: $location2Icon,
                        searchQuery: $location2SearchQuery,
                        searchResults: $location2SearchResults,
                        showIconPicker: $showIconPicker2,
                        onSelectPlace: { place in selectPlace(place, index: 2) },
                        onSearch: { query in searchPlace(query: query, index: 2) }
                    )

                    // Location 3
                    locationEditCard(
                        title: "Location 3",
                        address: $location3Address,
                        icon: $location3Icon,
                        searchQuery: $location3SearchQuery,
                        searchResults: $location3SearchResults,
                        showIconPicker: $showIconPicker3,
                        onSelectPlace: { place in selectPlace(place, index: 3) },
                        onSearch: { query in searchPlace(query: query, index: 3) }
                    )

                    // Location 4
                    locationEditCard(
                        title: "Location 4",
                        address: $location4Address,
                        icon: $location4Icon,
                        searchQuery: $location4SearchQuery,
                        searchResults: $location4SearchResults,
                        showIconPicker: $showIconPicker4,
                        onSelectPlace: { place in selectPlace(place, index: 4) },
                        onSearch: { query in searchPlace(query: query, index: 4) }
                    )
                }
                .padding(16)
            }
            .navigationTitle("Edit Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task {
                            await saveLocations()
                        }
                    }) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .onAppear {
            location1Address = currentPreferences?.location1Address ?? ""
            location1Icon = currentPreferences?.location1Icon ?? "house.fill"
            location1Coords = currentPreferences?.location1Coordinate

            location2Address = currentPreferences?.location2Address ?? ""
            location2Icon = currentPreferences?.location2Icon ?? "briefcase.fill"
            location2Coords = currentPreferences?.location2Coordinate

            location3Address = currentPreferences?.location3Address ?? ""
            location3Icon = currentPreferences?.location3Icon ?? "fork.knife"
            location3Coords = currentPreferences?.location3Coordinate

            location4Address = currentPreferences?.location4Address ?? ""
            location4Icon = currentPreferences?.location4Icon ?? "mappin.circle.fill"
            location4Coords = currentPreferences?.location4Coordinate
        }
    }

    private func locationEditCard(
        title: String,
        address: Binding<String>,
        icon: Binding<String>,
        searchQuery: Binding<String>,
        searchResults: Binding<[PlaceSearchResult]>,
        showIconPicker: Binding<Bool>,
        onSelectPlace: @escaping (PlaceSearchResult) -> Void,
        onSearch: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and Icon Picker
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                Button(action: { showIconPicker.wrappedValue.toggle() }) {
                    Image(systemName: icon.wrappedValue)
                        .font(.system(size: 24))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .frame(width: 44, height: 44)
                        .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                        .cornerRadius(8)
                }
            }

            // Icon Picker Menu
            if showIconPicker.wrappedValue {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Icon")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 8) {
                        ForEach(LocationType.allCases) { locationType in
                            Button(action: {
                                icon.wrappedValue = locationType.icon
                                showIconPicker.wrappedValue = false
                            }) {
                                Image(systemName: locationType.icon)
                                    .font(.system(size: 18))
                                    .foregroundColor(icon.wrappedValue == locationType.icon ? .white : (colorScheme == .dark ? .white : .black))
                                    .frame(height: 44)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                icon.wrappedValue == locationType.icon ?
                                                Color.blue :
                                                (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                            )
                                    )
                            }
                        }
                    }
                }
                .padding(12)
                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                .cornerRadius(8)
            }

            // Address Search
            VStack(alignment: .leading, spacing: 8) {
                Text("Address")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                TextField("Search or enter address", text: searchQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: searchQuery.wrappedValue) { newValue in
                        onSearch(newValue)
                    }

                // Selected address display
                if !address.wrappedValue.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)

                        Text(address.wrappedValue)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .padding(10)
                    .background(colorScheme == .dark ? Color.green.opacity(0.2) : Color.green.opacity(0.1))
                    .cornerRadius(6)
                }

                // Search Results
                if !searchResults.wrappedValue.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(searchResults.wrappedValue.prefix(5)) { result in
                            Button(action: {
                                onSelectPlace(result)
                                address.wrappedValue = result.name
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                            .lineLimit(1)

                                        Text(result.address)
                                            .font(.system(size: 11, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                            .lineLimit(1)
                                    }

                                    Spacer()
                                }
                                .padding(10)
                                .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.02))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        .cornerRadius(12)
    }
}

#Preview {
    AllLocationsEditView(currentPreferences: nil)
}
