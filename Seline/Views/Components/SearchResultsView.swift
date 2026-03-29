import SwiftUI

struct SearchResultsView: View {
    let results: [SearchResult]
    let isSearching: Bool
    @Binding var selectedTab: PrimaryTab
    var onOpenPlanInbox: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var searchService = SearchService.shared

    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                // Loading state
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching...")
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                }
                .padding(.vertical, 20)
            } else if results.isEmpty {
                // No results state
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.shadcnTextLg)
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    Text("No results found")
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                }
                .padding(.vertical, 20)
            } else {
                // Results list
                LazyVStack(spacing: 8) {
                    ForEach(results.prefix(5)) { result in
                        SearchResultRow(
                            result: result,
                            selectedTab: $selectedTab,
                            onOpenPlanInbox: onOpenPlanInbox
                        )
                    }

                    if results.count > 5 {
                        Text("\(results.count - 5) more results...")
                            .font(.shadcnTextXs)
                            .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.clear)
        )
        .searchResultsCardStyle(colorScheme: colorScheme, cornerRadius: 10)
        .padding(.horizontal, 20)
        .padding(.top, 2)
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    @Binding var selectedTab: PrimaryTab
    var onOpenPlanInbox: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var searchService = SearchService.shared

    var body: some View {
        Button(action: {
            if result.item.type == .plan, let onOpenPlanInbox {
                onOpenPlanInbox()
            } else if let destination = primaryTab(for: result.item.type) {
                selectedTab = destination
            }
            searchService.clearSearch()
        }) {
            HStack(spacing: 12) {
                // Tab icon
                Image(systemName: result.item.type.systemImage)
                    .font(.shadcnTextSm)
                    .foregroundColor(tabColor)
                    .frame(width: 20, height: 20)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.matchedText)
                        .font(.shadcnTextSm)
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(result.item.type.title)
                            .font(.shadcnTextXs)
                            .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                        if !result.item.content.isEmpty && result.item.content != result.matchedText {
                            Text("•")
                                .font(.shadcnTextXs)
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))

                            Text(result.item.content.prefix(30) + (result.item.content.count > 30 ? "..." : ""))
                                .font(.shadcnTextXs)
                                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Navigation arrow
                Image(systemName: "arrow.up.right")
                    .font(.shadcnTextXs)
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .searchResultsRowStyle(colorScheme: colorScheme, cornerRadius: 8)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var tabColor: Color {
        switch result.item.type {
        case .home:
            return .gray
        case .plan:
            return .orange
        case .search:
            return .gray
        case .notes:
            return .primary
        case .maps:
            return .blue
        }
    }

    private func primaryTab(for destination: SearchDestination) -> PrimaryTab? {
        switch destination {
        case .home: return .home
        case .search: return .search
        case .notes: return .notes
        case .maps: return .maps
        case .plan: return nil
        }
    }
}

#Preview {
    let sampleResults = [
        SearchResult(
            item: SearchableItem(
                title: "Important Email",
                content: "This is a sample email content that matches the search query.",
                type: .plan,
                identifier: "email-1"
            ),
            relevanceScore: 3.0,
            matchedText: "Important Email"
        ),
        SearchResult(
            item: SearchableItem(
                title: "Team Meeting",
                content: "Weekly team sync meeting with the development team.",
                type: .notes,
                identifier: "event-1"
            ),
            relevanceScore: 2.5,
            matchedText: "Team Meeting"
        )
    ]

    SearchResultsView(
        results: sampleResults,
        isSearching: false,
        selectedTab: .constant(.home)
    )
    .padding()
}
