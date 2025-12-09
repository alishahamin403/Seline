import SwiftUI

struct LocationDetailView: View {
    let placeDetails: PlaceDetails?
    let googlePlaceId: String
    @StateObject private var locationsManager = LocationsManager.shared
    @StateObject private var openAIService = DeepSeekService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @State private var selectedCategory: String = "Uncategorized"
    @State private var isSaving = false
    @State private var showCategoryPicker = false
    @State private var selectedPhotoIndex = 0

    var isSaved: Bool {
        locationsManager.isPlaceSaved(googlePlaceId: googlePlaceId)
    }

    var body: some View {
        if let placeDetails = placeDetails {
            loadedContentView(placeDetails: placeDetails)
                .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                .sheet(isPresented: $showCategoryPicker) {
                    CategoryPickerView(
                        selectedCategory: $selectedCategory,
                        onSave: { category in
                            savePlace(placeDetails: placeDetails, category: category)
                            showCategoryPicker = false
                        }
                    )
                    .presentationBg()
                }
        } else {
            loadingView
                .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(colorScheme == .dark ? Color.white : Color.black)

            Text("Loading location details...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loaded Content View

    @ViewBuilder
    private func loadedContentView(placeDetails: PlaceDetails) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Photo Gallery
                if !placeDetails.photoURLs.isEmpty {
                    TabView(selection: $selectedPhotoIndex) {
                        ForEach(Array(placeDetails.photoURLs.enumerated()), id: \.offset) { index, photoURL in
                            CachedAsyncImage(url: photoURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .overlay(
                                        ProgressView()
                                    )
                            }
                            .frame(height: 300)
                            .clipped()
                            .tag(index)
                        }
                    }
                    .frame(height: 300)
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 200)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                        )
                }

                // Content
                VStack(alignment: .leading, spacing: 20) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(placeDetails.name)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            Spacer()

                            if let isOpen = placeDetails.isOpenNow {
                                Text(isOpen ? "Open" : "Closed")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(isOpen ? .green : .red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill((isOpen ? Color.green : Color.red).opacity(0.2))
                                    )
                            }
                        }

                        // Rating
                        if let rating = placeDetails.rating {
                            HStack(spacing: 4) {
                                ForEach(0..<5) { index in
                                    Image(systemName: index < Int(rating.rounded()) ? "star.fill" : "star")
                                        .font(.system(size: 14))
                                        .foregroundColor(.yellow)
                                }
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                Text("(\(placeDetails.totalRatings) reviews)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }

                        // Price Level
                        if let priceLevel = placeDetails.priceLevel {
                            HStack(spacing: 2) {
                                ForEach(0..<priceLevel, id: \.self) { _ in
                                    Text("$")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.green)
                                }
                                ForEach(0..<(4 - priceLevel), id: \.self) { _ in
                                    Text("$")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray.opacity(0.3))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Divider()
                        .padding(.horizontal, 20)

                    // Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        InfoRow(icon: "mappin.circle.fill", text: placeDetails.address)

                        if let phone = placeDetails.phone {
                            Button(action: {
                                if let url = URL(string: "tel://\(phone)") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                InfoRow(icon: "phone.fill", text: phone)
                            }
                        }

                        if let website = placeDetails.website {
                            Button(action: {
                                if let url = URL(string: website) {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                InfoRow(icon: "globe", text: "Visit Website")
                            }
                        }

                        // Get Directions Button
                        Button(action: {
                            openDirections()
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                            Color.white :
                                            Color.black
                                    )
                                    .frame(width: 24)

                                Text("Get Directions")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                            Color.white :
                                            Color.black
                                    )

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // Opening Hours
                    if !placeDetails.openingHours.isEmpty {
                        Divider()
                            .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Opening Hours")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(placeDetails.openingHours, id: \.self) { hours in
                                    Text(hours)
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Reviews Section
                    if !placeDetails.reviews.isEmpty {
                        Divider()
                            .padding(.horizontal, 20)

                        VStack(alignment: .leading, spacing: 16) {
                            Text("Reviews")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.horizontal, 20)

                            ForEach(placeDetails.reviews) { review in
                                ReviewCard(review: review, colorScheme: colorScheme)
                            }
                        }
                    }

                    Spacer()
                        .frame(height: 100)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .overlay(alignment: .bottom) {
            // Save Button
            VStack(spacing: 0) {
                Divider()

                if isSaved {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                        Text("Saved to \(getSavedCategory())")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                } else {
                    Button(action: {
                        showCategoryPicker = true
                    }) {
                        HStack {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 18))
                            Text(isSaving ? "Saving..." : "Save to Category")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    colorScheme == .dark ?
                                        Color.white :
                                        Color.black
                                )
                        )
                    }
                    .disabled(isSaving)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func getSavedCategory() -> String {
        if let place = locationsManager.savedPlaces.first(where: { $0.googlePlaceId == googlePlaceId }) {
            return place.category
        }
        return "Unknown"
    }

    private func savePlace(placeDetails: PlaceDetails, category: String) {
        isSaving = true

        Task {
            // Create SavedPlace
            var place = placeDetails.toSavedPlace(googlePlaceId: googlePlaceId)
            place.category = category

            // Save to manager
            await MainActor.run {
                locationsManager.addPlace(place)
                isSaving = false
            }

            print("✅ Place saved: \(place.name) - Category: \(category)")
        }
    }

    private func openDirections() {
        guard let placeDetails = placeDetails else { return }

        let latitude = placeDetails.latitude
        let longitude = placeDetails.longitude
        let _ = placeDetails.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Try Google Maps app first
        let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(latitude),\(longitude)&directionsmode=driving")
        let appleMapsURL = URL(string: "http://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=d")

        if let googleMapsURL = googleMapsURL, UIApplication.shared.canOpenURL(googleMapsURL) {
            UIApplication.shared.open(googleMapsURL)
            print("✅ Opened directions in Google Maps")
        } else if let appleMapsURL = appleMapsURL {
            UIApplication.shared.open(appleMapsURL)
            print("✅ Opened directions in Apple Maps")
        } else {
            print("❌ Could not open maps for directions")
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let text: String
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(
                    colorScheme == .dark ?
                        Color.white :
                        Color.black
                )
                .frame(width: 24)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black)

            Spacer()
        }
    }
}

// MARK: - Review Card

struct ReviewCard: View {
    let review: PlaceReview
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Profile photo or initial
                if let photoUrl = review.profilePhotoUrl, let url = URL(string: photoUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(review.authorName.prefix(1)))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.gray)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(review.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            ForEach(0..<review.rating, id: \.self) { _ in
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.yellow)
                            }
                            ForEach(0..<(5 - review.rating), id: \.self) { _ in
                                Image(systemName: "star")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray)
                            }
                        }

                        if let time = review.relativeTime {
                            Text("• \(time)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                    }
                }

                Spacer()
            }

            Text(review.text)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                .lineLimit(4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Category Picker View

struct CategoryPickerView: View {
    @Binding var selectedCategory: String
    let onSave: (String) -> Void
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var locationsManager = LocationsManager.shared
    @State private var customCategory = ""
    @State private var showCustomInput = false

    var predefinedCategories = ["Restaurants", "Coffee Shops", "Shopping", "Entertainment", "Health & Fitness", "Travel", "Services"]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        // Existing categories from saved places
                        if !locationsManager.categories.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your Categories")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 20)

                                ForEach(Array(locationsManager.categories), id: \.self) { category in
                                    CategoryButton(
                                        title: category,
                                        isSelected: selectedCategory == category,
                                        colorScheme: colorScheme
                                    ) {
                                        selectedCategory = category
                                    }
                                }
                            }
                            .padding(.top, 20)
                        }

                        // Predefined categories
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested Categories")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.gray)
                                .padding(.horizontal, 20)

                            ForEach(predefinedCategories, id: \.self) { category in
                                if !locationsManager.categories.contains(category) {
                                    CategoryButton(
                                        title: category,
                                        isSelected: selectedCategory == category,
                                        colorScheme: colorScheme
                                    ) {
                                        selectedCategory = category
                                    }
                                }
                            }
                        }
                        .padding(.top, 20)

                        // Custom category
                        Button(action: {
                            showCustomInput = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 18))
                                Text("Create New Category")
                                    .font(.system(size: 16, weight: .medium))
                                Spacer()
                            }
                            .foregroundColor(
                                colorScheme == .dark ?
                                    Color.white :
                                    Color.black
                            )
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
                            )
                            .padding(.horizontal, 20)
                        }
                        .padding(.top, 12)
                    }
                }

                // Save Button
                VStack(spacing: 0) {
                    Divider()

                    Button(action: {
                        onSave(selectedCategory)
                        dismiss()
                    }) {
                        Text("Save to \(selectedCategory)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        colorScheme == .dark ?
                                            Color.white :
                                            Color.black
                                    )
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                }
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle("Select Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Create Category", isPresented: $showCustomInput) {
            TextField("Category name", text: $customCategory)
            Button("Cancel", role: .cancel) { }
            Button("Create") {
                if !customCategory.isEmpty {
                    selectedCategory = customCategory
                    customCategory = ""
                }
            }
        }
    }
}

struct CategoryButton: View {
    let title: String
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(
                        isSelected ?
                            (colorScheme == .dark ? .black : .white) :
                            (colorScheme == .dark ? .white : .black)
                    )

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected ?
                            (colorScheme == .dark ?
                                Color.white :
                                Color.black) :
                            (colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
                    )
            )
            .padding(.horizontal, 20)
        }
    }
}
