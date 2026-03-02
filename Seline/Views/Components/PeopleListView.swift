import SwiftUI

struct PeopleListView: View {
    @ObservedObject var peopleManager: PeopleManager
    @ObservedObject var locationsManager: LocationsManager
    let colorScheme: ColorScheme
    let searchText: String
    @Binding var isSearchActive: Bool
    let showsHeader: Bool

    @State private var selectedPerson: Person? = nil
    @State private var showingAddPerson = false
    @State private var showingContactsImport = false
    @State private var selectedRelationshipFilter: String? = nil

    @State private var isEditMode = false
    @State private var selectedPeopleForDeletion: Set<UUID> = []
    @State private var showingDeleteConfirmation = false
    @State private var showingBulkDeleteConfirmation = false
    @State private var personToDelete: Person? = nil

    @State private var categoryOrder: [String] = []
    @State private var filteredPeopleCache: [Person] = []
    @State private var groupedPeopleCache: [(groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])] = []

    @State private var searchDebouncer = DebouncedTaskRunner()
    @State private var internalSearchText = ""
    @FocusState private var isSearchFocused: Bool

    private static let categoryOrderKey = "people_category_order"

    init(
        peopleManager: PeopleManager,
        locationsManager: LocationsManager,
        colorScheme: ColorScheme,
        searchText: String,
        isSearchActive: Binding<Bool>,
        showsHeader: Bool = true
    ) {
        self.peopleManager = peopleManager
        self.locationsManager = locationsManager
        self.colorScheme = colorScheme
        self.searchText = searchText
        self._isSearchActive = isSearchActive
        self.showsHeader = showsHeader
    }

    private var favouritePeople: [Person] {
        peopleManager.getFavourites()
    }

    private var upcomingBirthdayPeople: [(person: Person, daysUntil: Int)] {
        peopleManager.people
            .compactMap { person -> (person: Person, daysUntil: Int)? in
                guard let daysUntil = peopleDaysUntilBirthday(person), daysUntil <= 30 else { return nil }
                return (person, daysUntil)
            }
            .sorted {
                if $0.daysUntil == $1.daysUntil {
                    return $0.person.displayName < $1.person.displayName
                }
                return $0.daysUntil < $1.daysUntil
            }
    }

    private var peopleSummaryText: String {
        guard !peopleManager.people.isEmpty else {
            return "Keep people connected to places, timeline visits, gifts, and notes."
        }

        var parts = ["\(peopleManager.people.count) saved"]
        let favouriteCount = favouritePeople.count
        if favouriteCount > 0 {
            parts.append("\(favouriteCount) favorites")
        }
        let birthdayCount = upcomingBirthdayPeople.count
        if birthdayCount > 0 {
            parts.append("\(birthdayCount) birthdays soon")
        }
        return parts.joined(separator: " · ")
    }

    private var sortedGroupedPeople: [(groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])] {
        guard !categoryOrder.isEmpty else { return groupedPeopleCache }

        return groupedPeopleCache.sorted { group1, group2 in
            let index1 = categoryOrder.firstIndex(of: group1.groupKey) ?? Int.max
            let index2 = categoryOrder.firstIndex(of: group2.groupKey) ?? Int.max
            return index1 < index2
        }
    }

    var body: some View {
        lifecycle(alerts(sheets(bodyContent)))
    }

    private var bodyContent: some View {
        ZStack(alignment: .top) {
            mainContentView

            if isSearchActive {
                searchOverlayView
            }
        }
    }

    @ViewBuilder
    private func sheets<Content: View>(_ content: Content) -> some View {
        content
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
    }

    @ViewBuilder
    private func alerts<Content: View>(_ content: Content) -> some View {
        content
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
    }

    @ViewBuilder
    private func lifecycle<Content: View>(_ content: Content) -> some View {
        content
            .onChange(of: searchText) { _ in
                searchDebouncer.schedule(delay: 0.3) {
                    updateFilteredResults()
                }
            }
            .onChange(of: internalSearchText) { _ in
                searchDebouncer.schedule(delay: 0.3) {
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
            .onChange(of: isSearchActive) { newValue in
                if newValue {
                    isSearchFocused = true
                }
            }
            .onAppear {
                loadCategoryOrder()
                updateFilteredResults()
                syncCategoryOrder()
            }
            .onDisappear {
                searchDebouncer.cancel()
            }
    }

    private var mainContentView: some View {
        ZStack {
            AppAmbientBackgroundLayer(
                colorScheme: colorScheme,
                variant: peoplePageVariant
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    peopleHeroCard
                    peopleDirectorySection
                }
                .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                .padding(.top, 12)
                .padding(.bottom, isEditMode ? 22 : 30)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isEditMode {
                stickyDeleteFooter
            }
        }
        .opacity(isSearchActive && !internalSearchText.isEmpty ? 0.3 : 1.0)
        .allowsHitTesting(!isSearchActive)
    }

    private var searchOverlayView: some View {
        VStack(spacing: 0) {
            UnifiedSearchBar(
                searchText: $internalSearchText,
                isFocused: $isSearchFocused,
                placeholder: "Search people, gifts, notes",
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchActive = false
                        isSearchFocused = false
                        internalSearchText = ""
                        updateFilteredResults()
                    }
                },
                colorScheme: colorScheme
            )
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .padding(.top, 8)
            .background(Color.clear)

            if !internalSearchText.isEmpty {
                SearchResultsListView(
                    results: filteredPeopleCache,
                    emptyMessage: "No people match your search",
                    rowContent: { person in
                        AnyView(
                            PersonRowView(
                                person: person,
                                colorScheme: colorScheme,
                                isEditMode: false,
                                isSelected: false,
                                onTap: {
                                    selectedPerson = person
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isSearchActive = false
                                        internalSearchText = ""
                                    }
                                },
                                onFavouriteTap: {
                                    peopleManager.toggleFavourite(for: person.id)
                                }
                            )
                        )
                    },
                    colorScheme: colorScheme
                )
            }
        }
        .background(
            AppAmbientBackgroundLayer(
                colorScheme: colorScheme,
                variant: peoplePageVariant
            )
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(100)
    }

    private var peopleHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if showsHeader {
                        Text("People")
                            .font(FontManager.geist(size: 28, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                    }

                    Text(isEditMode ? "Select people to delete or reorder groups." : peopleSummaryText)
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    if isEditMode {
                        secondaryActionButton(title: "Done", systemImage: "checkmark") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditMode = false
                                selectedPeopleForDeletion.removeAll()
                            }
                        }
                    } else {
                        if !peopleManager.people.isEmpty {
                            iconActionPill(systemImage: "slider.horizontal.3", accessibilityLabel: "Edit people") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditMode = true
                                }
                            }
                        }

                        iconActionPill(systemImage: "person.crop.rectangle.stack", accessibilityLabel: "Import contacts") {
                            showingContactsImport = true
                        }

                        primaryIconActionPill(systemImage: "plus", accessibilityLabel: "Add person") {
                            showingAddPerson = true
                        }
                    }
                }
            }

            Button(action: activateSearch) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.appTextSecondary(colorScheme))

                    Text("Search people, gifts, notes")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 16)
            }
            .buttonStyle(PlainButtonStyle())

            HStack(spacing: 10) {
                metricTile(label: "Total", value: "\(peopleManager.people.count)")
                metricTile(label: "Favorites", value: "\(favouritePeople.count)")
                metricTile(label: "Birthdays soon", value: "\(upcomingBirthdayPeople.count)")
            }

            if peopleManager.people.isEmpty {
                emptyHeroState
            } else if !favouritePeople.isEmpty && !isEditMode {
                favoritesOverview
            }
        }
        .padding(16)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: peoplePageVariant,
            cornerRadius: 24,
            highlightStrength: 0.95
        )
    }

    private var emptyHeroState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a tighter relationship hub")
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            Text("Save the people you care about, then connect them to visits, places, and receipts so the app becomes more useful over time.")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                primaryActionButton(title: "Add Person", systemImage: "plus") {
                    showingAddPerson = true
                }

                secondaryActionButton(title: "Import Contacts", systemImage: "arrow.down.doc") {
                    showingContactsImport = true
                }
            }
        }
        .padding(16)
        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 20)
    }

    private var favoritesOverview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Favourites")
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(favouritePeople) { person in
                        Button(action: {
                            selectedPerson = person
                        }) {
                            HStack(spacing: 10) {
                                personMiniAvatar(person)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(person.displayName)
                                        .font(FontManager.geist(size: 13, weight: .semibold))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .lineLimit(1)

                                    Text(person.relationshipDisplayText)
                                        .font(FontManager.geist(size: 11, weight: .regular))
                                        .foregroundColor(Color.appTextSecondary(colorScheme))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 16)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
    }

    private var peopleDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Relationship")
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            if !peopleManager.people.isEmpty && !isEditMode {
                relationshipFilterChips
            }

            if filteredPeopleCache.isEmpty {
                emptyDirectoryState
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedGroupedPeople, id: \.groupKey) { group in
                        groupCard(group)
                    }
                }
            }
        }
        .padding(16)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: peopleSectionVariant,
            cornerRadius: 24,
            highlightStrength: 0.5
        )
    }

    private var relationshipFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", isSelected: selectedRelationshipFilter == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedRelationshipFilter = nil
                    }
                }

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
            .padding(.vertical, 2)
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(isSelected ? (colorScheme == .dark ? .black : .white) : Color.appTextSecondary(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? (colorScheme == .dark ? Color.white : Color.black)
                              : Color.appChip(colorScheme))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var emptyDirectoryState: some View {
        VStack(spacing: 14) {
            Image(systemName: peopleManager.people.isEmpty ? "person.2.fill" : "line.3.horizontal.decrease.circle")
                .font(FontManager.geist(size: 40, weight: .light))
                .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.7))

            Text(peopleManager.people.isEmpty ? "No people saved yet" : "No people match your filter")
                .font(FontManager.geist(size: 16, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            Text(peopleManager.people.isEmpty
                 ? "Use Add or Import above to create a relationship hub tied to places and visits."
                 : "Try a different relationship chip or clear the current filter.")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if selectedRelationshipFilter != nil {
                secondaryActionButton(title: "Clear Filter", systemImage: "xmark") {
                    selectedRelationshipFilter = nil
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 24)
    }

    private func groupCard(_ group: (groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(group.displayName)
                            .font(FontManager.geist(size: 17, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text("\(group.people.count)")
                            .font(FontManager.geist(size: 11, weight: .semibold))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.appChip(colorScheme))
                            )
                    }
                }

                Spacer(minLength: 8)

                if isEditMode {
                    HStack(spacing: 6) {
                        groupReorderButton(systemImage: "chevron.up", isEnabled: canMoveCategoryUp(group.groupKey)) {
                            moveCategoryUp(group.groupKey)
                        }

                        groupReorderButton(systemImage: "chevron.down", isEnabled: canMoveCategoryDown(group.groupKey)) {
                            moveCategoryDown(group.groupKey)
                        }
                    }
                }
            }

            VStack(spacing: 10) {
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
                }
            }
        }
        .padding(16)
        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 24)
    }

    private func groupReorderButton(systemImage: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme).opacity(isEnabled ? 1 : 0.35))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.appChip(colorScheme))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }

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
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selectedPeopleForDeletion.isEmpty
                            ? (colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.28))
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
                .fill(Color.appBackground(colorScheme))
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 10, x: 0, y: -5)
    }

    private func metricTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .lineLimit(1)

            Text(value)
                .font(FontManager.geist(size: 23, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
    }

    private func personMiniAvatar(_ person: Person) -> some View {
        Group {
            if let photoURL = person.photoURL, !photoURL.isEmpty {
                CachedAsyncImage(url: photoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    miniInitialsAvatar(for: person)
                }
            } else {
                miniInitialsAvatar(for: person)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func miniInitialsAvatar(for person: Person) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(peopleRelationshipColor(person.relationship))
            .overlay(
                Text(person.initials)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    private func iconActionPill(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .background(
                    Circle()
                        .fill(Color.appChip(colorScheme))
                )
        }
        .accessibilityLabel(accessibilityLabel)
        .buttonStyle(PlainButtonStyle())
    }

    private func primaryIconActionPill(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundColor(.black)
                .background(
                    Circle()
                        .fill(Color(red: 0.98, green: 0.64, blue: 0.41))
                )
        }
        .accessibilityLabel(accessibilityLabel)
        .buttonStyle(PlainButtonStyle())
    }

    private func primaryActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(FontManager.geist(size: 13, weight: .semibold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color(red: 0.98, green: 0.64, blue: 0.41))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func secondaryActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(FontManager.geist(size: 12, weight: .medium))
            }
            .foregroundColor(Color.appTextPrimary(colorScheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.appChip(colorScheme))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func activateSearch() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchActive = true
            isSearchFocused = true
        }
    }

    private var peoplePageVariant: AppAmbientBackgroundVariant {
        .bottomTrailing
    }

    private var peopleSectionVariant: AppAmbientBackgroundVariant {
        .topLeading
    }

    private func updateFilteredResults() {
        var result = peopleManager.people
        let activeSearchText = isSearchActive ? internalSearchText : searchText

        if !activeSearchText.isEmpty {
            let lowercasedSearch = activeSearchText.lowercased()
            result = result.filter { person in
                person.name.lowercased().contains(lowercasedSearch) ||
                (person.nickname?.lowercased().contains(lowercasedSearch) ?? false) ||
                person.relationshipDisplayText.lowercased().contains(lowercasedSearch) ||
                (person.notes?.lowercased().contains(lowercasedSearch) ?? false) ||
                (person.favouriteFood?.lowercased().contains(lowercasedSearch) ?? false) ||
                (person.favouriteGift?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }

        if let filter = selectedRelationshipFilter {
            result = result.filter { person in
                if filter.hasPrefix("custom_") {
                    let customName = String(filter.dropFirst("custom_".count))
                    return person.relationship == .other && person.customRelationship == customName
                } else if filter.hasPrefix("type_") {
                    let typeRawValue = String(filter.dropFirst("type_".count))
                    return person.relationship.rawValue == typeRawValue
                } else {
                    return false
                }
            }
        }

        filteredPeopleCache = result

        let groupedDict = Dictionary(grouping: result) { person -> String in
            if person.relationship == .other, let custom = person.customRelationship, !custom.isEmpty {
                return "custom_\(custom)"
            } else {
                return "type_\(person.relationship.rawValue)"
            }
        }

        var groups: [(groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])] = []

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

    private func syncCategoryOrder() {
        let currentKeys = groupedPeopleCache.map { $0.groupKey }
        var merged: [String] = []
        for key in categoryOrder where currentKeys.contains(key) {
            merged.append(key)
        }
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

struct PersonRowView: View {
    let person: Person
    let colorScheme: ColorScheme
    var isEditMode: Bool = false
    var isSelected: Bool = false
    let onTap: () -> Void
    let onFavouriteTap: () -> Void
    var onLongPress: (() -> Void)? = nil

    private var linkedPlacesCount: Int {
        person.favouritePlaceIds?.count ?? 0
    }

    private var linkedPeopleCount: Int {
        person.linkedPeople?.count ?? 0
    }

    private var birthdayBadgeText: String? {
        guard let daysUntil = peopleDaysUntilBirthday(person) else {
            return nil
        }

        if daysUntil == 0 {
            return "Birthday today"
        }
        if daysUntil == 1 {
            return "Birthday tomorrow"
        }
        if daysUntil <= 30 {
            return "Birthday in \(daysUntil)d"
        }
        return nil
    }

    private var rowContextText: String {
        if let notePreview = sanitizedPreview(person.notes) {
            return notePreview
        }

        if let gift = trimmedValue(person.favouriteGift) {
            return "Gift idea: \(gift)"
        }

        if let food = trimmedValue(person.favouriteFood) {
            return "Likes \(food)"
        }

        if let interest = person.interests?.compactMap(trimmedValue).first {
            return "Interest: \(interest)"
        }

        if linkedPlacesCount > 0 || linkedPeopleCount > 0 {
            var parts: [String] = []
            if linkedPlacesCount > 0 {
                parts.append("\(linkedPlacesCount) place\(linkedPlacesCount == 1 ? "" : "s") linked")
            }
            if linkedPeopleCount > 0 {
                parts.append("\(linkedPeopleCount) relationship\(linkedPeopleCount == 1 ? "" : "s") mapped")
            }
            return parts.joined(separator: " · ")
        }

        return "Updated \(relativeDate(person.dateModified))"
    }

    var body: some View {
        HStack(spacing: 14) {
            if isEditMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected
                        ? (colorScheme == .dark ? .white : .black)
                        : Color.appTextSecondary(colorScheme).opacity(0.4))
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
            }

            personAvatar

            VStack(alignment: .leading, spacing: 8) {
                Text(person.displayName)
                    .font(FontManager.geist(size: 15, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .lineLimit(1)

                if let birthdayBadgeText {
                    rowBadge(
                        icon: "gift.fill",
                        text: birthdayBadgeText,
                        fill: Color(red: 0.98, green: 0.64, blue: 0.41).opacity(colorScheme == .dark ? 0.18 : 0.14),
                        foreground: Color(red: 0.98, green: 0.64, blue: 0.41)
                    )
                }

                Text(rowContextText)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            if !isEditMode {
                VStack(alignment: .trailing, spacing: 10) {
                    Button(action: onFavouriteTap) {
                        Image(systemName: person.isFavourite ? "star.fill" : "star")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(person.isFavourite ? .yellow : Color.appTextSecondary(colorScheme))
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.appChip(colorScheme))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.7))
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(isSelected ? Color.appChipStrong(colorScheme) : Color.appInnerSurface(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isSelected
                        ? (colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.18))
                        : Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.85 : 0.7),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if !isEditMode, let onLongPress {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onLongPress()
            }
        }
    }

    private var personAvatar: some View {
        Group {
            if let photoURL = person.photoURL, !photoURL.isEmpty {
                CachedAsyncImage(url: photoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsAvatar
                }
            } else {
                initialsAvatar
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.06 : 0), lineWidth: 1)
        )
    }

    private var initialsAvatar: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(peopleRelationshipColor(person.relationship))
            .overlay(
                Text(person.initials)
                    .font(FontManager.geist(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    private func rowBadge(icon: String, text: String, fill: Color, foreground: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(FontManager.geist(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(fill)
        )
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private func peopleRelationshipColor(_ relationship: RelationshipType) -> Color {
    switch relationship {
    case .family:
        return Color(red: 0.80, green: 0.34, blue: 0.34)
    case .partner:
        return Color(red: 0.88, green: 0.39, blue: 0.54)
    case .closeFriend:
        return Color(red: 0.40, green: 0.60, blue: 0.95)
    case .friend:
        return Color(red: 0.34, green: 0.74, blue: 0.60)
    case .coworker:
        return Color(red: 0.52, green: 0.54, blue: 0.76)
    case .classmate:
        return Color(red: 0.61, green: 0.45, blue: 0.79)
    case .neighbor:
        return Color(red: 0.51, green: 0.66, blue: 0.54)
    case .mentor:
        return Color(red: 0.84, green: 0.65, blue: 0.29)
    case .acquaintance:
        return Color(red: 0.53, green: 0.56, blue: 0.61)
    case .other:
        return Color(red: 0.44, green: 0.46, blue: 0.50)
    }
}

private func peopleDaysUntilBirthday(_ person: Person, from referenceDate: Date = Date()) -> Int? {
    guard let birthday = person.birthday else { return nil }

    let calendar = Calendar.current
    let monthDay = calendar.dateComponents([.month, .day], from: birthday)
    guard let nextBirthday = calendar.nextDate(
        after: calendar.startOfDay(for: referenceDate).addingTimeInterval(-1),
        matching: monthDay,
        matchingPolicy: .nextTime,
        direction: .forward
    ) else {
        return nil
    }

    let startOfToday = calendar.startOfDay(for: referenceDate)
    let startOfBirthday = calendar.startOfDay(for: nextBirthday)
    return calendar.dateComponents([.day], from: startOfToday, to: startOfBirthday).day
}

private func trimmedValue(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func sanitizedPreview(_ value: String?) -> String? {
    guard let trimmed = trimmedValue(value) else { return nil }
    let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
    if singleLine.count <= 68 {
        return singleLine
    }
    let endIndex = singleLine.index(singleLine.startIndex, offsetBy: 68)
    return String(singleLine[..<endIndex]) + "..."
}

#Preview {
    struct PreviewWrapper: View {
        @State private var isSearchActive = false

        var body: some View {
            PeopleListView(
                peopleManager: PeopleManager.shared,
                locationsManager: LocationsManager.shared,
                colorScheme: .dark,
                searchText: "",
                isSearchActive: $isSearchActive
            )
        }
    }

    return PreviewWrapper()
}
