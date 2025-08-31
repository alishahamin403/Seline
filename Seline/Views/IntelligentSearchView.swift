//
//  IntelligentSearchView.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import SwiftUI
import Foundation

struct IntelligentSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ContentViewModel
    @State var searchQuery: String
    @State private var selectedEmail: Email?
    @State private var isShowingEmailDetail = false
    @State private var recentSearches: [String] = []
    @FocusState private var isSearchFieldFocused: Bool
    @State private var showingFollowUp = false
    @State private var followUpContext = ""
    @State private var followUpSearchType: SearchType = .general
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            searchHeader
            
            // Results content
            if viewModel.isCurrentlySearching() {
                loadingView
            } else if viewModel.getCurrentSearchResult() != nil {
                // Always show results if we have one, even if the field is currently empty
                searchResultsContent
            } else {
                emptySearchView
            }
        }
        .linearBackground()
        .fullScreenCover(item: $selectedEmail) { email in
            NavigationView {
                GmailStyleEmailDetailView(email: email, viewModel: viewModel)
                    .navigationBarHidden(true)
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
        }
        .fullScreenCover(isPresented: $showingFollowUp) {
            NavigationView {
                FollowUpConversationView(
                    initialContext: followUpContext,
                    initialQuery: searchQuery,
                    searchType: followUpSearchType
                )
                .navigationBarHidden(true)
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
        }
        .onAppear {
            loadRecentSearches()
            isSearchFieldFocused = true
            if !searchQuery.isEmpty {
                performSearch()
            } else if viewModel.getCurrentSearchResult() == nil && !viewModel.searchText.isEmpty {
                // If launched from ContentView with existing text, kick off a search
                searchQuery = viewModel.searchText
                performSearch()
            }
        }
        .onChange(of: searchQuery) { newQuery in
            if newQuery.isEmpty {
                viewModel.searchResults = []
                viewModel.currentSearchResult = nil
            } else {
                performSearchWithDelay(newQuery)
            }
        }
    }
    
    // MARK: - Search Header
    
    private var searchHeader: some View {
        VStack(spacing: 16) {
            // Top navigation
            HStack {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    dismiss()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                Spacer()
                
                // Search type indicator
                if let searchResult = viewModel.getCurrentSearchResult() {
                    HStack(spacing: 6) {
                        Image(systemName: searchResult.type.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.accent)
                        
                        Text(searchResult.type.displayName)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            // Enhanced search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                TextField("Ask anything or search emails...", text: $searchQuery)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        if !searchQuery.isEmpty {
                            addToRecentSearches(searchQuery)
                            performSearch()
                        }
                    }
                
                if viewModel.isCurrentlySearching() {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(DesignSystem.Colors.accent)
                } else if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        isSearchFieldFocused = true
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Search Results Content
    
    private var searchResultsContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let searchResult = viewModel.getCurrentSearchResult() {
                    // AI Response Card
                    aiResponseCard(searchResult)
                        .padding(.horizontal, 24)
                    
                    // Email Results (if any)
                    if searchResult.type == .emailSearch && !searchResult.emails.isEmpty {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Found Emails")
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textPrimary)
                                
                                Spacer()
                                
                                Text("\\(searchResult.emails.count) emails")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.textSecondary)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                            
                            emailResultsList(searchResult.emails)
                        }
                    }
                } else {
                    noResultsView
                }
            }
        }
        .refreshable {
            await performRefreshSearch()
        }
    }
    
    // MARK: - AI Response Card
    
    private func aiResponseCard(_ searchResult: IntelligentSearchResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(searchTypeColor(searchResult.type).opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: searchResult.type.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(searchTypeColor(searchResult.type))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(searchResult.type.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    if let _ = searchResult.metadata["total_emails_searched"],
                       searchResult.type == .emailSearch {
                        Text("Searched through emails")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    } else {
                        Text("Powered by ChatGPT")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                
                Spacer()
                
                // Copy button
                Button(action: {
                    UIPasteboard.general.string = searchResult.response
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            
            // Response content
            Text(searchResult.response)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(nil)
                .textSelection(.enabled)

            // Follow-up action
            HStack {
                Spacer()
                Button(action: {
                    followUpContext = searchResult.response
                    followUpSearchType = mapToSearchType(searchResult.type)
                    showingFollowUp = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Ask a follow-up")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(DesignSystem.Colors.accent.opacity(0.1))
                    )
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(searchTypeColor(searchResult.type).opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func searchTypeColor(_ type: SearchIntent) -> Color {
        switch type {
        case .general:
            return DesignSystem.Colors.accent
        case .emailSearch:
            return .blue
        }
    }

    private func mapToSearchType(_ intent: SearchIntent) -> SearchType {
        switch intent {
        case .general:
            return .general
        case .emailSearch:
            return .email
        }
    }
    
    // MARK: - Email Results List
    
    private func emailResultsList(_ emails: [Email]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(emails.indices, id: \.self) { index in
                let email = emails[index]
                IntelligentSearchResultRow(email: email, query: searchQuery) {
                    // Add haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    
                    selectedEmail = email
                }
                
                if index < emails.count - 1 {
                    Divider()
                        .padding(.leading, 80)
                }
            }
        }
    }
    
    // MARK: - Empty Search View (Clean, no examples)
    
    private var emptySearchView: some View {
        VStack {
            Spacer()
            
            // Clean welcome message
            VStack(spacing: 20) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(DesignSystem.Colors.accent.opacity(0.6))
                
                Text("Search & Ask")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Start typing to search your emails or ask any question")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Clean recent searches section (only show if exists)
            if !recentSearches.isEmpty {
                VStack(spacing: 16) {
                    HStack {
                        Text("Recent")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                        
                        Spacer()
                        
                        Button("Clear") {
                            clearRecentSearches()
                        }
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                    }
                    
                    VStack(spacing: 8) {
                        ForEach(recentSearches.prefix(4), id: \.self) { search in
                            Button(action: {
                                searchQuery = search
                                isSearchFieldFocused = false
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 14))
                                        .foregroundColor(DesignSystem.Colors.textSecondary)
                                    
                                    Text(search)
                                        .font(.system(size: 15, weight: .regular, design: .rounded))
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(DesignSystem.Colors.surfaceSecondary)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(DesignSystem.Colors.border.opacity(0.15), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Example searches removed for cleaner UX
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DesignSystem.Colors.accent)
            
            Text("Thinking...")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }
    
    // MARK: - No Results View
    
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("No results found")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Try a different question or search term")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Helper Functions
    
    private func performSearch() {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        Task {
            await viewModel.performSearch(query: searchQuery)
        }
    }
    
    private func performSearchWithDelay(_ query: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if searchQuery == query {
                performSearch()
            }
        }
    }
    
    private func performRefreshSearch() async {
        if !searchQuery.isEmpty {
            await viewModel.performSearch(query: searchQuery)
        }
    }
    
    // MARK: - Recent Searches Management
    
    private func loadRecentSearches() {
        recentSearches = UserDefaults.standard.stringArray(forKey: "IntelligentRecentSearches") ?? []
    }
    
    private func addToRecentSearches(_ search: String) {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        recentSearches.removeAll { $0 == trimmed }
        recentSearches.insert(trimmed, at: 0)
        
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
        
        UserDefaults.standard.set(recentSearches, forKey: "IntelligentRecentSearches")
    }
    
    private func removeFromRecentSearches(_ search: String) {
        recentSearches.removeAll { $0 == search }
        UserDefaults.standard.set(recentSearches, forKey: "IntelligentRecentSearches")
    }
    
    private func clearRecentSearches() {
        recentSearches.removeAll()
        UserDefaults.standard.removeObject(forKey: "IntelligentRecentSearches")
    }
}

// MARK: - Intelligent Search Result Row

struct IntelligentSearchResultRow: View {
    let email: Email
    let query: String
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Sender avatar with AI badge
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(DesignSystem.Colors.accent.opacity(0.3), lineWidth: 2)
                        )
                    
                    Text(String(email.sender.name?.prefix(1).uppercased() ?? email.sender.email.prefix(1).uppercased()))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                    
                    // AI found indicator
                    Circle()
                        .fill(.blue)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        )
                        .offset(x: 18, y: -18)
                }
                
                // Email content
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(email.sender.name ?? email.sender.email)
                            .font(.system(size: email.isRead ? 15 : 16, weight: email.isRead ? .regular : .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(RelativeDateTimeFormatter().localizedString(for: email.date, relativeTo: Date()))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Text(highlightedSubject)
                        .font(.system(size: email.isRead ? 14 : 15, weight: email.isRead ? .regular : .medium, design: .rounded))
                        .foregroundColor(email.isRead ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(highlightedBody)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                    
                    // Metadata with AI indicator
                    HStack(spacing: 12) {
                        Label("AI Found", systemImage: "brain.head.profile")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.blue)
                        
                        if !email.attachments.isEmpty {
                            Label("\\(email.attachments.count)", systemImage: "paperclip")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        if email.isImportant {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        
                        Spacer()
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .scaleEffect(isPressed ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(DesignSystem.Colors.surface)
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
    
    private var highlightedSubject: AttributedString {
        highlightText(email.subject, query: query)
    }
    
    private var highlightedBody: AttributedString {
        highlightText(email.body, query: query)
    }
    
    private func highlightText(_ text: String, query: String) -> AttributedString {
        guard !query.isEmpty else {
            return AttributedString(text)
        }
        
        var attributedString = AttributedString(text)
        
        let searchTerms = query.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        for term in searchTerms {
            if let range = attributedString.range(of: term, options: [.caseInsensitive]) {
                attributedString[range].backgroundColor = DesignSystem.Colors.accent.opacity(0.2)
                attributedString[range].font = .system(size: 13, weight: .semibold, design: .rounded)
            }
        }
        
        return attributedString
    }
}

// MARK: - Preview

struct IntelligentSearchView_Previews: PreviewProvider {
    static var previews: some View {
        IntelligentSearchView(viewModel: ContentViewModel(), searchQuery: "")
    }
}