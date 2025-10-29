import SwiftUI

struct SearchBarComponent: View {
    @ObservedObject var searchService = SearchService.shared
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedTab: TabSelection

    init(selectedTab: Binding<TabSelection>) {
        self._selectedTab = selectedTab
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search input
            HStack(spacing: 12) {
                // Search icon
                Image(systemName: "magnifyingglass")
                    .font(FontManager.geist(size: .title3, weight: .regular))
                    .foregroundColor(.gray)

                // Search text field
                TextField("Search emails, events, notes, maps...", text: $searchService.searchQuery)
                    .font(FontManager.geist(size: .title3, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                // Clear button
                if !searchService.searchQuery.isEmpty {
                    Button(action: {
                        searchService.clearSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(FontManager.geist(size: .title3, weight: .regular))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
            )
            .padding(.horizontal, 20)

            // Search results
            if !searchService.searchQuery.isEmpty && !searchService.isInConversationMode {
                SearchResultsView(
                    results: searchService.searchResults,
                    isSearching: searchService.isSearching,
                    selectedTab: $selectedTab
                )
            }
        }
        .fullScreenCover(isPresented: $searchService.isInConversationMode) {
            ConversationSearchView()
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    SearchBarComponent(selectedTab: .constant(.home))
}