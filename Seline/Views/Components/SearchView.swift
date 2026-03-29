import SwiftUI

struct SearchView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let searchIndex = SearchIndexState.shared

    let isVisible: Bool
    @Binding var selectedTab: PrimaryTab
    @Binding var selectedFolder: String?
    var onOpenEmail: (Email) -> Void
    var onOpenTask: (TaskItem) -> Void
    var onOpenNote: (Note) -> Void
    var onOpenPlace: (SavedPlace) -> Void
    var onOpenPerson: (Person) -> Void

    @State private var searchText = ""
    @State private var searchResults: [OverlaySearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var preview = SearchPreviewData.empty
    @State private var recentSearches = SearchRecentQueryStore.load()
    @FocusState private var isSearchFocused: Bool

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var landingRecentQueries: [String] {
        Array(recentSearches.prefix(4))
    }

    private var searchResultsSummary: String {
        let matchLabel = searchResults.count == 1 ? "match" : "matches"
        return "\(searchResults.count) \(matchLabel) across Seline"
    }

    private var contentHorizontalPadding: CGFloat {
        16
    }

    private func handleSelection(_ result: OverlaySearchResult) {
        rememberSearchQuery()
        HapticManager.shared.selection()
        isSearchFocused = false

        switch result.type {
        case .email:
            if let email = result.email {
                onOpenEmail(email)
            }
        case .event:
            if let task = result.task {
                onOpenTask(task)
            }
        case .note, .receipt:
            if let note = result.note {
                onOpenNote(note)
            }
        case .location:
            if let place = result.location {
                onOpenPlace(place)
            }
        case .folder:
            if let folder = result.category {
                selectedFolder = folder
                selectedTab = .maps
            }
        case .person:
            if let person = result.person {
                onOpenPerson(person)
            }
        case .recurringExpense:
            selectedTab = .notes
            NotificationCenter.default.post(name: .openRecurringFromMainApp, object: nil)
        }
    }

    private func refreshSupplementaryState() {
        preview = searchIndex.preview
        recentSearches = SearchRecentQueryStore.load()
    }

    private func rememberSearchQuery(_ rawQuery: String? = nil) {
        let query = (rawQuery ?? trimmedSearchText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        recentSearches = SearchRecentQueryStore.record(query)
    }

    private func applyRecentSearch(_ query: String) {
        searchText = query
        recentSearches = SearchRecentQueryStore.record(query)
        isSearchFocused = true
        scheduleSearchRefresh()
    }

    private func removeRecentSearch(_ query: String) {
        recentSearches = SearchRecentQueryStore.remove(query)
    }

    private func clearRecentSearches() {
        recentSearches = SearchRecentQueryStore.clear()
    }

    private func scheduleSearchRefresh() {
        searchTask?.cancel()

        let query = trimmedSearchText
        guard isVisible, !query.isEmpty else {
            searchResults = []
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            searchResults = searchIndex.results(
                for: query,
                scopes: .searchPageScopes,
                limit: 36
            )
        }
    }

    private var titleRow: some View {
        HStack(spacing: 10) {
            Color.clear
                .frame(width: 42, height: 42)

            Spacer(minLength: 0)

            Text("Search")
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, -4)
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))

            TextField("Search mail, events, notes, places, people...", text: $searchText)
                .font(FontManager.geist(size: 15, weight: .regular))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .onSubmit {
                    rememberSearchQuery()
                    scheduleSearchRefresh()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isSearchFocused
                        ? Color.homeGlassAccent.opacity(colorScheme == .dark ? 0.42 : 0.26)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .shadow(
            color: isSearchFocused
                ? Color.homeGlassAccent.opacity(colorScheme == .dark ? 0.12 : 0.09)
                : .clear,
            radius: 18,
            x: 0,
            y: 8
        )
        .animation(.easeOut(duration: 0.18), value: isSearchFocused)
    }

    private var header: some View {
        VStack(spacing: 0) {
            titleRow

            searchField
                .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
                .padding(.bottom, 14)
        }
    }

    private var emptyStateView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if !landingRecentQueries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Recent")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(landingRecentQueries, id: \.self) { query in
                                    recentSearchChip(query)
                                }
                            }
                        }
                    }
                }

                if !preview.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Right Now")

                        VStack(spacing: 10) {
                            ForEach(preview.highlights) { highlight in
                                Button {
                                    handleSelection(highlight.result)
                                } label: {
                                    previewHighlightRow(highlight)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.bottom, 110)
        }
        .selinePrimaryPageScroll()
    }

    private var recentSearchesView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                if !recentSearches.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionHeader("Jump Back In")

                            Spacer(minLength: 0)

                            Button("Clear") {
                                clearRecentSearches()
                            }
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                            .buttonStyle(.plain)
                        }

                        VStack(spacing: 10) {
                            ForEach(recentSearches, id: \.self) { query in
                                HStack(spacing: 10) {
                                    Button {
                                        applyRecentSearch(query)
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(Color.appTextSecondary(colorScheme))
                                                .frame(width: 18)

                                            Text(query)
                                                .font(FontManager.geist(size: 15, weight: .medium))
                                                .foregroundColor(Color.appTextPrimary(colorScheme))
                                                .lineLimit(1)

                                            Spacer(minLength: 0)

                                            Image(systemName: "arrow.up.left")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(Color.appTextSecondary(colorScheme))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 14)
                                        .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 20)
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        removeRecentSearch(query)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(Color.appTextSecondary(colorScheme))
                                            .frame(width: 28, height: 28)
                                            .background(
                                                Circle()
                                                    .fill(Color.appChip(colorScheme))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }

                if !preview.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("Right Now")

                        VStack(spacing: 10) {
                            ForEach(preview.highlights) { highlight in
                                Button {
                                    handleSelection(highlight.result)
                                } label: {
                                    previewHighlightRow(highlight)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.bottom, 110)
        }
        .selinePrimaryPageScroll()
    }

    private var noResultsView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Color.homeGlassAccent.opacity(colorScheme == .dark ? 0.24 : 0.14))
                            .frame(width: 74, height: 74)

                        Image(systemName: "sparkles")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                    }

                    VStack(spacing: 8) {
                        Text("No direct matches")
                            .font(FontManager.geist(size: 22, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))

                        Text("Try a broader keyword or search by person, place, folder, or date.")
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 26)
                .appAmbientCardStyle(
                    colorScheme: colorScheme,
                    variant: .topLeading,
                    cornerRadius: 28,
                    highlightStrength: 0.8
                )
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.top, 26)
            .padding(.bottom, 110)
        }
        .selinePrimaryPageScroll()
    }

    private var resultsListView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                resultsHeroCard

                LazyVStack(spacing: 10) {
                    ForEach(searchResults) { result in
                        Button {
                            handleSelection(result)
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.appChip(colorScheme))
                                        .frame(width: 44, height: 44)

                                    Image(systemName: result.icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(FontManager.geist(size: 15, weight: .medium))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .lineLimit(1)

                                    Text(result.subtitle)
                                        .font(FontManager.geist(size: 13, weight: .regular))
                                        .foregroundColor(Color.appTextSecondary(colorScheme))
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                VStack(alignment: .trailing, spacing: 10) {
                                    Text(result.type.badgeLabel)
                                        .font(FontManager.geist(size: 11, weight: .semibold))
                                        .foregroundColor(Color.appTextSecondary(colorScheme))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(Color.appChip(colorScheme))
                                        )

                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.7))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 20)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, contentHorizontalPadding)
            .padding(.bottom, 110)
        }
        .selinePrimaryPageScroll()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(FontManager.geist(size: 13, weight: .semibold))
            .foregroundColor(Color.appTextSecondary(colorScheme))
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private var resultsHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RESULTS")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .tracking(1.1)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(trimmedSearchText)
                        .font(FontManager.geist(size: 24, weight: .semibold))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .lineLimit(2)

                    Text(searchResultsSummary)
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topTrailing,
            cornerRadius: 24,
            highlightStrength: 0.6
        )
    }

    private func recentSearchChip(_ query: String) -> some View {
        Button {
            applyRecentSearch(query)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.appTextSecondary(colorScheme))

                Text(query)
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 18)
        }
        .buttonStyle(.plain)
    }

    private func previewHighlightRow(_ highlight: SearchPreviewHighlight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appChip(colorScheme))
                    .frame(width: 46, height: 46)

                Image(systemName: highlight.result.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(highlight.eyebrow.uppercased())
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .tracking(0.8)

                Text(highlight.result.title)
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .lineLimit(2)

                Text(highlight.result.subtitle)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                Text(highlight.result.type.badgeLabel)
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.appChip(colorScheme))
                    )

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme).opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topTrailing,
            cornerRadius: 24,
            highlightStrength: 0.5
        )
    }

    @ViewBuilder
    private var content: some View {
        if trimmedSearchText.isEmpty {
            if isSearchFocused {
                recentSearchesView
            } else {
                emptyStateView
            }
        } else if searchResults.isEmpty {
            noResultsView
        } else {
            resultsListView
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .bottomTrailing)
        )
        .onAppear {
            isSearchFocused = false
            refreshSupplementaryState()
            scheduleSearchRefresh()
        }
        .onChange(of: searchText) { _ in
            scheduleSearchRefresh()
        }
        .onChange(of: isSearchFocused) { focused in
            if focused {
                recentSearches = SearchRecentQueryStore.load()
            }
        }
        .onChange(of: isVisible) { _ in
            isSearchFocused = false
            scheduleSearchRefresh()
        }
        .onReceive(searchIndex.$snapshotVersion) { _ in
            refreshSupplementaryState()
            scheduleSearchRefresh()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }
}

private enum SearchRecentQueryStore {
    private static let key = "search.view.recentQueries"
    private static let maxCount = 8

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ query: String) -> [String] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return load() }

        var queries = load().filter {
            $0.localizedCaseInsensitiveCompare(normalizedQuery) != .orderedSame
        }
        queries.insert(normalizedQuery, at: 0)
        queries = Array(queries.prefix(maxCount))
        UserDefaults.standard.set(queries, forKey: key)
        return queries
    }

    static func remove(_ query: String) -> [String] {
        let queries = load().filter {
            $0.localizedCaseInsensitiveCompare(query) != .orderedSame
        }
        UserDefaults.standard.set(queries, forKey: key)
        return queries
    }

    static func clear() -> [String] {
        UserDefaults.standard.removeObject(forKey: key)
        return []
    }
}

#Preview {
    SearchView(
        isVisible: true,
        selectedTab: .constant(.search),
        selectedFolder: .constant(nil),
        onOpenEmail: { _ in },
        onOpenTask: { _ in },
        onOpenNote: { _ in },
        onOpenPlace: { _ in },
        onOpenPerson: { _ in }
    )
}
