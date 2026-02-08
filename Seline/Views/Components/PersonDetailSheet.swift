import SwiftUI

struct PersonDetailSheet: View {
    let person: Person
    @ObservedObject var peopleManager: PeopleManager
    @ObservedObject var locationsManager: LocationsManager
    let colorScheme: ColorScheme
    let onDismiss: () -> Void
    
    @State private var showingEditSheet = false
    @State private var showingDeleteAlert = false
    @State private var visitCount: Int = 0
    @State private var receiptCount: Int = 0
    @State private var recentVisitIds: [UUID] = []
    @State private var recentVisits: [VisitHistoryItem] = []
    @State private var recentReceiptIds: [UUID] = []
    @State private var favouritePlaceIds: [UUID] = []
    @State private var isLoadingStats = true
    @State private var selectedPlace: SavedPlace? = nil
    @State private var selectedVisitPlaceId: UUID? = nil
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with avatar and basic info
                    headerSection
                    
                    // Personal attributes section
                    personalAttributesSection
                    
                    // Contact info section
                    if hasContactInfo {
                        contactInfoSection
                    }
                    
                    // Favourite places section
                    if !favouritePlaceIds.isEmpty {
                        favouritePlacesSection
                    }
                    
                    // Recent visits together section
                    if visitCount > 0 {
                        recentVisitsSection
                    }
                    
                    // Receipts together section
                    if receiptCount > 0 {
                        receiptsSection
                    }
                    
                    // Notes section
                    if let notes = person.notes, !notes.isEmpty {
                        notesSection(notes: notes)
                    }
                    
                    // How we met section
                    if let howWeMet = person.howWeMet, !howWeMet.isEmpty {
                        howWeMetSection(text: howWeMet)
                    }
                    
                    // Delete button
                    deleteButton
                    
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        onDismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Edit") {
                        showingEditSheet = true
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
        .task {
            await loadStats()
        }
        .sheet(isPresented: $showingEditSheet) {
            PersonEditForm(
                person: person,
                peopleManager: peopleManager,
                colorScheme: colorScheme,
                onSave: { updatedPerson in
                    peopleManager.updatePerson(updatedPerson)
                    showingEditSheet = false
                },
                onCancel: {
                    showingEditSheet = false
                }
            )
            .presentationBg()
        }
        .sheet(item: $selectedPlace) { place in
            PlaceDetailSheet(place: place, onDismiss: { selectedPlace = nil })
                .presentationBg()
        }
        .alert("Delete Person", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                peopleManager.deletePerson(person)
                onDismiss()
            }
        } message: {
            Text("Are you sure you want to delete \(person.name)? This action cannot be undone.")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                if let photoURL = person.photoURL, !photoURL.isEmpty {
                    CachedAsyncImage(url: photoURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        initialsAvatar(size: 100)
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                } else {
                    initialsAvatar(size: 100)
                }
            }
            .overlay(
                Circle()
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 2)
            )
            
            // Name and relationship
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(person.name)
                        .font(FontManager.geist(size: 24, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    if person.isFavourite {
                        Image(systemName: "star.fill")
                            .font(FontManager.geist(size: 16, weight: .medium))
                            .foregroundColor(.yellow)
                    }
                }
                
                if let nickname = person.nickname, !nickname.isEmpty, nickname != person.name {
                    Text("\"\(nickname)\"")
                        .font(FontManager.geist(size: 16, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        .italic()
                }
                
                HStack(spacing: 6) {
                    Image(systemName: person.relationship.icon)
                        .font(FontManager.geist(size: 12, weight: .medium))
                    Text(person.relationshipDisplayText)
                        .font(FontManager.geist(size: 14, weight: .medium))
                }
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                )
            }
            
            // Stats row
            if !isLoadingStats {
                HStack(spacing: 24) {
                    statItem(count: visitCount, label: "Visits", icon: "mappin.circle.fill")
                    statItem(count: receiptCount, label: "Receipts", icon: "receipt.fill")
                    statItem(count: favouritePlaceIds.count, label: "Places", icon: "heart.fill")
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 16)
    }
    
    private func statItem(count: Int, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(FontManager.geist(size: 14, weight: .medium))
                Text("\(count)")
                    .font(FontManager.geist(size: 18, weight: .bold))
            }
            .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Text(label)
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
        }
    }
    
    private func initialsAvatar(size: CGFloat) -> some View {
        Circle()
            .fill(colorForRelationship(person.relationship))
            .frame(width: size, height: size)
            .overlay(
                Text(person.initials)
                    .font(FontManager.geist(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Personal Attributes Section
    
    private var personalAttributesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Personal", icon: "person.fill")
            
            VStack(spacing: 0) {
                if let birthday = person.formattedBirthday {
                    attributeRow(icon: "gift.fill", title: "Birthday", value: birthday, iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    divider
                }
                
                if let age = person.age {
                    attributeRow(icon: "number", title: "Age", value: "\(age) years old", iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    divider
                }
                
                if let food = person.favouriteFood, !food.isEmpty {
                    attributeRow(icon: "fork.knife", title: "Favourite Food", value: food, iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    divider
                }
                
                if let gift = person.favouriteGift, !gift.isEmpty {
                    attributeRow(icon: "giftcard.fill", title: "Gift Ideas", value: gift, iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    divider
                }
                
                if let color = person.favouriteColor, !color.isEmpty {
                    attributeRow(icon: "paintpalette.fill", title: "Favourite Color", value: color, iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
                
                if let interests = person.interests, !interests.isEmpty {
                    divider
                    attributeRow(icon: "heart.fill", title: "Interests", value: interests.joined(separator: ", "), iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
        }
    }
    
    // MARK: - Contact Info Section
    
    private var hasContactInfo: Bool {
        (person.phone != nil && !person.phone!.isEmpty) ||
        (person.email != nil && !person.email!.isEmpty) ||
        (person.address != nil && !person.address!.isEmpty) ||
        (person.instagram != nil && !person.instagram!.isEmpty) ||
        (person.linkedIn != nil && !person.linkedIn!.isEmpty)
    }
    
    private var contactInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Contact", icon: "phone.fill")
            
            VStack(spacing: 0) {
                if let phone = person.phone, !phone.isEmpty {
                    contactRow(icon: "phone.fill", value: phone, action: { callPhone(phone) }, iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    divider
                }
                
                if let email = person.email, !email.isEmpty {
                    contactRow(icon: "envelope.fill", value: email, action: { sendEmail(email) }, iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                    divider
                }
                
                if let address = person.address, !address.isEmpty {
                    contactRow(icon: "map.fill", value: address, action: { openMaps(address) }, iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
                
                if let instagram = person.instagram, !instagram.isEmpty {
                    divider
                    contactRow(icon: "camera.fill", value: "@\(instagram)", action: { openInstagram(instagram) }, iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
                
                if let linkedIn = person.linkedIn, !linkedIn.isEmpty {
                    divider
                    contactRow(icon: "link", value: linkedIn, action: { openLinkedIn(linkedIn) }, iconColor: colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
        }
    }
    
    // MARK: - Favourite Places Section
    
    private var favouritePlacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Favourite Spots Together", icon: "heart.fill")
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(favouritePlaceIds, id: \.self) { placeId in
                        if let place = locationsManager.savedPlaces.first(where: { $0.id == placeId }) {
                            placeCard(place: place)
                        }
                    }
                }
            }
        }
    }
    
    private func placeCard(place: SavedPlace) -> some View {
        Button(action: {
            selectedPlace = place
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: place.getDisplayIcon())
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    
                    Text(place.displayName)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                }
                
                Text(place.category)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Recent Visits Section
    
    private var recentVisitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "Recent Visits Together", icon: "clock.fill")
                Spacer()
                Text("\(visitCount) total")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            
            VStack(spacing: 0) {
                ForEach(Array(recentVisits.prefix(5).enumerated()), id: \.element.visit.id) { index, visitItem in
                    visitRow(visitItem: visitItem)
                    if index < min(4, recentVisits.count - 1) {
                        divider
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
        }
    }
    
    private func visitRow(visitItem: VisitHistoryItem) -> some View {
        Button(action: {
            // Open the place detail for this visit
            if let place = locationsManager.savedPlaces.first(where: { $0.id == visitItem.visit.savedPlaceId }) {
                selectedPlace = place
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(FontManager.geist(size: 20, weight: .medium))
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(visitItem.placeName)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(formatVisitDate(visitItem.visit.entryTime))
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                        if let duration = visitItem.visit.durationMinutes {
                            Text("•")
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
                            Text(formatDuration(duration))
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        }
                    }

                    if let notes = visitItem.visit.visitNotes, !notes.isEmpty {
                        Text(notes)
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
            .padding(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Receipts Section
    
    private var receiptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(title: "Receipts Together", icon: "receipt.fill")
                Spacer()
                Text("\(receiptCount) total")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
            }
            
            VStack(spacing: 0) {
                ForEach(recentReceiptIds.prefix(5), id: \.self) { receiptId in
                    receiptRow(receiptId: receiptId)
                    if receiptId != recentReceiptIds.prefix(5).last {
                        divider
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
        }
    }
    
    private func receiptRow(receiptId: UUID) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "receipt.fill")
                .font(FontManager.geist(size: 20, weight: .medium))
                .foregroundColor(.green)
            
            Text("Receipt \(receiptId.uuidString.prefix(8))...")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
        }
        .padding(12)
    }
    
    // MARK: - Notes Section
    
    private func notesSection(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Notes", icon: "note.text")
            
            Text(notes)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
        }
    }
    
    // MARK: - How We Met Section
    
    private func howWeMetSection(text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "How We Met", icon: "hand.wave.fill")
            
            Text(text)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.8))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
        }
    }
    
    // MARK: - Delete Button
    
    private var deleteButton: some View {
        Button(action: {
            showingDeleteAlert = true
        }) {
            HStack {
                Image(systemName: "trash.fill")
                Text("Delete Person")
            }
            .font(FontManager.geist(size: 14, weight: .medium))
            .foregroundColor(.red)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.top, 16)
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(FontManager.geist(size: 14, weight: .medium))
            Text(title)
                .font(FontManager.geist(size: 16, weight: .semibold))
        }
        .foregroundColor(colorScheme == .dark ? .white : .black)
    }
    
    private func attributeRow(icon: String, title: String, value: String, iconColor: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(FontManager.geist(size: 16, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                
                Text(value)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            
            Spacer()
        }
        .padding(12)
    }
    
    private func contactRow(icon: String, value: String, action: @escaping () -> Void, iconColor: Color) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 24)
                
                Text(value)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
            .padding(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var divider: some View {
        Divider()
            .background(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
            .padding(.leading, 48)
    }
    
    // MARK: - Actions
    
    private func callPhone(_ phone: String) {
        if let url = URL(string: "tel://\(phone.replacingOccurrences(of: " ", with: ""))") {
            UIApplication.shared.open(url)
        }
    }
    
    private func sendEmail(_ email: String) {
        if let url = URL(string: "mailto:\(email)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openMaps(_ address: String) {
        if let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "maps://?q=\(encoded)") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openInstagram(_ username: String) {
        if let url = URL(string: "instagram://user?username=\(username)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else if let webUrl = URL(string: "https://instagram.com/\(username)") {
                UIApplication.shared.open(webUrl)
            }
        }
    }
    
    private func openLinkedIn(_ profile: String) {
        if let url = URL(string: "https://linkedin.com/in/\(profile)") {
            UIApplication.shared.open(url)
        }
    }
    
    // MARK: - Data Loading

    private func loadStats() async {
        visitCount = await peopleManager.getTotalVisitCount(personId: person.id)
        receiptCount = await peopleManager.getTotalReceiptCount(personId: person.id)
        recentVisitIds = await peopleManager.getVisitIdsForPerson(personId: person.id)
        recentReceiptIds = await peopleManager.getReceiptIdsForPerson(personId: person.id)
        favouritePlaceIds = await peopleManager.getFavouritePlacesForPerson(personId: person.id)

        // Fetch actual visit data
        await loadRecentVisits()

        await MainActor.run {
            isLoadingStats = false
        }
    }

    private func loadRecentVisits() async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            return
        }

        var visitItems: [VisitHistoryItem] = []

        // Fetch visit records from Supabase for the recent visit IDs
        for visitId in recentVisitIds.prefix(5) {
            do {
                let client = await SupabaseManager.shared.getPostgrestClient()
                let response: [LocationVisitRecord] = try await client
                    .from("location_visits")
                    .select()
                    .eq("id", value: visitId.uuidString)
                    .execute()
                    .value

                if let visit = response.first {
                    // Get the place name
                    if let place = locationsManager.savedPlaces.first(where: { $0.id == visit.savedPlaceId }) {
                        let item = VisitHistoryItem(visit: visit, placeName: place.displayName)
                        visitItems.append(item)
                    } else {
                        // Fallback if place not found locally
                        let item = VisitHistoryItem(visit: visit, placeName: "Unknown Location")
                        visitItems.append(item)
                    }
                }
            } catch {
                print("❌ Error loading visit \(visitId): \(error)")
            }
        }

        await MainActor.run {
            self.recentVisits = visitItems
        }
    }

    private func formatVisitDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
            return "Today, \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "h:mm a"
            return "Yesterday, \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(mins)m"
            }
        }
    }
    
    private func colorForRelationship(_ relationship: RelationshipType) -> Color {
        switch relationship {
        case .family: return Color(red: 0.8, green: 0.3, blue: 0.3)
        case .partner: return Color(red: 0.9, green: 0.3, blue: 0.5)
        case .closeFriend: return Color(red: 0.3, green: 0.6, blue: 0.9)
        case .friend: return Color(red: 0.3, green: 0.7, blue: 0.5)
        case .coworker: return Color(red: 0.5, green: 0.5, blue: 0.7)
        case .classmate: return Color(red: 0.6, green: 0.4, blue: 0.7)
        case .neighbor: return Color(red: 0.5, green: 0.6, blue: 0.5)
        case .mentor: return Color(red: 0.8, green: 0.6, blue: 0.2)
        case .acquaintance: return Color(red: 0.5, green: 0.5, blue: 0.5)
        case .other: return Color(red: 0.4, green: 0.4, blue: 0.4)
        }
    }
}
