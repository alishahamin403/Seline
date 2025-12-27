import SwiftUI

struct SavedPlaceRow: View {
    let place: SavedPlace
    let onTap: (SavedPlace) -> Void
    let onDelete: (SavedPlace) -> Void
    @StateObject private var locationsManager = LocationsManager.shared
    @Environment(\.colorScheme) var colorScheme
    @State private var showEditSheet = false
    @State private var isFavourite: Bool

    var body: some View {
        Button(action: {
            onTap(place)
        }) {
            HStack(spacing: 12) {
                // Location image or initials
                PlaceImageView(place: place, size: 56, cornerRadius: 8)

                // Place info
                VStack(alignment: .leading, spacing: 4) {
                    // Name and category
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            // Display name (custom or original)
                            Text(place.displayName)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(1)

                            // Show original name if custom name exists
                            if place.customName != nil {
                                Text(place.name)
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        // Category badge
                        Text(place.category)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(
                                colorScheme == .dark ?
                                    Color(red: 0.518, green: 0.792, blue: 0.914) :
                                    Color.black
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        colorScheme == .dark ?
                                            Color(red: 0.518, green: 0.792, blue: 0.914).opacity(0.2) :
                                            Color.black.opacity(0.1)
                                    )
                            )
                    }

                    // Address (always visible)
                    Text(place.formattedAddress)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // Rating if available
                    if let rating = place.rating {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)

                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                locationsManager.toggleFavourite(for: place.id)
                isFavourite.toggle()
            }) {
                Label(isFavourite ? "Remove from Favourites" : "Add to Favourites", systemImage: isFavourite ? "star.fill" : "star")
            }

            Button(action: {
                showEditSheet = true
            }) {
                Label("Rename", systemImage: "pencil")
            }

            Button(role: .destructive, action: {
                onDelete(place)
            }) {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditPlaceNameSheet(place: place)
        }
    .presentationBg()
        .onAppear {
            isFavourite = place.isFavourite
        }
    }

    init(place: SavedPlace, onTap: @escaping (SavedPlace) -> Void, onDelete: @escaping (SavedPlace) -> Void) {
        self.place = place
        self.onTap = onTap
        self.onDelete = onDelete
        _isFavourite = State(initialValue: place.isFavourite)
    }
}

// MARK: - Edit Place Name Sheet

struct EditPlaceNameSheet: View {
    let place: SavedPlace
    @StateObject private var locationsManager = LocationsManager.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var customName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Name")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                    TextField("Enter a custom name...", text: $customName)
                        .font(.system(size: 16))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.gray.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    colorScheme == .dark ?
                                        Color.white.opacity(0.1) : Color.black.opacity(0.1),
                                    lineWidth: 1
                                )
                        )
                        .focused($isTextFieldFocused)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Original Name")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                    Text(place.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.black.opacity(0.2) : Color.gray.opacity(0.05))
                        )
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Address")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

                    Text(place.address)
                        .font(.system(size: 14))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color.black.opacity(0.2) : Color.gray.opacity(0.05))
                        )
                }
                .padding(.horizontal, 20)

                Spacer()

                // Save Button
                Button(action: {
                    saveCustomName()
                }) {
                    Text("Save")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
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
                .padding(.bottom, 20)
            }
            .background(
                (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                    .ignoresSafeArea()
            )
            .navigationTitle("Rename Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if !customName.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            customName = ""
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .onAppear {
                customName = place.customName ?? ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isTextFieldFocused = true
                }
            }
        }
    }

    private func saveCustomName() {
        var updatedPlace = place
        updatedPlace.customName = customName.isEmpty ? nil : customName
        locationsManager.updatePlace(updatedPlace)
        dismiss()
    }
}

#Preview {
    VStack(spacing: 0) {
        SavedPlaceRow(
            place: SavedPlace(
                googlePlaceId: "test1",
                name: "Blue Bottle Coffee",
                address: "1355 Market St, San Francisco, CA 94103",
                latitude: 37.7749,
                longitude: -122.4194,
                phone: "(415) 555-1234",
                photos: [],
                rating: 4.5
            ),
            onTap: { _ in },
            onDelete: { _ in }
        )

        SavedPlaceRow(
            place: SavedPlace(
                googlePlaceId: "test2",
                name: "Whole Foods Market",
                address: "2001 Market St, San Francisco, CA 94114",
                latitude: 37.7749,
                longitude: -122.4194,
                photos: [],
                rating: 4.2
            ),
            onTap: { _ in },
            onDelete: { _ in }
        )
    }
    .padding()
    .background(Color.shadcnBackground(.light))
}
