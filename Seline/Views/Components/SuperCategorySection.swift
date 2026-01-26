import SwiftUI
import CoreLocation

struct SuperCategorySection: View {
    let superCategory: LocationSuperCategory
    let groupedPlaces: [String: [SavedPlace]]
    @Binding var expandedCategories: Set<String>
    let colorScheme: ColorScheme
    let currentLocation: CLLocation?
    let onPlaceTap: (SavedPlace) -> Void
    let onRatingTap: (SavedPlace) -> Void
    let onMoveToFolder: ((SavedPlace) -> Void)?
    
    @StateObject private var locationsManager = LocationsManager.shared
    
    private var sortedCategories: [String] {
        groupedPlaces.keys.sorted()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Super-category header with icon
            HStack(spacing: 8) {
                Image(systemName: superCategory.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                
                Text(superCategory.rawValue)
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Categories within this super-category
            VStack(spacing: 0) {
                ForEach(sortedCategories, id: \.self) { category in
                    if let places = groupedPlaces[category] {
                        RatableCategoryRow(
                            category: category,
                            places: places,
                            isExpanded: expandedCategories.contains(category),
                            isRatable: superCategory.isRatable,
                            currentLocation: currentLocation,
                            colorScheme: colorScheme,
                            onToggle: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    if expandedCategories.contains(category) {
                                        expandedCategories.remove(category)
                                    } else {
                                        expandedCategories.insert(category)
                                    }
                                }
                                HapticManager.shared.light()
                            },
                            onPlaceTap: onPlaceTap,
                            onRatingTap: onRatingTap,
                            onMoveToFolder: onMoveToFolder
                        )
                    }
                }
            }
        }
        .shadcnTileStyle(colorScheme: colorScheme)
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
    }
}

#Preview {
    SuperCategorySectionPreview()
}

struct SuperCategorySectionPreview: View {
    @State private var expandedCategories = Set(["Restaurants"])
    
    var body: some View {
        SuperCategorySection(
            superCategory: LocationSuperCategory.foodAndDining,
            groupedPlaces: [
                "Restaurants": [
                    SavedPlace(
                        googlePlaceId: "test1",
                        name: "Test Restaurant",
                        address: "123 Main St, Toronto, ON, Canada",
                        latitude: 43.6532,
                        longitude: -79.3832
                    )
                ]
            ],
            expandedCategories: $expandedCategories,
            colorScheme: ColorScheme.dark,
            currentLocation: nil,
            onPlaceTap: { _ in },
            onRatingTap: { _ in },
            onMoveToFolder: nil
        )
        .background(Color.black)
    }
}
