import SwiftUI

struct PeopleListView: View {
    @ObservedObject var peopleManager: PeopleManager
    @ObservedObject var locationsManager: LocationsManager
    let colorScheme: ColorScheme
    let searchText: String
    
    @State private var selectedPerson: Person? = nil
    @State private var showingAddPerson = false
    @State private var selectedRelationshipFilter: RelationshipType? = nil
    @State private var expandedSections: Set<RelationshipType> = Set(RelationshipType.allCases)
    
    private var filteredPeople: [Person] {
        var result = peopleManager.people
        
        // Apply search filter
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            result = result.filter { person in
                person.name.lowercased().contains(lowercasedSearch) ||
                (person.nickname?.lowercased().contains(lowercasedSearch) ?? false) ||
                person.relationshipDisplayText.lowercased().contains(lowercasedSearch) ||
                (person.notes?.lowercased().contains(lowercasedSearch) ?? false) ||
                (person.favouriteFood?.lowercased().contains(lowercasedSearch) ?? false) ||
                (person.favouriteGift?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }
        
        // Apply relationship filter
        if let filter = selectedRelationshipFilter {
            result = result.filter { $0.relationship == filter }
        }
        
        return result
    }
    
    private var groupedPeople: [(relationship: RelationshipType, people: [Person])] {
        let grouped = Dictionary(grouping: filteredPeople) { $0.relationship }
        return RelationshipType.allCases
            .filter { grouped[$0] != nil && !grouped[$0]!.isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { (relationship: $0, people: grouped[$0]!.sorted { $0.name < $1.name }) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with "People" title and Add button
            HStack(spacing: 12) {
                Text("People")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()

                // Add button in top right
                Button(action: {
                    showingAddPerson = true
                }) {
                    Text("Add")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white : Color.black)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            // Favorites section (similar to saved locations)
            if !peopleManager.people.isEmpty {
                favoritesSection
            }

            // Main content box (categories and people list)
            if !peopleManager.people.isEmpty {
                mainContentBox
            } else {
                emptyStateView
            }
        }
        .sheet(item: $selectedPerson) { person in
            PersonDetailSheet(
                person: person,
                peopleManager: peopleManager,
                locationsManager: locationsManager,
                colorScheme: colorScheme,
                onDismiss: { selectedPerson = nil }
            )
            .presentationBg()
        }
        .sheet(isPresented: $showingAddPerson) {
            PersonEditForm(
                person: nil,
                peopleManager: peopleManager,
                colorScheme: colorScheme,
                onSave: { newPerson in
                    peopleManager.addPerson(newPerson)
                    showingAddPerson = false
                },
                onCancel: {
                    showingAddPerson = false
                }
            )
            .presentationBg()
        }
    }
    
    // MARK: - Favorites Section
    
    @ViewBuilder
    private var favoritesSection: some View {
        let favourites = peopleManager.getFavourites()
            .filter { person in
                if !searchText.isEmpty {
                    let lowercasedSearch = searchText.lowercased()
                    return person.name.lowercased().contains(lowercasedSearch) ||
                           (person.nickname?.lowercased().contains(lowercasedSearch) ?? false)
                }
                return true
            }
        
        if !favourites.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("Favorites")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(favourites, id: \.id) { person in
                            Button(action: {
                                selectedPerson = person
                            }) {
                                VStack(spacing: 6) {
                                    // Avatar
                                    ZStack {
                                        if let photoURL = person.photoURL, !photoURL.isEmpty {
                                            CachedAsyncImage(url: photoURL) { image in
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } placeholder: {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(colorForRelationship(person.relationship))
                                                    .frame(width: 54, height: 54)
                                                    .overlay(
                                                        Text(person.initials)
                                                            .font(FontManager.geist(size: 20, weight: .semibold))
                                                            .foregroundColor(.white)
                                                    )
                                            }
                                            .frame(width: 54, height: 54)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        } else {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(colorForRelationship(person.relationship))
                                                .frame(width: 54, height: 54)
                                                .overlay(
                                                    Text(person.initials)
                                                        .font(FontManager.geist(size: 20, weight: .semibold))
                                                        .foregroundColor(.white)
                                                )
                                        }
                                    }
                                    
                                    Text(person.displayName)
                                        .font(FontManager.geist(size: 11, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                        .frame(width: 54, height: 28)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(
                        colorScheme == .dark 
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.04),
                radius: 20,
                x: 0,
                y: 4
            )
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .padding(.top, 12)
        }
    }
    
    // MARK: - Main Content Box
    
    @ViewBuilder
    private var mainContentBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Relationship filter chips
            relationshipFilterChips
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
            
            // People list content
            if filteredPeople.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.fill")
                        .font(FontManager.geist(size: 48, weight: .light))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    
                    Text(searchText.isEmpty ? "No people found" : "No people match your search")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                peopleListContent
                    .padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 20)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    colorScheme == .dark 
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.04),
            radius: 20,
            x: 0,
            y: 4
        )
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, 12)
    }
    
    // MARK: - Relationship Filter Chips
    
    private var relationshipFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                filterChip(title: "All", isSelected: selectedRelationshipFilter == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRelationshipFilter = nil
                    }
                }
                
                // Relationship type chips (only show types that have people)
                let availableTypes = Set(peopleManager.people.map { $0.relationship })
                ForEach(RelationshipType.allCases.filter { availableTypes.contains($0) }, id: \.self) { relationship in
                    filterChip(
                        title: relationship.displayName,
                        isSelected: selectedRelationshipFilter == relationship
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRelationshipFilter = selectedRelationshipFilter == relationship ? nil : relationship
                        }
                    }
                }
            }
        }
    }
    
    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FontManager.geist(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ?
                          (colorScheme == .dark ? Color.white : Color.black) :
                          (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)))
            )
            .foregroundColor(isSelected ?
                             (colorScheme == .dark ? Color.black : Color.white) :
                             (colorScheme == .dark ? Color.white : Color.black))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.fill")
                .font(FontManager.geist(size: 48, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
            
            Text(searchText.isEmpty ? "No people saved yet" : "No people found")
                .font(FontManager.geist(size: 18, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
            
            Text(searchText.isEmpty ? "Tap + to add friends, family, and contacts" : "Try a different search term")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - People List Content
    
    private var peopleListContent: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(groupedPeople, id: \.relationship) { group in
                Section {
                    ForEach(group.people) { person in
                        PersonRowView(
                            person: person,
                            colorScheme: colorScheme,
                            onTap: {
                                selectedPerson = person
                            },
                            onFavouriteTap: {
                                peopleManager.toggleFavourite(for: person.id)
                            }
                        )
                        
                        if person.id != group.people.last?.id {
                            Divider()
                                .padding(.leading, 84)
                                .opacity(0.2)
                        }
                    }
                } header: {
                    sectionHeader(for: group.relationship, count: group.people.count)
                }
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
    
    // MARK: - Section Header
    
    private func sectionHeader(for relationship: RelationshipType, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(relationship.displayName.uppercased())
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
            
            Text("(\(count))")
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
            
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
    }
    
}

// MARK: - Person Row View

struct PersonRowView: View {
    let person: Person
    let colorScheme: ColorScheme
    let onTap: () -> Void
    let onFavouriteTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar (box-like similar to locations)
                personAvatar
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(person.displayName)
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        // Relationship badge
                        Text(person.relationshipDisplayText)
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                        
                        // Birthday if available
                        if let birthday = person.formattedBirthday {
                            HStack(spacing: 3) {
                                Image(systemName: "gift.fill")
                                    .font(FontManager.geist(size: 10, weight: .medium))
                                Text(birthday)
                                    .font(FontManager.geist(size: 11, weight: .regular))
                            }
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                    }
                }
                
                Spacer()
                
                // Favourite button
                Button(action: onFavouriteTap) {
                    Image(systemName: person.isFavourite ? "star.fill" : "star")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(person.isFavourite ? .yellow : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var personAvatar: some View {
        ZStack {
            if let photoURL = person.photoURL, !photoURL.isEmpty {
                CachedAsyncImage(url: photoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsAvatar
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                initialsAvatar
            }
        }
    }
    
    private var initialsAvatar: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(colorForRelationship(person.relationship))
            .frame(width: 52, height: 52)
            .overlay(
                Text(person.initials)
                    .font(FontManager.geist(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
    
    private func colorForRelationship(_ relationship: RelationshipType) -> Color {
        switch relationship {
        case .family:
            return Color(red: 0.8, green: 0.3, blue: 0.3)
        case .partner:
            return Color(red: 0.9, green: 0.3, blue: 0.5)
        case .closeFriend:
            return Color(red: 0.3, green: 0.6, blue: 0.9)
        case .friend:
            return Color(red: 0.3, green: 0.7, blue: 0.5)
        case .coworker:
            return Color(red: 0.5, green: 0.5, blue: 0.7)
        case .classmate:
            return Color(red: 0.6, green: 0.4, blue: 0.7)
        case .neighbor:
            return Color(red: 0.5, green: 0.6, blue: 0.5)
        case .mentor:
            return Color(red: 0.8, green: 0.6, blue: 0.2)
        case .acquaintance:
            return Color(red: 0.5, green: 0.5, blue: 0.5)
        case .other:
            return Color(red: 0.4, green: 0.4, blue: 0.4)
        }
    }
}

#Preview {
    PeopleListView(
        peopleManager: PeopleManager.shared,
        locationsManager: LocationsManager.shared,
        colorScheme: .dark,
        searchText: ""
    )
}
