import SwiftUI
import CoreLocation

enum LocationSlot {
    case location1
    case location2
    case location3
    case location4
}

enum LocationType: String, CaseIterable, Identifiable {
    case home = "Home"
    case work = "Work"
    case gym = "Gym"
    case restaurant = "Restaurant"
    case park = "Park"
    case shopping = "Shopping"
    case school = "School"
    case hospital = "Hospital"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "briefcase.fill"
        case .gym: return "dumbbell.fill"
        case .restaurant: return "fork.knife"
        case .park: return "tree.fill"
        case .shopping: return "bag.fill"
        case .school: return "graduationcap.fill"
        case .hospital: return "cross.case.fill"
        case .custom: return "mappin.circle.fill"
        }
    }
}

struct LocationEditView: View {
    let locationSlot: LocationSlot
    let currentPreferences: UserLocationPreferences?
    let onSave: (UserLocationPreferences) -> Void

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var googleMapsService = GoogleMapsService.shared

    @State private var searchQuery = ""
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var selectedLocation: PlaceSearchResult?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedLocationType: LocationType

    init(locationSlot: LocationSlot, currentPreferences: UserLocationPreferences?, onSave: @escaping (UserLocationPreferences) -> Void) {
        self.locationSlot = locationSlot
        self.currentPreferences = currentPreferences
        self.onSave = onSave

        // Determine initial location type from current icon
        let currentIcon = Self.getCurrentIcon(slot: locationSlot, preferences: currentPreferences)
        let initialType = LocationType.allCases.first { $0.icon == currentIcon } ?? .home
        _selectedLocationType = State(initialValue: initialType)
    }

    static func getCurrentIcon(slot: LocationSlot, preferences: UserLocationPreferences?) -> String {
        guard let prefs = preferences else {
            switch slot {
            case .location1: return "house.fill"
            case .location2: return "briefcase.fill"
            case .location3: return "fork.knife"
            }
        }
        switch slot {
        case .location1: return prefs.location1Icon ?? "house.fill"
        case .location2: return prefs.location2Icon ?? "briefcase.fill"
        case .location3: return prefs.location3Icon ?? "fork.knife"
        }
    }

    private var title: String {
        selectedLocationType.rawValue
    }

    private var icon: String {
        selectedLocationType.icon
    }

    private var currentAddress: String? {
        guard let prefs = currentPreferences else { return nil }
        switch locationSlot {
        case .location1: return prefs.location1Address
        case .location2: return prefs.location2Address
        case .location3: return prefs.location3Address
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 48))
                        .foregroundColor(colorScheme == .dark ? .gray : .gray.opacity(0.8))

                    Text("Set \(title) Location")
                        .font(.system(size: 24, weight: .bold))

                    if let currentAddress = currentAddress {
                        Text("Current: \(currentAddress)")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 32)

                // Location Type Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Location Type")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(LocationType.allCases) { type in
                                LocationTypeChip(
                                    type: type,
                                    isSelected: selectedLocationType == type,
                                    colorScheme: colorScheme,
                                    onSelect: {
                                        selectedLocationType = type
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                // Search Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Search for address")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(.horizontal, 20)

                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)

                            TextField("Enter \(title.lowercased()) address", text: $searchQuery)
                                .font(.system(size: 14))
                                .onChange(of: searchQuery) { newValue in
                                    // Debounce search
                                    searchTask?.cancel()
                                    searchTask = Task {
                                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                                        if !Task.isCancelled {
                                            await searchLocation(query: newValue)
                                        }
                                    }
                                }

                            if isSearching {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding(12)
                        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                        .cornerRadius(10)

                        // Search Results
                        if !searchResults.isEmpty {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(searchResults.prefix(5)) { result in
                                        Button(action: {
                                            selectedLocation = result
                                            searchResults = []
                                            searchQuery = result.name
                                        }) {
                                            HStack(alignment: .top, spacing: 12) {
                                                Image(systemName: "mappin.circle.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(.gray)

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(result.name)
                                                        .font(.system(size: 13, weight: .medium))
                                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                                    Text(result.address)
                                                        .font(.system(size: 11))
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
                            }
                            .frame(maxHeight: 250)
                            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            .cornerRadius(10)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Selected Location
                    if let selected = selectedLocation {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Location")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(selected.name)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(selected.address)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Button(action: {
                                    selectedLocation = nil
                                    searchQuery = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(12)
                            .background(colorScheme == .dark ? Color.green.opacity(0.2) : Color.green.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button(action: saveLocation) {
                        Text("Save Location")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(selectedLocation != nil ? Color.gray : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .disabled(selectedLocation == nil)

                    if currentAddress != nil {
                        Button(action: removeLocation) {
                            Text("Remove Location")
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Actions

    private func searchLocation(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        await MainActor.run {
            isSearching = true
        }

        do {
            let results = try await googleMapsService.searchPlaces(query: query)
            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        } catch {
            print("❌ Search error: \(error)")
            await MainActor.run {
                isSearching = false
            }
        }
    }

    private func saveLocation() {
        guard let selected = selectedLocation else { return }

        var preferences = currentPreferences ?? UserLocationPreferences()
        preferences.isFirstTimeSetup = false

        switch locationSlot {
        case .location1:
            preferences.location1Address = selected.address
            preferences.location1Latitude = selected.latitude
            preferences.location1Longitude = selected.longitude
            preferences.location1Icon = selectedLocationType.icon
        case .location2:
            preferences.location2Address = selected.address
            preferences.location2Latitude = selected.latitude
            preferences.location2Longitude = selected.longitude
            preferences.location2Icon = selectedLocationType.icon
        case .location3:
            preferences.location3Address = selected.address
            preferences.location3Latitude = selected.latitude
            preferences.location3Longitude = selected.longitude
            preferences.location3Icon = selectedLocationType.icon
        }

        onSave(preferences)
        dismiss()
    }

    private func removeLocation() {
        var preferences = currentPreferences ?? UserLocationPreferences()

        switch locationSlot {
        case .location1:
            preferences.location1Address = nil
            preferences.location1Latitude = nil
            preferences.location1Longitude = nil
            preferences.location1Icon = "house.fill"
        case .location2:
            preferences.location2Address = nil
            preferences.location2Latitude = nil
            preferences.location2Longitude = nil
            preferences.location2Icon = "briefcase.fill"
        case .location3:
            preferences.location3Address = nil
            preferences.location3Latitude = nil
            preferences.location3Longitude = nil
            preferences.location3Icon = "fork.knife"
        }

        onSave(preferences)
        dismiss()
    }
}

// MARK: - Location Type Chip Component

struct LocationTypeChip: View {
    let type: LocationType
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 12, weight: .medium))

                Text(type.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ?
                    (colorScheme == .dark ?
                        Color.white :
                        Color.black) :
                    (colorScheme == .dark ?
                        Color.white.opacity(0.08) :
                        Color.black.opacity(0.05))
            )
            .foregroundColor(
                isSelected ?
                    .white :
                    (colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
            )
            .cornerRadius(20)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    LocationEditView(
        locationSlot: .location1,
        currentPreferences: nil,
        onSave: { _ in }
    )
}
