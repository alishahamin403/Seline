import SwiftUI

struct SearchOverlayBar: View {
    @Binding var isPresented: Bool
    @Binding var selectedTab: PrimaryTab
    @Binding var selectedNote: Note?
    @Binding var selectedEmail: Email?
    @Binding var selectedTask: TaskItem?
    @Binding var selectedLocation: SavedPlace?
    @Binding var selectedFolder: String?
    let onDismiss: () -> Void

    private let searchIndex = SearchIndexState.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var searchText = ""
    @State private var searchResults: [OverlaySearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                // Search icon
                Image(systemName: "magnifyingglass")
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(.gray)

                // Text field
                TextField("Search emails, events, notes, locations...", text: $searchText)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .focused($isSearchFocused)

                // Clear button
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Cancel button
                Button(action: {
                    searchText = ""
                    isSearchFocused = false
                    onDismiss()
                }) {
                    Text("Cancel")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Search results
            if isPresented && !searchText.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(searchResults) { result in
                            Button(action: {
                                handleResultTap(result)
                            }) {
                                OverlaySearchResultRow(result: result, colorScheme: colorScheme)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        if searchResults.isEmpty {
                            Text("No results found")
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                .searchResultsCardStyle(colorScheme: colorScheme, cornerRadius: 12)
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
        .onAppear {
            if isPresented {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            }
        }
        .onChange(of: isPresented) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
                scheduleSearchRefresh()
            } else {
                isSearchFocused = false
                searchTask?.cancel()
                searchResults = []
            }
        }
        .onChange(of: searchText) { _ in
            scheduleSearchRefresh()
        }
        .onReceive(searchIndex.$snapshotVersion) { _ in
            scheduleSearchRefresh()
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func handleResultTap(_ result: OverlaySearchResult) {
        HapticManager.shared.selection()

        switch result.type {
        case .note:
            if let note = result.note {
                selectedNote = note
            }
        case .email:
            if let email = result.email {
                selectedEmail = email
            }
        case .event:
            if let task = result.task {
                selectedTask = task
            }
        case .location:
            // For locations, open directly in Google Maps
            if let location = result.location {
                GoogleMapsService.shared.openInGoogleMaps(place: location)
            }
            // Dismiss immediately for locations since we're opening an external app
            onDismiss()
            return
        case .folder:
            // For folders, navigate to Maps tab and set the selected folder
            if let category = result.category {
                selectedTab = .maps
                selectedFolder = category
            }
        case .receipt:
            // Receipts are linked to notes - open the note if available
            if let note = result.note {
                selectedNote = note
            }
        case .recurringExpense:
            // Recurring expenses are shown in Notes tab - navigate there
            selectedTab = .notes
        case .person:
            break
        }

        // Dismiss search overlay after setting the state
        onDismiss()
    }

    private func scheduleSearchRefresh() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPresented, !query.isEmpty else {
            searchResults = []
            return
        }

        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            searchResults = searchIndex.results(
                for: query,
                scopes: .overlaySearchScopes,
                limit: 18
            )
        }
    }
}

// MARK: - Search Result Row

struct OverlaySearchResultRow: View {
    let result: OverlaySearchResult
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: result.icon)
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                .frame(width: 24)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(FontManager.geist(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .lineLimit(1)

                Text(result.subtitle)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    .lineLimit(1)
            }

            Spacer()

            // Type badge
            Text(result.type.badgeLabel)
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    colorScheme == .dark ?
                        Color.white.opacity(0.1) :
                        Color.black.opacity(0.05)
                )
                .cornerRadius(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .searchResultsRowStyle(colorScheme: colorScheme, cornerRadius: 8)
    }
}
