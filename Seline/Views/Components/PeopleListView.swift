import SwiftUI

extension Notification.Name {
    static let peopleHubAddRequested = Notification.Name("PeopleHubAddRequested")
    static let peopleHubImportRequested = Notification.Name("PeopleHubImportRequested")
}

struct PeopleListView: View {
    private struct PeopleActivityItem: Identifiable, Hashable {
        let id: String
        let title: String
    }

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
    @State private var favouritePeopleCache: [Person] = []
    @State private var upcomingBirthdayPeopleCache: [(person: Person, daysUntil: Int)] = []
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
        favouritePeopleCache
    }

    private var upcomingBirthdayPeople: [(person: Person, daysUntil: Int)] {
        upcomingBirthdayPeopleCache
    }

    private var sortedGroupedPeople: [(groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])] {
        guard !categoryOrder.isEmpty else { return groupedPeopleCache }

        return groupedPeopleCache.sorted { group1, group2 in
            let index1 = categoryOrder.firstIndex(of: group1.groupKey) ?? Int.max
            let index2 = categoryOrder.firstIndex(of: group2.groupKey) ?? Int.max
            return index1 < index2
        }
    }

    private var heroSupportingText: String {
        "Your close circle, family, and important connections in one place."
    }

    private var heroHeadlineText: String {
        let count = peopleManager.people.count
        guard count > 0 else { return "Build your people hub" }
        return "\(count) \(count == 1 ? "person" : "people") in your circle"
    }

    private var recentActivityItems: [PeopleActivityItem] {
        var items: [PeopleActivityItem] = []
        var seenTitles = Set<String>()

        func appendActivity(id: String, title: String?) {
            guard let title, !title.isEmpty, !seenTitles.contains(title) else { return }
            seenTitles.insert(title)
            items.append(PeopleActivityItem(id: id, title: title))
        }

        if let updatedPerson = peopleManager.people.max(by: { $0.dateModified < $1.dateModified }) {
            appendActivity(
                id: "updated-\(updatedPerson.id.uuidString)",
                title: "\(updatedPerson.displayName) was updated \(peopleRelativeDate(updatedPerson.dateModified))."
            )
        }

        if let birthday = upcomingBirthdayPeople.first {
            appendActivity(
                id: "birthday-\(birthday.person.id.uuidString)",
                title: "\(birthday.person.displayName) has a birthday \(birthdayTimingText(birthday.daysUntil))."
            )
        }

        if let linkedPerson = peopleManager.people.max(by: { connectionWeight(for: $0) < connectionWeight(for: $1) }) {
            appendActivity(
                id: "links-\(linkedPerson.id.uuidString)",
                title: linkedContextText(for: linkedPerson)
            )
        }

        if favouritePeople.count > 0 {
            appendActivity(
                id: "favourites-count",
                title: "\(favouritePeople.count) favourite\(favouritePeople.count == 1 ? "" : "s") are pinned for quick access."
            )
        }

        return Array(items.prefix(3))
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
                refreshSummaryCache()
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
                refreshSummaryCache()
            }
            .onDisappear {
                searchDebouncer.cancel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .peopleHubAddRequested)) { _ in
                if !isEditMode {
                    showingAddPerson = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .peopleHubImportRequested)) { _ in
                if !isEditMode {
                    showingContactsImport = true
                }
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
        .blur(radius: isSearchActive && !internalSearchText.isEmpty ? 8 : 0)
        .allowsHitTesting(!(isSearchActive && !internalSearchText.isEmpty))
    }

    private var searchOverlayView: some View {
        VStack(spacing: 0) {
            UnifiedSearchBar(
                searchText: $internalSearchText,
                isFocused: $isSearchFocused,
                placeholder: "Search people",
                onCancel: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSearchActive = false
                        isSearchFocused = false
                        internalSearchText = ""
                        updateFilteredResults()
                    }
                },
                colorScheme: colorScheme,
                variant: peoplePageVariant
            )
            .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
            .padding(.top, 8)

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
        .transition(.move(edge: .top).combined(with: .opacity))
        .zIndex(100)
    }

    private var peopleHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    if showsHeader {
                        Text("PEOPLE")
                            .font(FontManager.geist(size: 10, weight: .semibold))
                            .tracking(1.8)
                            .foregroundColor(Color.appTextSecondary(colorScheme))

                        Text(heroHeadlineText)
                            .font(FontManager.geist(size: 28, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                            .lineLimit(2)

                        Text(heroSupportingText)
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                    } else if !peopleManager.people.isEmpty {
                        iconActionPill(systemImage: "slider.horizontal.3", accessibilityLabel: "Edit people") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditMode = true
                            }
                        }
                    }
                }
            }

            if peopleManager.people.isEmpty {
                emptyHeroState
            } else if !favouritePeople.isEmpty && !isEditMode {
                favoritesOverview
            }
        }
        .padding(18)
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
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(Color.appTextSecondary(colorScheme))
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
                            .padding(.vertical, 11)
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
                VStack(spacing: 18) {
                    if !recentActivityItems.isEmpty && !isEditMode {
                        recentActivitySection
                    }

                    ForEach(sortedGroupedPeople, id: \.groupKey) { group in
                        relationshipGroupSection(group)
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

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundColor(Color.appTextSecondary(colorScheme))

            VStack(spacing: 0) {
                ForEach(Array(recentActivityItems.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color(red: 0.98, green: 0.64, blue: 0.41).opacity(colorScheme == .dark ? 0.95 : 0.9))
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)

                        Text(item.title)
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 11)

                    if index < recentActivityItems.count - 1 {
                        Divider()
                            .overlay(Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.7 : 0.9))
                            .padding(.leading, 18)
                    }
                }
            }
            .padding(.horizontal, 14)
            .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
        }
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

    private func relationshipGroupSection(_ group: (groupKey: String, displayName: String, relationshipType: RelationshipType?, people: [Person])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(group.displayName.uppercased())
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .tracking(1.6)
                    .foregroundColor(Color.appTextSecondary(colorScheme))

                Text("\(group.people.count)")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(Color.appTextSecondary(colorScheme))

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

            VStack(spacing: 0) {
                ForEach(Array(group.people.enumerated()), id: \.element.id) { index, person in
                    PersonRowView(
                        person: person,
                        colorScheme: colorScheme,
                        style: .plain,
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

                    if index < group.people.count - 1 {
                        Divider()
                            .overlay(Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.7 : 0.9))
                            .padding(.leading, isEditMode ? 92 : 70)
                    }
                }
            }
        }
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

    private func refreshSummaryCache() {
        let allPeople = peopleManager.people
        let favouritePeople = peopleManager.getFavourites()
        let upcomingBirthdays = allPeople
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

        favouritePeopleCache = favouritePeople
        upcomingBirthdayPeopleCache = upcomingBirthdays
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

    private func birthdayTimingText(_ daysUntil: Int) -> String {
        if daysUntil == 0 {
            return "today"
        }
        if daysUntil == 1 {
            return "tomorrow"
        }
        return "in \(daysUntil) days"
    }

    private func connectionWeight(for person: Person) -> Int {
        (person.favouritePlaceIds?.count ?? 0) + (person.linkedPeople?.count ?? 0)
    }

    private func linkedContextText(for person: Person) -> String? {
        let placeCount = person.favouritePlaceIds?.count ?? 0
        let relatedPeopleCount = person.linkedPeople?.count ?? 0
        guard placeCount > 0 || relatedPeopleCount > 0 else { return nil }

        var parts: [String] = []
        if placeCount > 0 {
            parts.append("\(placeCount) place\(placeCount == 1 ? "" : "s")")
        }
        if relatedPeopleCount > 0 {
            parts.append("\(relatedPeopleCount) relationship\(relatedPeopleCount == 1 ? "" : "s")")
        }
        return "\(person.displayName) is connected across \(parts.joined(separator: " and "))."
    }

    private func peopleRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct PersonRowView: View {
    enum Style: Equatable {
        case card
        case plain
    }

    let person: Person
    let colorScheme: ColorScheme
    var style: Style = .card
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
        rowContent
            .padding(rowPadding)
            .background(rowBackground)
            .overlay(rowBorder)
            .contentShape(Rectangle())
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

    private var rowContent: some View {
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
                Button(action: onFavouriteTap) {
                    Image(systemName: person.isFavourite ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(person.isFavourite ? .yellow : Color.appTextSecondary(colorScheme))
                        .frame(width: 30, height: 30)
                        .background(favouriteButtonBackground)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private var rowPadding: EdgeInsets {
        switch style {
        case .card:
            return EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        case .plain:
            return EdgeInsets(top: 14, leading: 0, bottom: 14, trailing: 0)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if style == .card {
            RoundedRectangle(cornerRadius: 20)
                .fill(isSelected ? Color.appChipStrong(colorScheme) : Color.appInnerSurface(colorScheme))
        } else if isSelected {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.appChipStrong(colorScheme))
        }
    }

    @ViewBuilder
    private var rowBorder: some View {
        if style == .card {
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    isSelected
                        ? (colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.18))
                        : Color.appBorder(colorScheme).opacity(colorScheme == .dark ? 0.85 : 0.7),
                    lineWidth: 1
                )
        } else if isSelected {
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.14),
                    lineWidth: 1
                )
        }
    }

    @ViewBuilder
    private var favouriteButtonBackground: some View {
        if style == .card {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.appChip(colorScheme))
        } else {
            Circle()
                .fill(Color.clear)
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
