import SwiftUI

struct PeopleListView: View {
    @ObservedObject var peopleManager: PeopleManager
    @ObservedObject var locationsManager: LocationsManager
    let colorScheme: ColorScheme
    let searchText: String
    
    @State private var selectedPerson: Person? = nil
    @State private var showingAddPerson = false
    @State private var showingContactsImport = false
    @State private var selectedRelationshipFilter: String? = nil // Changed to String to support custom relationships
    @State private var expandedSections: Set<RelationshipType> = Set(RelationshipType.allCases)

    // Edit mode for bulk delete
    @State private var isEditMode = false
    @State private var selectedPeopleForDeletion: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var personToDelete: Person? = nil

    // Category ordering
    @State private var categoryOrder: [String] = [] // Custom order for categories

    // Cache for filtered and grouped results
    @State private var filteredPeopleCache: [Person] = []
    @State private var groupedPeopleCache: [(groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])] = []

    // Debounce timer for search
    @State private var searchDebounceTimer: Timer?
    
    // MARK: - Cache Update Method

    private func updateFilteredResults() {
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
            result = result.filter { person in
                if filter.hasPrefix("custom_") {
                    // Custom relationship filter
                    let customName = String(filter.dropFirst("custom_".count))
                    return person.relationship == .other && person.customRelationship == customName
                } else if filter.hasPrefix("type_") {
                    // Standard relationship type filter
                    let typeRawValue = String(filter.dropFirst("type_".count))
                    return person.relationship.rawValue == typeRawValue
                } else {
                    return false
                }
            }
        }

        filteredPeopleCache = result

        // Update grouped cache - group by custom relationship if type is "other"
        let groupedDict = Dictionary(grouping: result) { person -> String in
            if person.relationship == .other, let custom = person.customRelationship, !custom.isEmpty {
                return "custom_\(custom)" // Use custom relationship as key
            } else {
                return "type_\(person.relationship.rawValue)" // Use standard relationship type
            }
        }

        // Build sorted groups
        var groups: [(groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])] = []

        // First add standard relationship types (in order)
        for relType in RelationshipType.allCases where relType != .other {
            let key = "type_\(relType.rawValue)"
            if let people = groupedDict[key], !people.isEmpty {
                groups.append((
                    groupKey: key,
                    displayName: relType.displayName,
                    relationshipType: relType,
                    people: people.sorted { $0.name < $1.name }
                ))
            }
        }

        // Then add custom relationships (alphabetically)
        let customGroups = groupedDict
            .filter { $0.key.hasPrefix("custom_") }
            .sorted { $0.key < $1.key }
            .map { key, people -> (groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person]) in
                let customName = String(key.dropFirst("custom_".count))
                return (
                    groupKey: key,
                    displayName: customName,
                    relationshipType: nil,
                    people: people.sorted { $0.name < $1.name }
                )
            }
        groups.append(contentsOf: customGroups)

        // Finally add "Other" if there are people with relationship = .other but no custom relationship
        let otherKey = "type_\(RelationshipType.other.rawValue)"
        if let otherPeople = groupedDict[otherKey], !otherPeople.isEmpty {
            groups.append((
                groupKey: otherKey,
                displayName: RelationshipType.other.displayName,
                relationshipType: .other,
                people: otherPeople.sorted { $0.name < $1.name }
            ))
        }

        groupedPeopleCache = groups
    }

    private static let categoryOrderKey = "people_category_order"

    var body: some View {
        VStack(spacing: 0) {
            // PINNED HEADER — never scrolls
            stickyHeader
                .background(colorScheme == .dark ? Color.black : Color(UIColor.systemBackground))

            // SCROLLABLE CONTENT — everything between header and footer scrolls
            ScrollView {
                VStack(spacing: 0) {
                    // Favorites
                    if !peopleManager.people.isEmpty && !isEditMode {
                        favoritesSection
                    }

                    // Main list
                    if !peopleManager.people.isEmpty {
                        mainContentBox
                    } else {
                        emptyStateView
                    }
                }
                .padding(.bottom, isEditMode ? 20 : 0)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditMode {
                stickyDeleteFooter
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
        .sheet(isPresented: $showingContactsImport) {
            ContactsImportView(
                peopleManager: peopleManager,
                colorScheme: colorScheme,
                onDismiss: {
                    showingContactsImport = false
                }
            )
            .presentationBg()
        }
        .alert(
            "Delete Person",
            isPresented: $showingDeleteConfirmation,
            presenting: personToDelete
        ) { person in
            Button("Cancel", role: .cancel) {
                personToDelete = nil
            }
            Button("Delete", role: .destructive) {
                deleteSinglePerson(person)
            }
        } message: { person in
            Text("Are you sure you want to delete \(person.name)? This action cannot be undone.")
        }
        .alert(
            "Delete Multiple People",
            isPresented: $showingBulkDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedPeople()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedPeopleForDeletion.count) \(selectedPeopleForDeletion.count == 1 ? "person" : "people")? This action cannot be undone.")
        }
        .onChange(of: searchText) { _ in
            searchDebounceTimer?.invalidate()
            searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                updateFilteredResults()
            }
        }
        .onChange(of: selectedRelationshipFilter) { _ in
            updateFilteredResults()
        }
        .onChange(of: peopleManager.people) { _ in
            updateFilteredResults()
            syncCategoryOrder()
        }
        .onAppear {
            loadCategoryOrder()
            updateFilteredResults()
            syncCategoryOrder()
        }
    }
    
    // MARK: - Sticky Header

    private var stickyHeader: some View {
        HStack(spacing: 12) {
            Text("People")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()

            if isEditMode {
                // Done button in edit mode
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditMode = false
                        selectedPeopleForDeletion.removeAll()
                    }
                }) {
                    Text("Done")
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
            } else {
                // Show Edit button if there are people
                if !peopleManager.people.isEmpty {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditMode = true
                        }
                    }) {
                        Text("Edit")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Import from Contacts button
                Button(action: {
                    showingContactsImport = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 11, weight: .medium))
                        Text("Import")
                            .font(FontManager.geist(size: 12, weight: .medium))
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())

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
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Sorted Grouped People

    private var sortedGroupedPeople: [(groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])] {
        // If no custom order, return as is
        if categoryOrder.isEmpty {
            return groupedPeopleCache
        }

        // Sort according to custom order
        return groupedPeopleCache.sorted { group1, group2 in
            let index1 = categoryOrder.firstIndex(of: group1.groupKey) ?? Int.max
            let index2 = categoryOrder.firstIndex(of: group2.groupKey) ?? Int.max
            return index1 < index2
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
                    LazyHStack(spacing: 10) {
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
            // Relationship filter chips (hidden in edit mode – edit mode is for selecting/reordering)
            if !isEditMode {
                relationshipFilterChips
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            }

            // People list content
            if filteredPeopleCache.isEmpty {
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
                // No nested ScrollView – the outer ScrollView handles scrolling
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

                // Show chips for all groups (standard + custom)
                ForEach(groupedPeopleCache, id: \.groupKey) { group in
                    filterChip(
                        title: group.displayName,
                        isSelected: selectedRelationshipFilter == group.groupKey
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedRelationshipFilter = selectedRelationshipFilter == group.groupKey ? nil : group.groupKey
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
        VStack(spacing: 0) {
            ForEach(sortedGroupedPeople, id: \.groupKey) { group in
                // Section header
                sectionHeader(groupKey: group.groupKey, displayName: group.displayName, count: group.people.count)

                // People rows
                ForEach(group.people) { person in
                    PersonRowView(
                        person: person,
                        colorScheme: colorScheme,
                        isEditMode: isEditMode,
                        isSelected: selectedPeopleForDeletion.contains(person.id),
                        onTap: {
                            if isEditMode {
                                toggleSelection(person.id)
                            } else {
                                selectedPerson = person
                            }
                        },
                        onFavouriteTap: {
                            peopleManager.toggleFavourite(for: person.id)
                        },
                        onLongPress: {
                            personToDelete = person
                            showingDeleteConfirmation = true
                        }
                    )

                    if person.id != group.people.last?.id {
                        Divider()
                            .padding(.leading, 84)
                            .opacity(0.2)
                    }
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

    private func sectionHeader(groupKey: String, displayName: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(displayName.uppercased())
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))

            Text("(\(count))")
                .font(FontManager.geist(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))

            Spacer()

            // Up / Down arrows in edit mode (same pattern as home page widgets)
            if isEditMode {
                HStack(spacing: 6) {
                    Button {
                        moveCategoryUp(groupKey)
                    } label: {
                        Image(systemName: "chevron.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(colorScheme == .dark ? Color(white: 0.7) : Color(white: 0.3))
                            .background(Circle().fill(colorScheme == .dark ? Color.black : Color.white).frame(width: 18, height: 18))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(canMoveCategoryUp(groupKey) ? 1.0 : 0.3)
                    .disabled(!canMoveCategoryUp(groupKey))

                    Button {
                        moveCategoryDown(groupKey)
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(colorScheme == .dark ? Color(white: 0.7) : Color(white: 0.3))
                            .background(Circle().fill(colorScheme == .dark ? Color.black : Color.white).frame(width: 18, height: 18))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .opacity(canMoveCategoryDown(groupKey) ? 1.0 : 0.3)
                    .disabled(!canMoveCategoryDown(groupKey))
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 20)
        .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
    }

    // MARK: - Sticky Delete Footer

    private var stickyDeleteFooter: some View {
        VStack(spacing: 0) {
            Button(action: {
                if !selectedPeopleForDeletion.isEmpty {
                    showingBulkDeleteConfirmation = true
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(selectedPeopleForDeletion.isEmpty
                        ? "Select people to delete"
                        : "Delete \(selectedPeopleForDeletion.count) \(selectedPeopleForDeletion.count == 1 ? "Person" : "People")")
                        .font(FontManager.geist(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(selectedPeopleForDeletion.isEmpty
                            ? (colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.3))
                            : Color.red)
                )
                .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(selectedPeopleForDeletion.isEmpty)
        }
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? Color.black : Color(UIColor.systemBackground))
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 10, x: 0, y: -5)
    }

    // MARK: - Category Reordering

    /// Sync categoryOrder with current groups (add new, remove stale)
    private func syncCategoryOrder() {
        let currentKeys = groupedPeopleCache.map { $0.groupKey }
        var merged: [String] = []
        // Keep existing ordered keys that still exist
        for key in categoryOrder where currentKeys.contains(key) {
            merged.append(key)
        }
        // Append any new keys at the end
        for key in currentKeys where !merged.contains(key) {
            merged.append(key)
        }
        categoryOrder = merged
    }

    private func canMoveCategoryUp(_ groupKey: String) -> Bool {
        guard let index = categoryOrder.firstIndex(of: groupKey) else { return false }
        return index > 0
    }

    private func canMoveCategoryDown(_ groupKey: String) -> Bool {
        guard let index = categoryOrder.firstIndex(of: groupKey) else { return false }
        return index < categoryOrder.count - 1
    }

    private func moveCategoryUp(_ groupKey: String) {
        guard let index = categoryOrder.firstIndex(of: groupKey), index > 0 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            categoryOrder.swapAt(index, index - 1)
        }
        HapticManager.shared.selection()
        saveCategoryOrder()
    }

    private func moveCategoryDown(_ groupKey: String) {
        guard let index = categoryOrder.firstIndex(of: groupKey), index < categoryOrder.count - 1 else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            categoryOrder.swapAt(index, index + 1)
        }
        HapticManager.shared.selection()
        saveCategoryOrder()
    }

    private func saveCategoryOrder() {
        UserDefaults.standard.set(categoryOrder, forKey: Self.categoryOrderKey)
    }

    private func loadCategoryOrder() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.categoryOrderKey) {
            categoryOrder = saved
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ personId: UUID) {
        if selectedPeopleForDeletion.contains(personId) {
            selectedPeopleForDeletion.remove(personId)
        } else {
            selectedPeopleForDeletion.insert(personId)
        }
    }

    private func deleteSinglePerson(_ person: Person) {
        peopleManager.deletePerson(person)
        personToDelete = nil
    }

    private func deleteSelectedPeople() {
        let peopleToDelete = peopleManager.people.filter { selectedPeopleForDeletion.contains($0.id) }
        for person in peopleToDelete {
            peopleManager.deletePerson(person)
        }
        selectedPeopleForDeletion.removeAll()
        isEditMode = false
    }

}

// MARK: - Person Row View

struct PersonRowView: View {
    let person: Person
    let colorScheme: ColorScheme
    var isEditMode: Bool = false
    var isSelected: Bool = false
    let onTap: () -> Void
    let onFavouriteTap: () -> Void
    var onLongPress: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Selection circle in edit mode
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected
                        ? (colorScheme == .dark ? .white : .black)
                        : (colorScheme == .dark ? .white.opacity(0.25) : .black.opacity(0.25)))
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }

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

            // Favourite button (hidden in edit mode)
            if !isEditMode {
                Button(action: onFavouriteTap) {
                    Image(systemName: person.isFavourite ? "star.fill" : "star")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(person.isFavourite ? .yellow : (colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3)))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if !isEditMode, let onLongPress = onLongPress {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onLongPress()
            }
        }
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
