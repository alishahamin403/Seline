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

    let cuisineOptions = ["Italian", "Chinese", "Japanese", "Thai", "Indian", "Mexican", "French", "Korean", "Shawarma", "Jamaican", "Pizza", "Burger", "Cafe", "Other"]

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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    // Address
                    Text(restaurant.formattedAddress)
                        .font(.system(size: 12, weight: .regular))
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
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                                Text(String(format: "%.1f", googleRating))
                                    .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 14, weight: .bold))
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                    
                    Text("Rate")
                        .font(.system(size: 9, weight: .medium))
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
            .font(.system(size: 9, weight: .medium))
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
        VStack(spacing: 12) {
            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                .padding(.horizontal, 12)

            ratingSliderView

            cuisineFieldView

            notesFieldView

            saveButtonView
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var ratingSliderView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Rating")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Spacer()

                if let rating = tempRating {
                    HStack(spacing: 3) {
                        Text("\(rating)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(ratingColor(rating))
                        Text("/10")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                } else {
                    Text("Not rated")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
            }

            // Star rating buttons
            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { number in
                    Button(action: {
                        HapticManager.shared.selection()
                        withAnimation(.spring(response: 0.2)) {
                            tempRating = number
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(
                                    tempRating == number 
                                        ? ratingColor(number).opacity(0.2)
                                        : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))
                                )
                                .frame(width: 28, height: 28)
                            
                            if let rating = tempRating, number <= rating {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(ratingColor(rating))
                            } else {
                                Image(systemName: "star")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    private var cuisineFieldView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cuisine")
                .font(.system(size: 12, weight: .semibold))
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
                    HStack(spacing: 6) {
                        Text(tempCuisine ?? "Select cuisine")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            colorScheme == .dark 
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.1),
                            lineWidth: 1
                        )
                )
            }
        }
    }

    private var notesFieldView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            TextEditor(text: $tempNotes)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(minHeight: 70)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            colorScheme == .dark 
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.1),
                            lineWidth: 1
                        )
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
            Text("Save")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black)
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
