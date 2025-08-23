//
//  SearchResultsView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct SearchResultsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContentViewModel()
    @State var searchQuery: String
    @State private var showingEmailDetail = false
    @State private var selectedEmail: Email?
    @State private var sortBy: SortOption = .relevance
    @State private var recentSearches: [String] = []
    
    enum SortOption: String, CaseIterable {
        case relevance = "Relevance"
        case date = "Date"
        case sender = "Sender"
        
        var icon: String {
            switch self {
            case .relevance: return "star"
            case .date: return "clock"
            case .sender: return "person"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search header with controls
                searchHeader
                
                // Results content
                if viewModel.isLoading {
                    loadingView
                } else if searchResults.isEmpty && !searchQuery.isEmpty {
                    noResultsView
                } else if searchQuery.isEmpty {
                    recentSearchesView
                } else {
                    searchResultsList
                }
            }
            .designSystemBackground()
            .navigationTitle("Search Results")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(DesignSystem.Typography.bodyMedium)
                    .accentColor()
                }
            }
        }
        .sheet(item: $selectedEmail) { email in
            EmailDetailView(email: email)
        }
        .onAppear {
            loadRecentSearches()
            if !searchQuery.isEmpty {
                performSearch()
            }
        }
        .onChange(of: searchQuery) { _ in
            performSearch()
        }
    }
    
    // MARK: - Search Header
    
    private var searchHeader: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Enhanced search box
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(searchQuery.isEmpty ? DesignSystem.Colors.systemTextSecondary : DesignSystem.Colors.accent)
                
                TextField("Search your emails...", text: $searchQuery)
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.systemTextPrimary)
                    .submitLabel(.search)
                    .onSubmit {
                        saveToRecentSearches(searchQuery)
                        performSearch()
                    }
                
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                    }
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.systemSecondaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .stroke(
                        searchQuery.isEmpty ? DesignSystem.Colors.systemBorder : DesignSystem.Colors.accent.opacity(0.5),
                        lineWidth: searchQuery.isEmpty ? 1 : 2
                    )
            )
            .shadow(color: DesignSystem.Shadow.light, radius: 4, x: 0, y: 2)
            
            // Results summary and sorting
            if !searchQuery.isEmpty && !searchResults.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(searchResults.count) results")
                            .font(DesignSystem.Typography.bodyMedium)
                            .primaryText()
                        
                        Text("for \"\(searchQuery)\"")
                            .font(DesignSystem.Typography.caption)
                            .secondaryText()
                    }
                    
                    Spacer()
                    
                    // Sort picker
                    Menu {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button(action: {
                                sortBy = option
                            }) {
                                HStack {
                                    Text(option.rawValue)
                                    if sortBy == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: sortBy.icon)
                                .font(.caption)
                            Text(sortBy.rawValue)
                                .font(DesignSystem.Typography.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(DesignSystem.Colors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(DesignSystem.Colors.accent.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(DesignSystem.Colors.accent.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.systemSecondaryBackground)
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.systemBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Search Results List
    
    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedResults) { result in
                    SearchResultRow(
                        email: result.email,
                        searchQuery: searchQuery,
                        relevanceScore: result.relevanceScore,
                        onTap: {
                            selectedEmail = result.email
                            showingEmailDetail = true
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    
                    if result.email.id != sortedResults.last?.email.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
                
                // Show more results button
                if searchResults.count > 10 {
                    Button("Show More Results") {
                        // Implement pagination
                    }
                    .font(DesignSystem.Typography.bodyMedium)
                    .accentColor()
                    .padding(DesignSystem.Spacing.lg)
                }
            }
        }
        .refreshable {
            performSearch()
        }
        .animation(.easeInOut(duration: 0.3), value: sortBy)
    }
    
    // MARK: - Recent Searches View
    
    private var recentSearchesView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
            Text("Recent Searches")
                .font(DesignSystem.Typography.title3)
                .primaryText()
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.top, DesignSystem.Spacing.lg)
            
            if recentSearches.isEmpty {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.Colors.systemTextSecondary.opacity(0.6))
                    
                    Text("No recent searches")
                        .font(DesignSystem.Typography.body)
                        .secondaryText()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(DesignSystem.Spacing.lg)
            } else {
                ScrollView {
                    VStack(spacing: DesignSystem.Spacing.xs) {
                        ForEach(recentSearches, id: \.self) { search in
                            RecentSearchRow(
                                searchText: search,
                                onTap: {
                                    searchQuery = search
                                    performSearch()
                                },
                                onDelete: {
                                    removeFromRecentSearches(search)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - No Results View
    
    private var noResultsView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.systemTextSecondary.opacity(0.6))
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No Results Found")
                    .font(DesignSystem.Typography.title3)
                    .primaryText()
                
                Text("Try adjusting your search terms or check spelling")
                    .font(DesignSystem.Typography.body)
                    .secondaryText()
                    .multilineTextAlignment(.center)
            }
            
            // Search suggestions
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Search Suggestions:")
                    .font(DesignSystem.Typography.bodyMedium)
                    .primaryText()
                
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("• Try broader terms like \"meeting\" or \"project\"")
                    Text("• Search by sender name or email address")
                    Text("• Look for specific keywords in subject lines")
                    Text("• Check for typos in your search query")
                }
                .font(DesignSystem.Typography.subheadline)
                .secondaryText()
            }
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.systemSecondaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DesignSystem.Colors.accent)
            
            Text("Searching emails...")
                .font(DesignSystem.Typography.body)
                .secondaryText()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }
    
    // MARK: - Helper Properties
    
    private var searchResults: [SearchResult] {
        viewModel.searchResults.map { email in
            SearchResult(
                email: email,
                relevanceScore: calculateRelevanceScore(email: email, query: searchQuery)
            )
        }
    }
    
    private var sortedResults: [SearchResult] {
        switch sortBy {
        case .relevance:
            return searchResults.sorted { $0.relevanceScore > $1.relevanceScore }
        case .date:
            return searchResults.sorted { $0.email.date > $1.email.date }
        case .sender:
            return searchResults.sorted { $0.email.sender.displayName < $1.email.sender.displayName }
        }
    }
    
    // MARK: - Helper Methods
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        
        Task {
            // Add slight delay to debounce search
            try? await Task.sleep(nanoseconds: 300_000_000)
            await viewModel.performSearch(query: searchQuery)
        }
    }
    
    private func calculateRelevanceScore(email: Email, query: String) -> Double {
        let queryLower = query.lowercased()
        var score: Double = 0
        
        // Subject match (highest weight)
        let subjectMatches = email.subject.lowercased().components(separatedBy: " ").filter { $0.contains(queryLower) }.count
        score += Double(subjectMatches) * 3.0
        
        // Exact subject match bonus
        if email.subject.lowercased().contains(queryLower) {
            score += 5.0
        }
        
        // Body match (medium weight)
        let bodyMatches = email.body.lowercased().components(separatedBy: " ").filter { $0.contains(queryLower) }.count
        score += Double(bodyMatches) * 1.5
        
        // Sender match (medium weight)
        if email.sender.displayName.lowercased().contains(queryLower) || email.sender.email.lowercased().contains(queryLower) {
            score += 2.0
        }
        
        // Recent emails bonus
        let daysSinceEmail = Calendar.current.dateComponents([.day], from: email.date, to: Date()).day ?? 0
        if daysSinceEmail <= 7 {
            score += 1.0
        }
        
        // Unread bonus
        if !email.isRead {
            score += 0.5
        }
        
        // Important email bonus
        if email.isImportant {
            score += 1.0
        }
        
        return score
    }
    
    private func loadRecentSearches() {
        if let searches = UserDefaults.standard.array(forKey: "recent_searches") as? [String] {
            recentSearches = Array(searches.prefix(10)) // Limit to 10 recent searches
        }
    }
    
    private func saveToRecentSearches(_ search: String) {
        guard !search.isEmpty else { return }
        
        var searches = recentSearches
        
        // Remove if already exists
        searches.removeAll { $0 == search }
        
        // Add to beginning
        searches.insert(search, at: 0)
        
        // Keep only 10 most recent
        searches = Array(searches.prefix(10))
        
        recentSearches = searches
        UserDefaults.standard.set(searches, forKey: "recent_searches")
    }
    
    private func removeFromRecentSearches(_ search: String) {
        recentSearches.removeAll { $0 == search }
        UserDefaults.standard.set(recentSearches, forKey: "recent_searches")
    }
}

// MARK: - Search Result Model

struct SearchResult: Identifiable {
    let id = UUID()
    let email: Email
    let relevanceScore: Double
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let email: Email
    let searchQuery: String
    let relevanceScore: Double
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Relevance indicator and avatar
                ZStack {
                    Circle()
                        .fill(relevanceColor.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(relevanceColor.opacity(0.3), lineWidth: 2)
                        )
                    
                    if !email.isRead {
                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 12, height: 12)
                            .offset(x: 15, y: -15)
                    }
                    
                    Text(String(email.sender.displayName.prefix(1).uppercased()))
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(relevanceColor)
                }
                
                // Email content with highlighting
                VStack(alignment: .leading, spacing: 6) {
                    // Header row
                    HStack {
                        Text(highlightMatches(in: email.sender.displayName, query: searchQuery))
                            .font(email.isRead ? DesignSystem.Typography.body : DesignSystem.Typography.bodyMedium)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            // Relevance badge
                            Text(relevanceText)
                                .font(DesignSystem.Typography.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(relevanceColor.gradient)
                                )
                            
                            Text(RelativeDateTimeFormatter().localizedString(for: email.date, relativeTo: Date()))
                                .font(DesignSystem.Typography.caption)
                                .secondaryText()
                        }
                    }
                    
                    // Subject with highlighting
                    Text(highlightMatches(in: email.subject, query: searchQuery))
                        .font(email.isRead ? DesignSystem.Typography.subheadline : DesignSystem.Typography.callout)
                        .lineLimit(1)
                    
                    // Body preview with highlighting
                    Text(highlightMatches(in: email.body, query: searchQuery))
                        .font(DesignSystem.Typography.footnote)
                        .secondaryText()
                        .lineLimit(2)
                    
                    // Metadata
                    HStack(spacing: DesignSystem.Spacing.md) {
                        if !email.attachments.isEmpty {
                            Label("\(email.attachments.count)", systemImage: "paperclip")
                                .font(DesignSystem.Typography.caption2)
                                .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                        }
                        
                        if email.isImportant {
                            Label("Important", systemImage: "exclamationmark.circle.fill")
                                .font(DesignSystem.Typography.caption2)
                                .foregroundColor(.red)
                        }
                        
                        Spacer()
                        
                        Text("Score: \(Int(relevanceScore))")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(relevanceColor)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.systemTextSecondary)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.systemBackground)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity) {
            // Long press action
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
    
    private var relevanceColor: Color {
        if relevanceScore >= 8.0 {
            return .green
        } else if relevanceScore >= 5.0 {
            return .orange
        } else if relevanceScore >= 3.0 {
            return .blue
        } else {
            return .gray
        }
    }
    
    private var relevanceText: String {
        if relevanceScore >= 8.0 {
            return "EXCELLENT"
        } else if relevanceScore >= 5.0 {
            return "GOOD"
        } else if relevanceScore >= 3.0 {
            return "FAIR"
        } else {
            return "LOW"
        }
    }
    
    private func highlightMatches(in text: String, query: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        if let range = attributedString.range(of: query, options: .caseInsensitive) {
            attributedString[range].foregroundColor = DesignSystem.Colors.accent
            attributedString[range].font = .system(size: attributedString[range].font?.pointSize ?? 16, weight: .semibold)
            attributedString[range].backgroundColor = DesignSystem.Colors.accent.opacity(0.1)
        }
        
        return attributedString
    }
}

// MARK: - Recent Search Row

struct RecentSearchRow: View {
    let searchText: String
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onTap) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.body)
                        .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                    
                    Text(searchText)
                        .font(DesignSystem.Typography.body)
                        .primaryText()
                    
                    Spacer()
                }
            }
            
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.systemTextSecondary)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.systemSecondaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.sm)
    }
}

// MARK: - Preview

struct SearchResultsView_Previews: PreviewProvider {
    static var previews: some View {
        SearchResultsView(searchQuery: "meeting")
    }
}