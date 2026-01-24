import SwiftUI

struct PlaceDetailSheet: View {
    let place: SavedPlace
    let onDismiss: () -> Void
    var isFromRanking: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var mapsService = GoogleMapsService.shared
    @State private var isLoading = true
    @State private var showingMapSelection = false

    var isPlaceDataComplete: Bool {
        !place.name.isEmpty && !place.address.isEmpty && !place.displayName.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isPlaceDataComplete {
                // Show loading state if place data is incomplete
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("Loading location details...")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                        .ignoresSafeArea()
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Top padding
                        Spacer()
                            .frame(height: 8)
                        // Photos carousel
                        if !place.photos.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(place.photos.indices, id: \.self) { index in
                                        AsyncImage(url: URL(string: place.photos[index])) { phase in
                                            switch phase {
                                            case .empty:
                                                ProgressView()
                                                    .frame(width: 280, height: 200)
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 280, height: 200)
                                                    .clipped()
                                                    .cornerRadius(12)
                                            case .failure:
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.gray.opacity(0.3))
                                                    .frame(width: 280, height: 200)
                                                    .overlay(
                                                        Image(systemName: "photo")
                                                            .font(FontManager.geist(size: 40, weight: .regular))
                                                            .foregroundColor(.gray)
                                                    )
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }

                    VStack(alignment: .leading, spacing: 16) {
                        // Place name and category
                        VStack(alignment: .leading, spacing: 8) {
                            Text(place.displayName)
                                .font(FontManager.geist(size: 24, weight: .bold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)

                            HStack(spacing: 8) {
                                // Category badge
                                Text(place.category)
                                    .font(FontManager.geist(size: 12, weight: .medium))
                                    .foregroundColor(
                                        colorScheme == .dark ?
                                            Color.white :
                                            Color.black
                                    )
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(
                                                colorScheme == .dark ?
                                                    Color.white.opacity(0.2) :
                                                    Color.black.opacity(0.1)
                                            )
                                    )

                                // Rating
                                if let rating = place.rating {
                                    HStack(spacing: 4) {
                                        Image(systemName: "star.fill")
                                            .font(FontManager.geist(size: 14, weight: .regular))
                                            .foregroundColor(.yellow)

                                        Text(String(format: "%.1f", rating))
                                            .font(FontManager.geist(size: 14, weight: .semibold))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                    }
                                }
                            }
                        }

                        // Address with Maps button
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Address")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                            HStack(alignment: .top, spacing: 12) {
                                Text(place.address)
                                    .font(FontManager.geist(size: 15, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                
                                Spacer()
                                
                                // Maps button (pill-shaped)
                                Button(action: {
                                    openInMaps(place: place)
                                }) {
                                    Text("Maps")
                                        .font(FontManager.geist(size: 13, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1))
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        // Phone number
                        if let phone = place.phone {
                            Button(action: {
                                callPhone(phone)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "phone.fill")
                                        .font(FontManager.geist(size: 20, weight: .regular))
                                        .foregroundColor(
                                            colorScheme == .dark ?
                                                Color.white :
                                                Color.black
                                        )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Phone")
                                            .font(FontManager.geist(size: 12, weight: .medium))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                        Text(phone)
                                            .font(FontManager.geist(size: 15, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? .white : .black)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(FontManager.geist(size: 14, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Opening Hours
                        if let hours = place.openingHours, !hours.isEmpty {
                            OpeningHoursSection(hours: hours, colorScheme: colorScheme)
                        }
                        
                        // Location Memories (what user usually gets, why they visit)
                        LocationMemorySection(place: place, colorScheme: colorScheme)

                        // Visit Stats and History (not shown in Ranking tab)
                        if !isFromRanking {
                            VisitStatsCard(place: place)

                            VisitHistoryCard(place: place)
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer()
                        .frame(height: 40)
                }
            }
            .background(
                (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                    .ignoresSafeArea()
            )
            }
        }
        .background(
            (colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                .ignoresSafeArea()
        )
        .alert("Choose Map App", isPresented: $showingMapSelection) {
            Button("Google Maps") {
                UserDefaults.standard.set("google", forKey: "preferredMapApp")
                mapsService.openInGoogleMaps(place: place, preferGoogle: true)
            }
            Button("Apple Maps") {
                UserDefaults.standard.set("apple", forKey: "preferredMapApp")
                mapsService.openInGoogleMaps(place: place, preferGoogle: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Which map app would you like to use? This will be your default choice.")
        }
    }

    private func callPhone(_ phone: String) {
        // Remove formatting from phone number
        let cleanedPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        if let phoneURL = URL(string: "tel://\(cleanedPhone)"),
           UIApplication.shared.canOpenURL(phoneURL) {
            UIApplication.shared.open(phoneURL)
        }
    }
    
    private func openInMaps(place: SavedPlace) {
        // Check if user has a preferred map app
        let userDefaults = UserDefaults.standard
        let preferredMapKey = "preferredMapApp"
        
        if let preferredMap = userDefaults.string(forKey: preferredMapKey) {
            // User has a preference, use it
            if preferredMap == "google" {
                mapsService.openInGoogleMaps(place: place, preferGoogle: true)
            } else {
                mapsService.openInGoogleMaps(place: place, preferGoogle: false)
            }
        } else {
            // First time - show selection
            showingMapSelection = true
        }
    }
}

// MARK: - Location Memory Section

struct LocationMemorySection: View {
    let place: SavedPlace
    let colorScheme: ColorScheme
    
    @StateObject private var memoryService = LocationMemoryService.shared
    @State private var memories: [LocationMemory] = []
    @State private var isLoading = false
    @State private var showingPurchaseInput = false
    @State private var showingPurposeInput = false
    @State private var purchaseText = ""
    @State private var purposeText = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // General reasons for visiting this location (higher level)
                    if let purposeMemory = memories.first(where: { $0.memoryType == .purpose }) {
                        Button(action: {
                            purposeText = purposeMemory.content
                            showingPurposeInput = true
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "brain.head.profile")
                                    .font(FontManager.geist(size: 20, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Why you visit")
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                    Text(purposeMemory.content)
                                        .font(FontManager.geist(size: 15, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(nil)
                                }

                                Spacer()

                                // Edit chevron
                                Image(systemName: "chevron.right")
                                    .font(FontManager.geist(size: 12, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        Button(action: {
                            purposeText = ""
                            showingPurposeInput = true
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "brain.head.profile")
                                    .font(FontManager.geist(size: 20, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                                Text("What are some reasons you visit this location?")
                                    .font(FontManager.geist(size: 15, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                Spacer()

                                Image(systemName: "plus.circle.fill")
                                    .font(FontManager.geist(size: 20, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1),
                                        lineWidth: 1.5,
                                        antialiased: true
                                    )
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.01))
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    // What user usually gets (optional secondary info)
                    if let purchaseMemory = memories.first(where: { $0.memoryType == .purchase }) {
                        Button(action: {
                            purchaseText = purchaseMemory.content
                            showingPurchaseInput = true
                        }) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "cart.fill")
                                    .font(FontManager.geist(size: 20, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Usually get")
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                                    Text(purchaseMemory.content)
                                        .font(FontManager.geist(size: 15, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(nil)

                                    if let items = purchaseMemory.items, !items.isEmpty {
                                        Text("Items: \(items.joined(separator: ", "))")
                                            .font(FontManager.geist(size: 12, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                            .padding(.top, 2)
                                    }
                                }

                                Spacer()

                                // Edit chevron
                                Image(systemName: "chevron.right")
                                    .font(FontManager.geist(size: 12, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .onAppear {
            loadMemories()
        }
        .sheet(isPresented: $showingPurchaseInput) {
            LocationMemoryInputSheet(
                place: place,
                memoryType: .purchase,
                question: "What do you usually get?",
                placeholder: "e.g., vitamins, allergy meds, groceries...",
                initialText: purchaseText,
                colorScheme: colorScheme,
                onSave: { text in
                    await savePurchaseMemory(text: text)
                    showingPurchaseInput = false
                    purchaseText = ""
                },
                onDismiss: {
                    showingPurchaseInput = false
                    purchaseText = ""
                }
            )
        }
        .sheet(isPresented: $showingPurposeInput) {
            LocationMemoryInputSheet(
                place: place,
                memoryType: .purpose,
                question: "Why do you visit?",
                placeholder: "e.g., weekly grocery shopping, picking up prescriptions, meeting friends...",
                initialText: purposeText,
                colorScheme: colorScheme,
                onSave: { text in
                    await savePurposeMemory(text: text)
                    showingPurposeInput = false
                    purposeText = ""
                },
                onDismiss: {
                    showingPurposeInput = false
                    purposeText = ""
                }
            )
        }
    }
    
    private func loadMemories() {
        isLoading = true
        Task {
            do {
                memories = try await memoryService.getMemories(for: place.id)
            } catch {
                print("❌ Failed to load location memories: \(error)")
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func savePurchaseMemory(text: String) async {
        let extraction = NaturalLanguageExtractionService.shared.extractInfo(from: text)
        
        do {
            try await memoryService.saveMemory(
                placeId: place.id,
                type: .purchase,
                content: extraction.rawText,
                items: extraction.items.isEmpty ? nil : extraction.items,
                frequency: extraction.frequency
            )
            await loadMemories()
        } catch {
            print("❌ Failed to save purchase memory: \(error)")
        }
    }
    
    private func savePurposeMemory(text: String) async {
        do {
            try await memoryService.saveMemory(
                placeId: place.id,
                type: .purpose,
                content: text
            )
            await loadMemories()
        } catch {
            print("❌ Failed to save purpose memory: \(error)")
        }
    }
}

struct MemoryRow: View {
    let icon: String
    let label: String
    let content: String
    let items: [String]?
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(FontManager.geist(size: 16, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                
                Text(content)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                if let items = items, !items.isEmpty {
                    Text("Items: \(items.joined(separator: ", "))")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Edit indicator
            Image(systemName: "pencil")
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
        }
    }
}

struct LocationMemoryInputSheet: View {
    let place: SavedPlace
    let memoryType: MemoryType
    let question: String
    let placeholder: String
    let initialText: String
    let colorScheme: ColorScheme
    let onSave: (String) async -> Void
    let onDismiss: () -> Void

    @State private var inputText: String
    @FocusState private var isFocused: Bool

    enum MemoryType {
        case purpose
        case purchase
    }

    init(place: SavedPlace, memoryType: MemoryType, question: String, placeholder: String, initialText: String = "", colorScheme: ColorScheme, onSave: @escaping (String) async -> Void, onDismiss: @escaping () -> Void) {
        self.place = place
        self.memoryType = memoryType
        self.question = question
        self.placeholder = placeholder
        self.initialText = initialText
        self.colorScheme = colorScheme
        self.onSave = onSave
        self.onDismiss = onDismiss
        _inputText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                // Location name
                Text(place.displayName)
                    .font(FontManager.geist(size: 18, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Divider()

                // Question
                Text(question)
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.top, 8)

                // Input field
                TextField(placeholder, text: $inputText, axis: .vertical)
                    .font(FontManager.geist(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
                    .lineLimit(3...6)
                    .focused($isFocused)

                Spacer()
            }
            .padding(20)
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .navigationTitle(memoryType == .purpose ? "Location Memory" : "What You Get")
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
                        Task {
                            await onSave(inputText.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}

// MARK: - Opening Hours Section
struct OpeningHoursSection: View {
    let hours: [String]
    let colorScheme: ColorScheme
    @State private var isExpanded = false
    
    // Get current day abbreviation (Mon, Tue, etc.)
    private var currentDayPrefix: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"  // Short weekday name
        return formatter.string(from: Date())
    }
    
    // Find today's hours from the array
    private var todayHours: String? {
        let dayPrefixes = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let todayPrefix = currentDayPrefix
        
        // Try to find matching day
        for hour in hours {
            for prefix in dayPrefixes {
                if hour.hasPrefix(prefix) && todayPrefix.hasPrefix(prefix.prefix(3)) {
                    return hour
                }
            }
        }
        
        // If no match, return first hour as fallback
        return hours.first
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row - tappable to expand/collapse
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "clock.fill")
                        .font(FontManager.geist(size: 20, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hours")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        
                        if let today = todayHours {
                            Text(today)
                                .font(FontManager.geist(size: 15, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded hours list
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(hours, id: \.self) { hour in
                        HStack {
                            Text(hour)
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.85))
                            Spacer()
                        }
                    }
                }
                .padding(.leading, 32)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

#Preview {
    PlaceDetailSheet(
        place: SavedPlace(
            googlePlaceId: "test1",
            name: "Blue Bottle Coffee",
            address: "1355 Market St, San Francisco, CA 94103",
            latitude: 37.7749,
            longitude: -122.4194,
            phone: "(415) 555-1234",
            photos: [
                "https://via.placeholder.com/280x200",
                "https://via.placeholder.com/280x200"
            ],
            rating: 4.5,
            openingHours: [
                "Monday: 7:00 AM – 6:00 PM",
                "Tuesday: 7:00 AM – 6:00 PM",
                "Wednesday: 7:00 AM – 6:00 PM",
                "Thursday: 7:00 AM – 6:00 PM",
                "Friday: 7:00 AM – 6:00 PM",
                "Saturday: 8:00 AM – 5:00 PM",
                "Sunday: 8:00 AM – 5:00 PM"
            ]
        ),
        onDismiss: {}
    )
}
