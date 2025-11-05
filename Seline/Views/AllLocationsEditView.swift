import SwiftUI
import CoreLocation

struct AllLocationsEditView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var googleMapsService = GoogleMapsService.shared
    @StateObject private var supabaseManager = SupabaseManager.shared

    var currentPreferences: UserLocationPreferences?

    @State private var selectedLocationIndex = 0

    @State private var location1Address: String = ""
    @State private var location1Icon: String = "house.fill"
    @State private var location1SearchQuery: String = ""
    @State private var location1SearchResults: [PlaceSearchResult] = []
    @State private var location1Latitude: Double?
    @State private var location1Longitude: Double?

    @State private var location2Address: String = ""
    @State private var location2Icon: String = "briefcase.fill"
    @State private var location2SearchQuery: String = ""
    @State private var location2SearchResults: [PlaceSearchResult] = []
    @State private var location2Latitude: Double?
    @State private var location2Longitude: Double?

    @State private var location3Address: String = ""
    @State private var location3Icon: String = "fork.knife"
    @State private var location3SearchQuery: String = ""
    @State private var location3SearchResults: [PlaceSearchResult] = []
    @State private var location3Latitude: Double?
    @State private var location3Longitude: Double?

    @State private var location4Address: String = ""
    @State private var location4Icon: String = "mappin.circle.fill"
    @State private var location4SearchQuery: String = ""
    @State private var location4SearchResults: [PlaceSearchResult] = []
    @State private var location4Latitude: Double?
    @State private var location4Longitude: Double?

    @State private var isSaving = false

    init(currentPreferences: UserLocationPreferences?) {
        self.currentPreferences = currentPreferences
    }

    private var locationNames: [String] {
        ["Home", "Work", "Dining", "Fitness"]
    }

    private var locationIcons: [String] {
        ["house.fill", "briefcase.fill", "fork.knife", "dumbbell.fill"]
    }

    private func getCurrentAddress() -> String {
        switch selectedLocationIndex {
        case 0: return location1Address
        case 1: return location2Address
        case 2: return location3Address
        case 3: return location4Address
        default: return ""
        }
    }

    private func setCurrentAddress(_ value: String) {
        switch selectedLocationIndex {
        case 0: location1Address = value
        case 1: location2Address = value
        case 2: location3Address = value
        case 3: location4Address = value
        default: break
        }
    }

    private func getCurrentIcon() -> String {
        switch selectedLocationIndex {
        case 0: return location1Icon
        case 1: return location2Icon
        case 2: return location3Icon
        case 3: return location4Icon
        default: return ""
        }
    }

    private func setCurrentIcon(_ value: String) {
        switch selectedLocationIndex {
        case 0: location1Icon = value
        case 1: location2Icon = value
        case 2: location3Icon = value
        case 3: location4Icon = value
        default: break
        }
    }

    private func getCurrentSearchQuery() -> String {
        switch selectedLocationIndex {
        case 0: return location1SearchQuery
        case 1: return location2SearchQuery
        case 2: return location3SearchQuery
        case 3: return location4SearchQuery
        default: return ""
        }
    }

    private func setCurrentSearchQuery(_ value: String) {
        switch selectedLocationIndex {
        case 0: location1SearchQuery = value
        case 1: location2SearchQuery = value
        case 2: location3SearchQuery = value
        case 3: location4SearchQuery = value
        default: break
        }
    }

    private func getCurrentSearchResults() -> [PlaceSearchResult] {
        switch selectedLocationIndex {
        case 0: return location1SearchResults
        case 1: return location2SearchResults
        case 2: return location3SearchResults
        case 3: return location4SearchResults
        default: return []
        }
    }

    private func setCurrentSearchResults(_ value: [PlaceSearchResult]) {
        switch selectedLocationIndex {
        case 0: location1SearchResults = value
        case 1: location2SearchResults = value
        case 2: location3SearchResults = value
        case 3: location4SearchResults = value
        default: break
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

    private func performSearch(index: Int) {
        let query = getCurrentSearchQuery()
        if !query.isEmpty {
            searchPlace(query: query, index: index)
        }
    }

    private func selectPlace(_ place: PlaceSearchResult, index: Int) {
        switch index {
        case 1:
            location1Address = place.name
            location1Latitude = place.latitude
            location1Longitude = place.longitude
            location1SearchResults = []
            location1SearchQuery = ""
        case 2:
            location2Address = place.name
            location2Latitude = place.latitude
            location2Longitude = place.longitude
            location2SearchResults = []
            location2SearchQuery = ""
        case 3:
            location3Address = place.name
            location3Latitude = place.latitude
            location3Longitude = place.longitude
            location3SearchResults = []
            location3SearchQuery = ""
        case 4:
            location4Address = place.name
            location4Latitude = place.latitude
            location4Longitude = place.longitude
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
        updatedPrefs.location1Latitude = location1Latitude
        updatedPrefs.location1Longitude = location1Longitude

        // Update location 2
        updatedPrefs.location2Address = location2Address.isEmpty ? nil : location2Address
        updatedPrefs.location2Icon = location2Icon
        updatedPrefs.location2Latitude = location2Latitude
        updatedPrefs.location2Longitude = location2Longitude

        // Update location 3
        updatedPrefs.location3Address = location3Address.isEmpty ? nil : location3Address
        updatedPrefs.location3Icon = location3Icon
        updatedPrefs.location3Latitude = location3Latitude
        updatedPrefs.location3Longitude = location3Longitude

        // Update location 4
        updatedPrefs.location4Address = location4Address.isEmpty ? nil : location4Address
        updatedPrefs.location4Icon = location4Icon
        updatedPrefs.location4Latitude = location4Latitude
        updatedPrefs.location4Longitude = location4Longitude

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
            VStack(spacing: 0) {
                // Location Selector with dots
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedLocationIndex = index
                            }
                        }) {
                            VStack(spacing: 12) {
                                Image(systemName: locationIcons[index])
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(selectedLocationIndex == index ? (colorScheme == .dark ? .white : .black) : (colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4)))

                                Text(locationNames[index])
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(selectedLocationIndex == index ? (colorScheme == .dark ? .white : .black) : (colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4)))

                                if selectedLocationIndex == index {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(colorScheme == .dark ? Color.white : Color.black)
                                        .frame(width: 24, height: 3)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .background(colorScheme == .dark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))

                Divider()

                // Location Editor
                ScrollView {
                    VStack(spacing: 24) {
                        // Icon Selector - Horizontal
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Icon")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(LocationType.allCases) { locationType in
                                        Button(action: {
                                            HapticManager.shared.selection()
                                            setCurrentIcon(locationType.icon)
                                        }) {
                                            Image(systemName: locationType.icon)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(getCurrentIcon() == locationType.icon ? .white : (colorScheme == .dark ? .white : .black))
                                                .frame(width: 48, height: 48)
                                                .background(
                                                    Circle()
                                                        .fill(getCurrentIcon() == locationType.icon ? (colorScheme == .dark ? Color.white : Color.black) : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)))
                                                )
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Address Search
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Address")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                                .padding(.horizontal, 16)

                            VStack(spacing: 0) {
                                // Search Field
                                HStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

                                    TextField("Search places", text: .init(
                                        get: { getCurrentSearchQuery() },
                                        set: { newValue in
                                            setCurrentSearchQuery(newValue)
                                        }
                                    ))
                                    .font(.system(size: 16, weight: .regular))
                                    .onSubmit {
                                        performSearch(index: selectedLocationIndex + 1)
                                    }

                                    if !getCurrentSearchQuery().isEmpty {
                                        Button(action: {
                                            HapticManager.shared.selection()
                                            setCurrentSearchQuery("")
                                            setCurrentSearchResults([])
                                        }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                                        }
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))

                                // Selected Address
                                if !getCurrentAddress().isEmpty {
                                    Divider()
                                        .padding(.horizontal, 0)

                                    HStack(spacing: 10) {
                                        Image(systemName: "mappin.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.system(size: 16))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(getCurrentAddress())
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                                .lineLimit(2)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                }
                            }
                            .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                            .cornerRadius(10)
                            .padding(.horizontal, 16)

                            // Search Results
                            if !getCurrentSearchResults().isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(getCurrentSearchResults().prefix(5), id: \.id) { result in
                                        Button(action: {
                                            HapticManager.shared.selection()
                                            selectPlace(result, index: selectedLocationIndex + 1)
                                            setCurrentAddress(result.name)
                                        }) {
                                            HStack(spacing: 12) {
                                                Image(systemName: "mappin")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                                    .frame(width: 24)

                                                VStack(alignment: .leading, spacing: 3) {
                                                    Text(result.name)
                                                        .font(.system(size: 14, weight: .semibold))
                                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                                        .lineLimit(1)

                                                    Text(result.address)
                                                        .font(.system(size: 12, weight: .regular))
                                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                                        .lineLimit(1)
                                                }

                                                Spacer()
                                            }
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 12)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(PlainButtonStyle())

                                        if result.id != getCurrentSearchResults().prefix(5).last?.id {
                                            Divider()
                                                .padding(.horizontal, 14)
                                        }
                                    }
                                }
                                .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                                .cornerRadius(10)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 24)
                }

                Divider()

                // Save Button
                Button(action: {
                    Task {
                        await saveLocations()
                    }
                }) {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text("Save")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        Spacer()
                    }
                    .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                    .padding(.vertical, 14)
                    .background(colorScheme == .dark ? Color.white : Color.black)
                    .cornerRadius(10)
                    .padding(16)
                }
                .disabled(isSaving)
            }
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            location1Address = currentPreferences?.location1Address ?? ""
            location1Icon = currentPreferences?.location1Icon ?? "house.fill"
            location1Latitude = currentPreferences?.location1Latitude
            location1Longitude = currentPreferences?.location1Longitude

            location2Address = currentPreferences?.location2Address ?? ""
            location2Icon = currentPreferences?.location2Icon ?? "briefcase.fill"
            location2Latitude = currentPreferences?.location2Latitude
            location2Longitude = currentPreferences?.location2Longitude

            location3Address = currentPreferences?.location3Address ?? ""
            location3Icon = currentPreferences?.location3Icon ?? "fork.knife"
            location3Latitude = currentPreferences?.location3Latitude
            location3Longitude = currentPreferences?.location3Longitude

            location4Address = currentPreferences?.location4Address ?? ""
            location4Icon = currentPreferences?.location4Icon ?? "mappin.circle.fill"
            location4Latitude = currentPreferences?.location4Latitude
            location4Longitude = currentPreferences?.location4Longitude
        }
    }
}

#Preview {
    AllLocationsEditView(currentPreferences: nil)
}
