import SwiftUI

struct RatingEditorSheet: View {
    let place: SavedPlace
    let colorScheme: ColorScheme
    let onSave: (Int?, String?, String?) -> Void
    let onDismiss: () -> Void
    
    @State private var tempRating: Int? = nil
    @State private var tempNotes: String = ""
    @State private var tempCuisine: String? = nil
    
    let cuisineOptions = [
        "American", "BBQ", "Burger", "Cafe", "Caribbean", "Chinese", "French",
        "Greek", "Indian", "Italian", "Jamaican", "Japanese", "Korean",
        "Mediterranean", "Mexican", "Middle Eastern", "Pakistani", "Pizza",
        "Seafood", "Thai", "Turkish", "Vegetarian", "Vietnamese", "Other"
    ]
    
    // Check if this is a food-related place
    private var isFoodPlace: Bool {
        let lower = place.category.lowercased()
        return lower.contains("restaurant") || lower.contains("cafe") || lower.contains("food") ||
               lower.contains("dining") || lower.contains("pizza") || lower.contains("burger")
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Place header
                    placeHeaderView
                    
                    // Rating slider
                    ratingSliderView
                    
                    // Cuisine selector (only for food places)
                    if isFoodPlace {
                        cuisineFieldView
                    }
                    
                    // Notes field
                    notesFieldView
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .background(
                (colorScheme == .dark ? Color.black : Color.white)
                    .ignoresSafeArea()
            )
            .navigationTitle("Rate Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        HapticManager.shared.selection()
                        onSave(tempRating, tempNotes.isEmpty ? nil : tempNotes, tempCuisine)
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // Initialize with current values
            tempRating = place.userRating
            tempNotes = place.userNotes ?? ""
            tempCuisine = place.userCuisine
        }
    }
    
    // MARK: - Place Header
    
    private var placeHeaderView: some View {
        HStack(spacing: 12) {
            PlaceImageView(place: place, size: 60, cornerRadius: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(place.displayName)
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(2)
                
                Text(place.formattedAddress)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    // MARK: - Rating Slider
    
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
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    // MARK: - Cuisine Field
    
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
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    // MARK: - Notes Field
    
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
            .frame(minHeight: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
        }
        .padding(16)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    // MARK: - Helper Functions
    
    private func ratingColor(_ rating: Int) -> Color {
        if rating >= 8 {
            return Color.green
        } else if rating >= 5 {
            return Color.orange
        } else {
            return Color.red
        }
    }
}

#Preview {
    RatingEditorSheet(
        place: SavedPlace(
            googlePlaceId: "test",
            name: "Test Restaurant",
            address: "123 Main St, Toronto, ON, Canada",
            latitude: 43.6532,
            longitude: -79.3832,
            rating: 4.5
        ),
        colorScheme: .dark,
        onSave: { _, _, _ in },
        onDismiss: {}
    )
    .preferredColorScheme(.dark)
}
