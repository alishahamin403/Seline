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

    let cuisineOptions = ["Italian", "Chinese", "Japanese", "Thai", "Indian", "Mexican", "French", "Korean", "Pizza", "Burger", "Cafe", "Other"]

    var body: some View {
        VStack(spacing: 0) {
            collapsedCardView

            if isExpanded {
                expandedEditView
            }
        }
        .background(cardBackground)
        .overlay(cardBorder)
    }

    private var collapsedCardView: some View {
        HStack(spacing: 12) {
            restaurantInfoView
                .frame(maxWidth: .infinity, alignment: .leading)

            ratingColumnView
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    isExpanded = false
                } else {
                    tempRating = restaurant.userRating
                    tempNotes = restaurant.userNotes ?? ""
                    tempCuisine = restaurant.userCuisine
                    isExpanded = true
                }
            }
        }
    }

    private var restaurantInfoView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(restaurant.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(1)

            Text(restaurant.formattedAddress)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var ratingColumnView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let userRating = restaurant.userRating {
                Text("\(userRating)/10")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            } else {
                Text("—")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
            }

            if let rating = restaurant.rating {
                HStack(spacing: 2) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }
        }
    }

    private var expandedEditView: some View {
        VStack(spacing: 12) {
            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

            ratingSliderView

            cuisineFieldView

            notesFieldView

            saveButtonView
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var ratingSliderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your Rating")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                Spacer()

                if let rating = tempRating {
                    Text("\(rating)/10")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                } else {
                    Text("Not rated")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
            }

            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { number in
                    Button(action: {
                        tempRating = number
                    }) {
                        if let rating = tempRating, number <= rating {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                        } else {
                            Image(systemName: "star")
                                .font(.system(size: 12))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                        }
                    }
                }
            }
        }
    }

    private var cuisineFieldView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cuisine")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                Spacer()

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
                    HStack(spacing: 4) {
                        Text(tempCuisine ?? "Select cuisine")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                colorScheme == .dark ?
                                    Color.white.opacity(0.05) : Color.gray.opacity(0.05)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                colorScheme == .dark ?
                                    Color.white.opacity(0.1) : Color.gray.opacity(0.1),
                                lineWidth: 1
                            )
                    )
                }
            }
        }
    }

    private var notesFieldView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

            TextEditor(text: $tempNotes)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(minHeight: 60)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            colorScheme == .dark ?
                                Color.white.opacity(0.05) : Color.gray.opacity(0.05)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            colorScheme == .dark ?
                                Color.white.opacity(0.1) : Color.gray.opacity(0.1),
                            lineWidth: 1
                        )
                )
        }
    }

    private var saveButtonView: some View {
        Button(action: {
            onRatingUpdate(tempRating, tempNotes.isEmpty ? nil : tempNotes, tempCuisine)
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = false
            }
        }) {
            Text("Save")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.2, green: 0.2, blue: 0.2))
                )
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                colorScheme == .dark ?
                    Color.white.opacity(0.05) : Color.gray.opacity(0.05)
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                colorScheme == .dark ?
                    Color.white.opacity(0.1) : Color.gray.opacity(0.1),
                lineWidth: 1
            )
    }
}

#Preview {
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
        onRatingUpdate: { _, _ in }
    )
}
