import SwiftUI

struct CuisineFilterView: View {
    @Binding var selectedCuisines: Set<String>
    let colorScheme: ColorScheme

    private let cuisines = [
        "American", "BBQ", "Burger", "Cafe", "Caribbean", "Chinese",
        "French", "Greek", "Indian", "Italian", "Japanese", "Korean",
        "Mediterranean", "Mexican", "Middle Eastern", "Pakistani",
        "Pizza", "Seafood", "Thai", "Turkish", "Vegetarian", "Vietnamese"
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(cuisines, id: \.self) { cuisine in
                    CuisineChip(
                        cuisine: cuisine,
                        isSelected: selectedCuisines.contains(cuisine),
                        colorScheme: colorScheme,
                        onTap: { toggleCuisine(cuisine) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func toggleCuisine(_ cuisine: String) {
        HapticManager.shared.selection()
        if selectedCuisines.contains(cuisine) {
            selectedCuisines.remove(cuisine)
        } else {
            selectedCuisines.insert(cuisine)
        }
    }
}

struct CuisineChip: View {
    let cuisine: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(cuisine)
                .font(FontManager.geist(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : (colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
