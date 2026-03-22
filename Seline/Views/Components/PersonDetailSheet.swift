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

    private var primaryTextColor: Color {
        Color.appTextPrimary(colorScheme)
    }

    private var secondaryTextColor: Color {
        Color.appTextSecondary(colorScheme)
    }

    private var tertiaryTextColor: Color {
        Color.appTextSecondary(colorScheme).opacity(0.72)
    }

    private var cardFillColor: Color {
        Color.appSurface(colorScheme)
    }

    private var cardBorderColor: Color {
        Color.appBorder(colorScheme)
    }

    private var detailHeroSummary: String {
        "Places, visits, receipts, and notes connected to \(person.displayName) stay organized in one calm view."
    }

    private var hasPersonalAttributes: Bool {
        person.birthday != nil
            || !(person.favouriteFood ?? "").isEmpty
            || !(person.favouriteGift ?? "").isEmpty
            || !(person.favouriteColor ?? "").isEmpty
            || !(person.interests ?? []).isEmpty
    }
    
    var body: some View {
        ZStack {
            AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .topLeading)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    topActionBar
                    headerSection

                    if !isLoadingStats {
                        statsOverviewCard
                    }

                    if hasPersonalAttributes {
                        personalAttributesSection
                    }

                    if hasContactInfo {
                        contactInfoSection
                    }

                    if !favouritePlaceIds.isEmpty {
                        favouritePlacesSection
                    }

                    if visitCount > 0 {
                        recentVisitsSection
                    }

                    if receiptCount > 0 {
                        receiptsSection
                    }

                    if let notes = person.notes, !notes.isEmpty {
                        notesSection(notes: notes)
                    }

                    if let howWeMet = person.howWeMet, !howWeMet.isEmpty {
                        howWeMetSection(text: howWeMet)
                    }

                    deleteButton

                    Spacer().frame(height: 24)
                }
                .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .selinePrimaryPageScroll()
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

    private var topActionBar: some View {
        HStack(spacing: 12) {
            topPillButton(title: "Close", systemImage: "xmark") {
                onDismiss()
            }

            Spacer(minLength: 10)

            topPillButton(title: "Edit", systemImage: "pencil") {
                showingEditSheet = true
            }
        }
    }

    private func topPillButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(FontManager.geist(size: 14, weight: .semibold))
            }
            .foregroundColor(primaryTextColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.appChip(colorScheme))
            )
            .overlay(
                Capsule()
                    .stroke(cardBorderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    if let photoURL = person.photoURL, !photoURL.isEmpty {
                        CachedAsyncImage(url: photoURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            initialsAvatar(size: 92)
                        }
                        .frame(width: 92, height: 92)
                        .clipShape(Circle())
                    } else {
                        initialsAvatar(size: 92)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(cardBorderColor, lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 16, x: 0, y: 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text(person.relationshipDisplayText.uppercased())
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                        .tracking(1.4)

                    HStack(spacing: 8) {
                        Text(person.name)
                            .font(FontManager.geist(size: 30, weight: .semibold))
                            .foregroundColor(primaryTextColor)
                            .lineLimit(2)

                        if person.isFavourite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(width: 28, height: 28)
                                .background(
                                    Circle()
                                        .fill(Color.homeGlassAccent)
                                )
                        }
                    }

                    if let nickname = person.nickname, !nickname.isEmpty, nickname != person.name {
                        Text("\"\(nickname)\"")
                            .font(FontManager.geist(size: 16, weight: .regular))
                            .foregroundColor(secondaryTextColor)
                            .italic()
                    }

                    Text(detailHeroSummary)
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                heroMetaChip(icon: person.relationship.icon, title: person.relationshipDisplayText)

                if let birthday = person.formattedBirthday {
                    heroMetaChip(icon: "gift.fill", title: birthday)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .background(sectionCardBackground(cornerRadius: 28))
    }

    private func heroMetaChip(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(secondaryTextColor)

            Text(title)
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.appChip(colorScheme))
        )
        .overlay(
            Capsule()
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
    }

    private var statsOverviewCard: some View {
        HStack(spacing: 10) {
            statTile(count: visitCount, label: "Visits", icon: "mappin")
            statTile(count: receiptCount, label: "Receipts", icon: "receipt")
            statTile(count: favouritePlaceIds.count, label: "Places", icon: "heart")
        }
        .padding(10)
        .background(sectionCardBackground(cornerRadius: 22))
    }

    private func statTile(count: Int, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(secondaryTextColor)

                Text(label)
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(1)
            }

            Text("\(count)")
                .font(FontManager.geist(size: 28, weight: .semibold))
                .foregroundColor(primaryTextColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.appInnerSurface(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
    }
    
    private func initialsAvatar(size: CGFloat) -> some View {
        Circle()
            .fill(colorForRelationship(person.relationship))
            .frame(width: size, height: size)
            .overlay(
                Text(person.initials)
                    .font(FontManager.geist(size: size * 0.36, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Personal Attributes Section
    
    private var personalAttributesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Personal", icon: "person.fill")
            
            VStack(spacing: 0) {
                if let birthday = person.formattedBirthday {
                    attributeRow(icon: "gift.fill", title: "Birthday", value: birthday, iconColor: secondaryTextColor)
                    divider
                }
                
                if let age = person.age {
                    attributeRow(icon: "number", title: "Age", value: "\(age) years old", iconColor: secondaryTextColor)
                    divider
                }
                
                if let food = person.favouriteFood, !food.isEmpty {
                    attributeRow(icon: "fork.knife", title: "Favourite Food", value: food, iconColor: secondaryTextColor)
                    divider
                }
                
                if let gift = person.favouriteGift, !gift.isEmpty {
                    attributeRow(icon: "giftcard.fill", title: "Gift Ideas", value: gift, iconColor: secondaryTextColor)
                    divider
                }
                
                if let color = person.favouriteColor, !color.isEmpty {
                    attributeRow(icon: "paintpalette.fill", title: "Favourite Color", value: color, iconColor: secondaryTextColor)
                }
                
                if let interests = person.interests, !interests.isEmpty {
                    divider
                    attributeRow(icon: "heart.fill", title: "Interests", value: interests.joined(separator: ", "), iconColor: secondaryTextColor)
                }
            }
            .background(sectionCardBackground(cornerRadius: 22))
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
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Contact", icon: "phone.fill")
            
            VStack(spacing: 0) {
                if let phone = person.phone, !phone.isEmpty {
                    contactRow(icon: "phone.fill", value: phone, action: { callPhone(phone) }, iconColor: secondaryTextColor)
                    divider
                }
                
                if let email = person.email, !email.isEmpty {
                    contactRow(icon: "envelope.fill", value: email, action: { sendEmail(email) }, iconColor: secondaryTextColor)
                    divider
                }
                
                if let address = person.address, !address.isEmpty {
                    contactRow(icon: "map.fill", value: address, action: { openMaps(address) }, iconColor: secondaryTextColor)
                }
                
                if let instagram = person.instagram, !instagram.isEmpty {
                    divider
                    contactRow(icon: "camera.fill", value: "@\(instagram)", action: { openInstagram(instagram) }, iconColor: secondaryTextColor)
                }
                
                if let linkedIn = person.linkedIn, !linkedIn.isEmpty {
                    divider
                    contactRow(icon: "link", value: linkedIn, action: { openLinkedIn(linkedIn) }, iconColor: secondaryTextColor)
                }
            }
            .background(sectionCardBackground(cornerRadius: 22))
        }
    }
    
    // MARK: - Favourite Places Section
    
    private var favouritePlacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                        .font(FontManager.geist(size: 15, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                    
                    Text(place.displayName)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .lineLimit(1)
                }
                
                Text(place.category)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(tertiaryTextColor)
            }
            .padding(14)
            .frame(width: 228, alignment: .leading)
            .background(sectionCardBackground(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Recent Visits Section
    
    private var recentVisitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(title: "Recent Visits Together", icon: "clock.fill")
                Spacer()
                Text("\(visitCount) total")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(tertiaryTextColor)
            }
            
            VStack(spacing: 0) {
                ForEach(Array(recentVisits.prefix(5).enumerated()), id: \.element.visit.id) { index, visitItem in
                    visitRow(visitItem: visitItem)
                    if index < min(4, recentVisits.count - 1) {
                        divider
                    }
                }
            }
            .background(sectionCardBackground(cornerRadius: 22))
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
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.appChip(colorScheme))
                    Image(systemName: "mappin")
                        .font(FontManager.geist(size: 13, weight: .semibold))
                        .foregroundColor(secondaryTextColor)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(visitItem.placeName)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(formatVisitDate(visitItem.visit.entryTime))
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(secondaryTextColor)

                        if let duration = visitItem.visit.durationMinutes {
                            Text("•")
                                .foregroundColor(tertiaryTextColor)
                            Text(formatDuration(duration))
                                .font(FontManager.geist(size: 12, weight: .regular))
                                .foregroundColor(secondaryTextColor)
                        }
                    }

                    if let notes = visitItem.visit.visitNotes, !notes.isEmpty {
                        Text(notes)
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(tertiaryTextColor)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(tertiaryTextColor)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Receipts Section
    
    private var receiptsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(title: "Receipts Together", icon: "receipt.fill")
                Spacer()
                Text("\(receiptCount) total")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(tertiaryTextColor)
            }
            
            VStack(spacing: 0) {
                ForEach(recentReceiptIds.prefix(5), id: \.self) { receiptId in
                    receiptRow(receiptId: receiptId)
                    if receiptId != recentReceiptIds.prefix(5).last {
                        divider
                    }
                }
            }
            .background(sectionCardBackground(cornerRadius: 22))
        }
    }
    
    private func receiptRow(receiptId: UUID) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.appChip(colorScheme))
                Image(systemName: "receipt")
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
            }
            .frame(width: 34, height: 34)
            
            Text("Receipt \(receiptId.uuidString.prefix(8))...")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(primaryTextColor)
            
            Spacer()
            
            Image(systemName: "arrow.up.right")
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(tertiaryTextColor)
        }
        .padding(14)
    }
    
    // MARK: - Notes Section
    
    private func notesSection(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Notes", icon: "note.text")
            
            Text(notes)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(primaryTextColor)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(sectionCardBackground(cornerRadius: 22))
        }
    }
    
    // MARK: - How We Met Section
    
    private func howWeMetSection(text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "How We Met", icon: "hand.wave.fill")
            
            Text(text)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(primaryTextColor)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(sectionCardBackground(cornerRadius: 22))
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
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(colorScheme == .dark ? Color.red.opacity(0.12) : Color.red.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.red.opacity(colorScheme == .dark ? 0.35 : 0.22), lineWidth: 1)
        )
        .padding(.top, 6)
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.appChip(colorScheme))
                Image(systemName: icon)
                    .font(FontManager.geist(size: 10, weight: .semibold))
                    .foregroundColor(secondaryTextColor)
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .textCase(.uppercase)
                .tracking(1.1)
        }
        .foregroundColor(secondaryTextColor)
    }

    private func sectionCardBackground(cornerRadius: CGFloat = 16) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(cardFillColor)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(cardBorderColor, lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? .black.opacity(0.18) : Color.black.opacity(0.05),
                radius: colorScheme == .dark ? 10 : 16,
                x: 0,
                y: colorScheme == .dark ? 6 : 10
            )
    }
    
    private func attributeRow(icon: String, title: String, value: String, iconColor: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.appChip(colorScheme))

                Image(systemName: icon)
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .frame(width: 34, height: 34)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(tertiaryTextColor)
                
                Text(value)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(primaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
        .padding(14)
    }
    
    private func contactRow(icon: String, value: String, action: @escaping () -> Void, iconColor: Color) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.appChip(colorScheme))

                    Image(systemName: icon)
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(iconColor)
                }
                .frame(width: 34, height: 34)
                
                Text(value)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(primaryTextColor)
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(tertiaryTextColor)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
    }
    
    private var divider: some View {
        Divider()
            .overlay(Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.7 : 0.95))
            .padding(.leading, 60)
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
        guard SupabaseManager.shared.getCurrentUser()?.id != nil else {
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
