import SwiftUI

// MARK: - NewLocationSuggestionCard
//
// A sleek, modern card that appears on the home page when user
// has been at an unsaved location (with a title like restaurant/shop) for 5+ minutes

struct NewLocationSuggestionCard: View {
    @StateObject private var suggestionService = LocationSuggestionService.shared
    @State private var isExpanded = false
    @State private var showCategoryPicker = false
    @State private var selectedCategory: String? = nil
    @State private var isSaving = false
    @State private var animationOffset: CGFloat = 50
    @State private var cardOpacity: Double = 0
    @Environment(\.colorScheme) var colorScheme
    
    private let categories = [
        "Home", "Work", "Restaurant", "Cafe", "Gym", "Shopping",
        "Entertainment", "Healthcare", "Education", "Other"
    ]
    
    // MARK: - Theme Colors
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }
    
    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08)
    }
    
    var body: some View {
        if let suggestion = suggestionService.suggestedLocation {
            VStack(spacing: 0) {
                // Main card
                VStack(spacing: 14) {
                    // Header with icon and dismiss
                    HStack(spacing: 12) {
                        // Clean location indicator
                        ZStack {
                            Circle()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: "mappin.circle.fill")
                                .font(FontManager.geist(size: 22, weight: .semibold))
                                .foregroundColor(primaryTextColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("New location detected")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(secondaryTextColor)
                            
                            Text(suggestion.name)
                                .font(FontManager.geist(size: 17, weight: .semibold))
                                .foregroundColor(primaryTextColor)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Dismiss button
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                suggestionService.dismissSuggestion()
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(FontManager.geist(size: 14, weight: .semibold))
                                .foregroundColor(secondaryTextColor)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                                )
                        }
                    }
                    
                    // Address (smaller, secondary)
                    HStack {
                        Image(systemName: "location.fill")
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                        
                        Text(suggestion.address)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.top, -4)
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        // Category picker button
                        Menu {
                            ForEach(categories, id: \.self) { category in
                                Button(action: {
                                    selectedCategory = category
                                }) {
                                    HStack {
                                        Text(category)
                                        if selectedCategory == category {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(FontManager.geist(size: 13, weight: .medium))
                                Text(selectedCategory ?? "Select")
                                    .font(FontManager.geist(size: 14, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(FontManager.geist(size: 10, weight: .semibold))
                            }
                            .foregroundColor(primaryTextColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(borderColor, lineWidth: 1)
                            )
                        }
                        
                        Spacer()
                        
                        // Save button - black/white theme
                        Button(action: {
                            saveLocation()
                        }) {
                            HStack(spacing: 6) {
                                if isSaving {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(colorScheme == .dark ? .black : .white)
                                } else {
                                    Image(systemName: "plus")
                                        .font(FontManager.geist(size: 14, weight: .semibold))
                                }
                                Text("Save Location")
                                    .font(FontManager.geist(size: 14, weight: .semibold))
                            }
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? .white : .black)
                            )
                        }
                        .disabled(isSaving)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: 1)
                )
                .shadow(
                    color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.06),
                    radius: 12,
                    x: 0,
                    y: 4
                )
            }
            .padding(.horizontal, 16)
            .offset(y: animationOffset)
            .opacity(cardOpacity)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    animationOffset = 0
                    cardOpacity = 1
                }
            }
        }
    }
    
    private func saveLocation() {
        isSaving = true
        
        Task {
            let category = selectedCategory ?? "Other"
            if let place = await suggestionService.saveSuggestedLocation(withCategory: category) {
                // Update the category
                var updatedPlace = place
                updatedPlace.category = category
                LocationsManager.shared.updatePlace(updatedPlace)
                
                // Setup geofence for new location
                GeofenceManager.shared.setupGeofences(for: LocationsManager.shared.savedPlaces)
            }
            
            await MainActor.run {
                isSaving = false
            }
        }
    }
}

// MARK: - Compact version for smaller spaces

struct NewLocationSuggestionBanner: View {
    @StateObject private var suggestionService = LocationSuggestionService.shared
    @State private var showFullCard = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if let suggestion = suggestionService.suggestedLocation {
            Button(action: {
                showFullCard = true
            }) {
                HStack(spacing: 10) {
                    // Pulsing dot
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                            .frame(width: 12, height: 12)
                        
                        Circle()
                            .fill(colorScheme == .dark ? .white : .black)
                            .frame(width: 8, height: 8)
                    }
                    
                    Text("Save \"\(suggestion.name)\"?")
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .sheet(isPresented: $showFullCard) {
                LocationSuggestionSheet(suggestion: suggestion)
            }
        }
    }
}

// MARK: - Full sheet for saving location

struct LocationSuggestionSheet: View {
    let suggestion: SuggestedLocation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var suggestionService = LocationSuggestionService.shared
    @State private var customName: String = ""
    @State private var selectedCategory: String? = nil
    @State private var isSaving = false
    
    private let categories = [
        "Home", "Work", "Restaurant", "Cafe", "Gym", "Shopping",
        "Entertainment", "Healthcare", "Education", "Other"
    ]
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Location preview
                VStack(spacing: 16) {
                    // Map-like visual - black/white theme
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            .frame(height: 120)
                        
                        VStack(spacing: 8) {
                            Image(systemName: "mappin.circle.fill")
                                .font(FontManager.geist(size: 40, weight: .regular))
                                .foregroundColor(primaryTextColor)
                        }
                    }
                    
                    // Location details
                    VStack(spacing: 8) {
                        Text(suggestion.name)
                            .font(FontManager.geist(size: 20, weight: .bold))
                            .foregroundColor(primaryTextColor)
                        
                        Text(suggestion.address)
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                // Custom name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Name (Optional)")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    
                    TextField("e.g., Mom's House, Favorite Coffee Shop", text: $customName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)
                
                // Category picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(categories, id: \.self) { category in
                                Button(action: {
                                    selectedCategory = category
                                }) {
                                    Text(category)
                                        .font(FontManager.geist(size: 14, weight: .medium))
                                        .foregroundColor(selectedCategory == category ? (colorScheme == .dark ? .black : .white) : primaryTextColor)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(selectedCategory == category
                                                    ? (colorScheme == .dark ? Color.white : Color.black)
                                                    : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                                                )
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    Button(action: saveLocation) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(colorScheme == .dark ? .black : .white)
                            } else {
                                Image(systemName: "plus")
                            }
                            Text("Save Location")
                                .font(FontManager.geist(size: 16, weight: .semibold))
                        }
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(colorScheme == .dark ? .white : .black)
                        )
                    }
                    .disabled(isSaving)
                    
                    Button(action: {
                        suggestionService.dismissSuggestion()
                        dismiss()
                    }) {
                        Text("Not Now")
                            .font(FontManager.geist(size: 16, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle("Save Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func saveLocation() {
        isSaving = true
        
        Task {
            let category = selectedCategory ?? "Other"
            if let place = await suggestionService.saveSuggestedLocation(withCategory: category) {
                var updatedPlace = place
                if !customName.isEmpty {
                    updatedPlace.customName = customName
                }
                updatedPlace.category = category
                LocationsManager.shared.updatePlace(updatedPlace)
                
                // Setup geofence for new location
                GeofenceManager.shared.setupGeofences(for: LocationsManager.shared.savedPlaces)
            }
            
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}

#Preview {
    VStack {
        NewLocationSuggestionCard()
        Spacer()
    }
    .padding(.top)
    .background(Color(.systemGroupedBackground))
}
