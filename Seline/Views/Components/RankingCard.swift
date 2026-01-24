import SwiftUI

struct RankingCard: View {
    let restaurant: SavedPlace
    let colorScheme: ColorScheme
    let onRatingUpdate: (Int?, String?, String?) -> Void

    @State private var isExpanded = false
    @State private var tempRating: Int? = nil
    @State private var tempNotes: String = ""
    @State private var tempCuisine: String? = nil
    @State private var showCuisineMenu = false

    let cuisineOptions = [
        "American", "BBQ", "Burger", "Cafe", "Caribbean", "Chinese", "French", 
        "Greek", "Indian", "Italian", "Jamaican", "Japanese", "Korean", 
        "Mediterranean", "Mexican", "Middle Eastern", "Pakistani", "Pizza", 
        "Seafood", "Thai", "Turkish", "Vegetarian", "Vietnamese", "Other"
    ]

    var body: some View {
        VStack(spacing: 0) {
            collapsedCardView

            if isExpanded {
                expandedEditView
            }
        }
        .shadcnTileStyle(colorScheme: colorScheme)
    }

    private var collapsedCardView: some View {
        Button(action: {
            HapticManager.shared.light()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if isExpanded {
                    isExpanded = false
                } else {
                    tempRating = restaurant.userRating
                    tempNotes = restaurant.userNotes ?? ""
                    tempCuisine = restaurant.userCuisine
                    isExpanded = true
                }
            }
        }) {
            HStack(spacing: 12) {
                // Place image/thumbnail
                PlaceImageView(place: restaurant, size: 48, cornerRadius: 10)
                
                // Restaurant info
                VStack(alignment: .leading, spacing: 4) {
                    Text(restaurant.displayName)
                        .font(FontManager.geist(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Address
                    Text(restaurant.formattedAddress)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                        .lineLimit(1)
                    
                    // Cuisine tag and Google rating
                    HStack(spacing: 6) {
                        if let cuisine = restaurant.userCuisine {
                            cuisineTag(cuisine)
                        }
                        
                        if let googleRating = restaurant.rating {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(FontManager.geist(size: 9, weight: .regular))
                                    .foregroundColor(.orange)
                                Text(String(format: "%.1f", googleRating))
                                    .font(FontManager.geist(size: 10, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                // Rating badge
                ratingBadge
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var ratingBadge: some View {
        Group {
            if let userRating = restaurant.userRating {
                Text("\(userRating)/10")
                    .font(FontManager.geist(size: 14, weight: .bold))
                    .foregroundColor(ratingColor(userRating))
                    .frame(width: 50)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(ratingColor(userRating).opacity(0.15))
                    )
            } else {
                VStack(spacing: 3) {
                    Image(systemName: "star")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                    
                    Text("Rate")
                        .font(FontManager.geist(size: 9, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                }
                .frame(width: 44)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                )
            }
        }
    }
    
    private func cuisineTag(_ cuisine: String) -> some View {
        Text(cuisine)
            .font(FontManager.geist(size: 9, weight: .medium))
            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
            )
    }
    
    private func ratingColor(_ rating: Int) -> Color {
        if rating >= 8 {
            return Color.green
        } else if rating >= 5 {
            return Color.orange
        } else {
            return Color.red
        }
    }

    private var expandedEditView: some View {
        VStack(spacing: 20) {
            ratingSliderView
            cuisineFieldView
            notesFieldView
            saveButtonView
        }
        .padding(16)
        .padding(.bottom, 4)
    }

    private var ratingSliderView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Rating")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Spacer()
                if let rating = tempRating {
                    Text("\(rating)/10")
                        .font(FontManager.geist(size: 14, weight: .bold))
                        .foregroundColor(ratingColor(rating))
                } else {
                    Text("Tap to rate")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }

            // Star rating container
            HStack(spacing: 8) {
                ForEach(1...10, id: \.self) { number in
                    Button(action: {
                        HapticManager.shared.selection()
                        withAnimation(.spring(response: 0.2)) {
                            tempRating = number
                        }
                    }) {
                        Image(systemName: (tempRating ?? 0) >= number ? "star.fill" : "star")
                            .font(FontManager.geist(size: (tempRating ?? 0) >= number ? 14 : 12, systemWeight: .medium))
                            .foregroundColor((tempRating ?? 0) >= number ? ratingColor(tempRating ?? 0) : (colorScheme == .dark ? .white.opacity(0.2) : .black.opacity(0.2)))
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
        }
    }

    private var cuisineFieldView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cuisine")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Menu {
                Button(action: {
                    tempCuisine = nil
                }) {
                    HStack {
                        Text("Clear")
                        if tempCuisine == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                ForEach(cuisineOptions, id: \.self) { cuisine in
                    Button(action: {
                        tempCuisine = cuisine
                    }) {
                        HStack {
                            Text(cuisine)
                            if tempCuisine == cuisine {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(tempCuisine ?? "Select Cuisine")
                        .font(FontManager.geist(size: 14, systemWeight: tempCuisine == nil ? .regular : .medium))
                        .foregroundColor(tempCuisine == nil ? (colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)) : (colorScheme == .dark ? .white : .black))

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                )
            }
        }
    }

    private var notesFieldView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            ZStack(alignment: .topLeading) {
                if tempNotes.isEmpty {
                    Text("Add your personal notes here...")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                
                TextEditor(text: $tempNotes)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .frame(minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
        }
    }

    private var saveButtonView: some View {
        Button(action: {
            HapticManager.shared.selection()
            onRatingUpdate(tempRating, tempNotes.isEmpty ? nil : tempNotes, tempCuisine)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded = false
            }
        }) {
            Text("Save Changes")
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black)
                )
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RankingCard(
            restaurant: SavedPlace(
                googlePlaceId: "test",
                name: "Test Restaurant",
                address: "123 Main St, Toronto, Ontario, Canada",
                latitude: 43.6532,
                longitude: -79.3832,
                rating: 4.5
            ),
            colorScheme: .dark,
            onRatingUpdate: { _, _, _ in }
        )
        .padding()
    }
    .background(Color.black)
}
