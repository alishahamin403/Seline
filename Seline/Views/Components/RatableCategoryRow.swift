import SwiftUI
import CoreLocation

struct RatableCategoryRow: View {
    let category: String
    let places: [SavedPlace]
    let isExpanded: Bool
    let isRatable: Bool
    let currentLocation: CLLocation?
    let colorScheme: ColorScheme
    let onToggle: () -> Void
    let onPlaceTap: (SavedPlace) -> Void
    let onRatingTap: (SavedPlace) -> Void
    let onMoveToFolder: ((SavedPlace) -> Void)?
    
    @StateObject private var locationsManager = LocationsManager.shared
    @State private var showingRenameAlert = false
    @State private var selectedPlace: SavedPlace? = nil
    @State private var newPlaceName = ""
    @State private var showingRenameFolderAlert = false
    @State private var newFolderName = ""
    
    // Rating statistics
    private var ratedPlaces: [SavedPlace] {
        places.filter { $0.userRating != nil }
    }
    
    private var unratedPlaces: [SavedPlace] {
        places.filter { $0.userRating == nil }
    }
    
    private var averageRating: Double {
        guard !ratedPlaces.isEmpty else { return 0 }
        let sum = ratedPlaces.compactMap { $0.userRating }.reduce(0, +)
        return Double(sum) / Double(ratedPlaces.count)
    }
    
    private var ratingSummaryColor: Color {
        if averageRating >= 8 {
            return .green
        } else if averageRating >= 5 {
            return .primary
        } else {
            return .blue
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category header (tap to expand, long press to rename)
            HStack(spacing: 12) {
                Text(category)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                // Count badge with rated count
                HStack(spacing: 4) {
                    // Total count
                    Text("\(places.count)")
                        .font(FontManager.geist(size: 12, weight: .semibold))

                    // Rated count (if applicable and has ratings)
                    if isRatable && !ratedPlaces.isEmpty {
                        Text("•")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                        Text("\(ratedPlaces.count)")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(ratingSummaryColor)
                    }
                }
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(minWidth: 24, minHeight: 24)
                .padding(.horizontal, 6)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                )
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .onTapGesture {
                onToggle()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                HapticManager.shared.selection()
                newFolderName = category
                showingRenameFolderAlert = true
            }
            
            // Places list
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .opacity(0.3)
                    
                    ForEach(places) { place in
                        placeRow(for: place)
                        
                        // Divider between places
                        if place.id != places.last?.id {
                            Divider()
                                .padding(.horizontal, 16)
                                .opacity(0.2)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .alert("Rename Place", isPresented: $showingRenameAlert) {
            TextField("Place name", text: $newPlaceName)
            Button("Cancel", role: .cancel) {
                selectedPlace = nil
                newPlaceName = ""
            }
            Button("Rename") {
                if let place = selectedPlace {
                    var updatedPlace = place
                    updatedPlace.customName = newPlaceName.trimmingCharacters(in: .whitespacesAndNewlines)
                    locationsManager.updatePlace(updatedPlace)
                    selectedPlace = nil
                    newPlaceName = ""
                }
            }
        } message: {
            Text("Enter a new name for this place")
        }
        .alert(places.isEmpty ? "Manage Folder" : "Rename Folder", isPresented: $showingRenameFolderAlert) {
            TextField("Folder name", text: $newFolderName)
            if places.isEmpty {
                Button("Delete", role: .destructive) {
                    locationsManager.removeUserFolder(category)
                    newFolderName = ""
                }
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
            Button("Rename") {
                locationsManager.renameCategory(category, to: newFolderName)
                newFolderName = ""
            }
        } message: {
            Text(places.isEmpty ? "Rename or delete this folder" : "Enter a new name for this folder")
        }
    }
    
    // MARK: - Rating Summary Pills
    
    private var ratingSummaryPill: some View {
        HStack(spacing: 4) {
            Text(String(format: "Avg %.1f", averageRating))
                .font(FontManager.geist(size: 11, weight: .medium))
            Text("•")
            Text("\(ratedPlaces.count) rated")
                .font(FontManager.geist(size: 11, weight: .medium))
        }
        .foregroundColor(ratingSummaryColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(ratingSummaryColor.opacity(0.15))
        )
    }
    
    private var unratedSummaryPill: some View {
        Text("\(unratedPlaces.count) need rating")
            .font(FontManager.geist(size: 11, weight: .medium))
            .foregroundColor(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.15))
            )
    }
    
    // MARK: - Place Row
    
    private func placeRow(for place: SavedPlace) -> some View {
        Button(action: {
            onPlaceTap(place)
        }) {
            HStack(spacing: 12) {
                PlaceImageView(place: place, size: 52, cornerRadius: 12)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(place.displayName)
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)

                        if place.isFavourite {
                            Image(systemName: "star.fill")
                                .font(FontManager.geist(size: 11, weight: .semibold))
                                .foregroundColor(.yellow)
                        }
                    }

                    if let distance = calculateDistance(to: place) {
                        Text(formatDistance(distance))
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                    }
                }
                
                Spacer()
                
                // Rating badge (only if ratable)
                if isRatable && !isPersonalLocation(place) {
                    ratingBadge(for: place)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 0)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                locationsManager.toggleFavourite(for: place.id)
                HapticManager.shared.selection()
            }) {
                Label(
                    place.isFavourite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: place.isFavourite ? "star.slash" : "star.fill"
                )
            }
            
            Button(action: {
                selectedPlace = place
                newPlaceName = place.customName ?? place.name
                showingRenameAlert = true
            }) {
                Label("Rename", systemImage: "pencil")
            }
            
            if onMoveToFolder != nil {
                Button(action: {
                    onMoveToFolder?(place)
                }) {
                    Label("Move to Folder", systemImage: "folder")
                }
            }
            
            Button(role: .destructive, action: {
                locationsManager.deletePlace(place)
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Rating Badge
    
    private func ratingBadge(for place: SavedPlace) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            onRatingTap(place)
        }) {
            Group {
                if let userRating = place.userRating {
                    // Rated - show rating with star
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(FontManager.geist(size: 10, weight: .medium))
                            .foregroundColor(ratingColor(userRating))
                        Text("\(userRating)")
                            .font(FontManager.geist(size: 13, weight: .bold))
                            .foregroundColor(ratingColor(userRating))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ratingColor(userRating).opacity(0.15))
                    )
                } else {
                    // Unrated - show "Rate" prompt
                    VStack(spacing: 2) {
                        Image(systemName: "star")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                        
                        Text("Rate")
                            .font(FontManager.geist(size: 9, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                    }
                    .frame(width: 44)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                    )
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func ratingColor(_ rating: Int) -> Color {
        if rating >= 8 {
            return Color.green
        } else if rating >= 5 {
            return Color.primary
        } else {
            return Color.red
        }
    }
    
    // MARK: - Helper Functions
    
    private func calculateDistance(to place: SavedPlace) -> CLLocationDistance? {
        guard let currentLocation = currentLocation else { return nil }
        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return currentLocation.distance(from: placeLocation)
    }
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    private func isPersonalLocation(_ place: SavedPlace) -> Bool {
        let lower = place.category.lowercased()
        return lower.contains("home") || lower.contains("work") || lower.contains("office") || lower.contains("house")
    }
}

#Preview {
    VStack {
        RatableCategoryRow(
            category: "Restaurants",
            places: [
                SavedPlace(
                    googlePlaceId: "test1",
                    name: "Test Restaurant",
                    address: "123 Main St, Toronto, ON, Canada",
                    latitude: 43.6532,
                    longitude: -79.3832
                )
            ],
            isExpanded: true,
            isRatable: true,
            currentLocation: nil,
            colorScheme: .dark,
            onToggle: {},
            onPlaceTap: { _ in },
            onRatingTap: { _ in },
            onMoveToFolder: nil
        )
    }
    .padding()
    .background(Color.black)
}
