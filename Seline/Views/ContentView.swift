//
//  ContentView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var todoManager = TodoManager.shared
    @StateObject private var voiceRecordingService = VoiceRecordingService.shared
    @State private var showingSettings = false
    @State private var showingSearchResults = false
    @State private var showingImportantEmails = false
    @State private var showingUpcomingEvents = false
    @State private var showingVoiceRecording = false
    @State private var showingVoiceTodosList = false
    @State private var isRefreshing = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var showingSearchSuggestions = false
    @State private var showingAddOptions = false
    @State private var showingAddTodo = false
    @State private var showingAddCalendarEvent = false
    @State private var calendarEventTitle = ""
    @State private var calendarEventDescription: String?
    @State private var calendarEventStart = Date()
    @State private var calendarEventEnd = Date().addingTimeInterval(3600)
    @State private var calendarEventLocation: String?
    @State private var todosExpanded = false // no longer used for UI state (kept for compatibility)
    @State private var eventsExpanded = false // no longer used for UI state (kept for compatibility)
    @State private var showingVoiceModeSelector = false
    @State private var showingVoiceOverlay = false
    @State private var selectedVoiceMode: VoiceMode?
    @FocusState private var isSearchFocused: Bool
    @State private var actionCompleted = false
    
    private var todayImportantCount: Int {
        viewModel.importantEmails.count
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top area: Clean header with minimal elements
                topSection
                
                if isSearchFocused {
                    // When focused, show search interface with suggestions
                    searchFocusedView
                } else {
                    // Normal view with category cards
                    categoryCardsView
                }
                
                // Search bar - always at bottom but moves up with keyboard
                bottomSearchSection
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - geometry.safeAreaInsets.bottom : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .linearBackground()
            .animation(.easeOut(duration: 0.3), value: isSearchFocused)
            .animation(.easeOut(duration: 0.3), value: keyboardHeight)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.easeOut(duration: 0.3)) {
                        keyboardHeight = keyboardFrame.height
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    keyboardHeight = 0
                }
            }
        }
        .fullScreenCover(isPresented: $showingSettings) {
            NavigationView {
                AdvancedSettingsView(openAIService: OpenAIService.shared)
                    .navigationBarHidden(true)
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
        }
        .fullScreenCover(isPresented: $showingSearchResults) {
            NavigationView {
                IntelligentSearchView(viewModel: viewModel, openAIService: OpenAIService.shared, searchQuery: viewModel.searchText)
                    .navigationBarHidden(true)
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
        }
        .fullScreenCover(isPresented: $showingImportantEmails) {
            NavigationView {
                TodayEmailsView(openAIService: OpenAIService.shared) // Using TodayEmailsView instead of ImportantEmailsView
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
        }
        .fullScreenCover(isPresented: $showingUpcomingEvents) {
            UpcomingEventsView()
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
        }

        .sheet(isPresented: $showingVoiceTodosList) {
            TodoListView() // Using TodoListView instead of VoiceTodosListView
        }
        .sheet(isPresented: $showingAddTodo) {
            AddTodoView { todoItem in
                Task {
                    await todoManager.addTodo(todoItem)
                }
            }
        }
        .sheet(isPresented: $showingAddCalendarEvent) {
            AddCalendarEventView(
                onEventAdded: {
                    Task {
                        await viewModel.loadCategoryEmails()
                    }
                },
                title: calendarEventTitle,
                description: calendarEventDescription,
                start: calendarEventStart,
                end: calendarEventEnd,
                location: calendarEventLocation
            )
        }
        .actionSheet(isPresented: $showingAddOptions) {
            ActionSheet(
                title: Text("Add New Item"),
                message: Text("What would you like to add?"),
                buttons: [
                    .default(Text("📝 Todo Item")) {
                        showingAddTodo = true
                    },
                    .default(Text("📅 Calendar Event")) {
                        showingAddCalendarEvent = true
                    },
                    .cancel()
                ]
            )
        }
        .overlay(
            // Voice mode selector and recording overlays
            Group {
                if showingVoiceModeSelector {
                    VoiceModeSelector(
                        onModeSelected: { mode in
                            selectedVoiceMode = mode
                            showingVoiceModeSelector = false
                            showingVoiceRecording = true
                            
                            // Start recording immediately for selected mode
                            startVoiceRecording(for: mode)
                        },
                        onCancel: {
                            showingVoiceModeSelector = false
                        },
                        selectedVoiceMode: $selectedVoiceMode,
                        showingVoiceModeSelector: $showingVoiceModeSelector,
                        showingVoiceRecording: $showingVoiceRecording,
                        startVoiceRecording: startVoiceRecording
                    )
                } else if showingVoiceRecording, let mode = selectedVoiceMode {
                    VoiceModeRecordingOverlay(
                        mode: mode,
                        onCancel: {
                            voiceRecordingService.stopRecording(userInitiated: true)
                            showingVoiceRecording = false
                            selectedVoiceMode = nil
                        },
                        onModeChange: {
                            voiceRecordingService.stopRecording(userInitiated: true)
                            showingVoiceRecording = false
                            showingVoiceModeSelector = true
                        }
                    )
                }
            }
        )
        // Search is now triggered only when user presses Enter/Return
        // This prevents the refresh screen behavior
        .onAppear {
            Task {
                await viewModel.loadEmails()
                await viewModel.loadCategoryEmails()
            }
        }
        .onChange(of: voiceRecordingService.isRecording) { isRecording in
            // Auto-hide recording overlay when recording stops (but not when cancelled by user)
            if !isRecording && !voiceRecordingService.isProcessing {
                showingVoiceRecording = false
                selectedVoiceMode = nil
            }
        }
        // Stop voice recording on action completion
        .onDisappear {
            if actionCompleted {
                voiceRecordingService.stopRecording(userInitiated: true)
            }
        }
    }
    
    // MARK: - Voice Recording Helper
    
    private func startVoiceRecording(for mode: VoiceMode) {
        let oneShotMode: VoiceRecordingService.OneShotMode
        switch mode {
        case .todo:
            oneShotMode = .todo
        case .search:
            oneShotMode = .search // Calendar uses search mode for transcription
        @unknown default:
            oneShotMode = .search
        }

        VoiceRecordingService.shared.startOneShotTranscription(for: oneShotMode) { transcript in
            // Hide overlay when transcription completes
            Task { @MainActor in
                showingVoiceRecording = false
                selectedVoiceMode = nil
            }
            
            guard let text = transcript, !text.isEmpty else { return }
            
            // Process based on selected mode instead of AI detection
            switch mode {
            case .todo:
                Task { await TodoManager.shared.createTodoFromSpeech(text) }
            case .search:
                // For search mode, populate search field and open search results
                Task { @MainActor in
                    viewModel.searchText = text
                    showingSearchResults = true
                }
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Top Section
    
    private var topSection: some View {
        HStack {
            Text("Seline")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Spacer()
            
            HStack(spacing: 16) {
                // Settings button
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "person.circle")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                // Inbox button with improved formatting
                Button(action: {
                    openGmailApp()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 14, weight: .medium))
                        Text("Inbox")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DesignSystem.Colors.surfaceSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(DesignSystem.Colors.border.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }
    
    // MARK: - Category Cards View (Normal State)
    
    private var categoryCardsView: some View {
        VStack(spacing: 0) {
            Spacer()
            categoryCardsSection
            Spacer()
        }
    }
    
    // MARK: - Search Focused View with Suggestions
    
    private var searchFocusedView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Give some breathing room at top
                Spacer(minLength: 40)
                
                // Search history section with better design
                searchSuggestionsSection
                
                // Extra space at bottom to account for keyboard
                Spacer(minLength: 120)
            }
        }
        .linearBackground()
    }
    
    private var searchSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !viewModel.searchHistory.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Recent Searches")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Spacer()
                        Button("Clear") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.clearSearchHistory()
                            }
                        }
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.searchHistory, id: \.self) { historyItem in
                            SearchHistoryRow(
                                text: historyItem,
                                onTap: {
                                    viewModel.searchText = historyItem
                                    isSearchFocused = false
                                },
                                onDelete: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        viewModel.removeFromSearchHistory(historyItem)
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
                    
                    VStack(spacing: 8) {
                        Text("No recent searches")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Text("Start typing to search emails or ask questions")
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
    }
    
    
    // MARK: - Category Cards Section
    
    private var categoryCardsSection: some View {
        VStack(spacing: 16) {

            // Today's Emails Card with Previews
            TodaysEmailsPreviewCard(
                emails: viewModel.displayedTodaysEmails,
                totalCount: todayImportantCount,
                onTap: {
                    showingImportantEmails = true
                }
            )

            // Today's Events (tap to open full view)
            ExpandableEventsSection(
                events: viewModel.displayedUpcomingEvents,
                isExpanded: .constant(false),
                onAddEvent: {
                    showingAddCalendarEvent = true
                },
                onViewAll: {
                    showingUpcomingEvents = true
                }
            )
            .contentShape(Rectangle())
            .onTapGesture { showingUpcomingEvents = true }

            // Today's Todos (tap to open full view)
            ExpandableTodosSection(
                todos: Array(todoManager.todayTodos.prefix(3)),
                isExpanded: .constant(false),
                onAddTodo: {
                    showingAddTodo = true
                },
                onAddTodoWithVoice: {
                    selectedVoiceMode = .todo
                    showingVoiceRecording = true
                    startVoiceRecording(for: .todo)
                },
                onViewAll: {
                    showingVoiceTodosList = true
                }
            )
            .contentShape(Rectangle())
            .onTapGesture { showingVoiceTodosList = true }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Bottom Search Section
    
    private var bottomSearchSection: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: isSearchFocused ? "sparkles" : "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(isSearchFocused ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                    .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                
                TextField(searchPlaceholder, text: $viewModel.searchText)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .textFieldStyle(PlainTextFieldStyle())
                    .focused($isSearchFocused)
                    .onSubmit {
                        if !viewModel.searchText.isEmpty {
                            showingSearchResults = true
                        }
                    }
                
                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        viewModel.searchText = ""
                        isSearchFocused = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Search voice button: when focused on search, record voice for search (opens IntelligentSearchView with transcription)
                if isSearchFocused {
                    Button(action: {
                        selectedVoiceMode = .search
                        showingVoiceRecording = true
                        startVoiceRecording(for: .search)
                    }) {
                        ZStack {
                            Circle()
                                .fill(voiceRecordingService.isRecording ? Color.red : DesignSystem.Colors.accent)
                                .frame(width: 28, height: 28)
                                .scaleEffect(voiceRecordingService.isRecording ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: voiceRecordingService.isRecording)
                            
                            if voiceRecordingService.isProcessing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: voiceRecordingService.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color.white)
                            }
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Voice search button: when not focused, open voice mode selector
                    Button(action: {
                        selectedVoiceMode = .search
                        showingVoiceRecording = true
                        startVoiceRecording(for: .search)
                    }) {
                        ZStack {
                            Circle()
                                .fill(voiceRecordingService.isRecording ? Color.red : DesignSystem.Colors.accent)
                                .frame(width: 28, height: 28)
                                .scaleEffect(voiceRecordingService.isRecording ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: voiceRecordingService.isRecording)
                            
                            if voiceRecordingService.isProcessing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: voiceRecordingService.isRecording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color.white)
                            }
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                if !viewModel.searchText.isEmpty && isSearchFocused {
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        showingSearchResults = true
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                    .transition(.scale.combined(with: .opacity))
                }

            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: isSearchFocused ? 20 : 16)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: isSearchFocused ? 20 : 16)
                            .stroke(isSearchFocused ? DesignSystem.Colors.accent.opacity(0.5) : DesignSystem.Colors.border.opacity(0.3), lineWidth: isSearchFocused ? 2 : 1)
                    )
                    .animation(.easeInOut(duration: 0.3), value: isSearchFocused)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            
        }
    }
    
    private var searchPlaceholder: String {
        if isSearchFocused {
            return "Ask me anything or search emails..."
        } else {
            return "Search emails, ask questions..."
        }
    }
    
    // MARK: - Actions
    
    
    
    // MARK: - Data Refresh
    
    private func performRefresh() async {
        isRefreshing = true
        await viewModel.refresh()
        isRefreshing = false
    }
    
    // MARK: - Gmail App Integration
    
    private func openGmailApp() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Gmail app URL scheme
        let gmailURL = URL(string: "googlegmail://")!
        
        // Check if Gmail app is installed
        if UIApplication.shared.canOpenURL(gmailURL) {
            // Open Gmail app
            UIApplication.shared.open(gmailURL, options: [:]) { success in
                if !success {
                    print("Failed to open Gmail app")
                    // Fallback to App Store if opening fails
                    DispatchQueue.main.async {
                        self.openGmailInAppStore()
                    }
                }
            }
        } else {
            // Gmail app not installed, redirect to App Store
            openGmailInAppStore()
        }
    }
    
    private func openGmailInAppStore() {
        // Gmail App Store URL
        let appStoreURL = URL(string: "https://apps.apple.com/app/gmail-email-by-google/id422689480")!
        
        if UIApplication.shared.canOpenURL(appStoreURL) {
            UIApplication.shared.open(appStoreURL, options: [:]) { success in
                if !success {
                    print("Failed to open App Store for Gmail")
                }
            }
        }
    }
}

// MARK: - Modern Category Card Component

struct CategoryCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let count: Int
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Modern gradient icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.primaryGradient)
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(
                            Color(UIColor { traitCollection in
                                traitCollection.userInterfaceStyle == .dark ? 
                                UIColor.black : UIColor.white
                            })
                        )
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }

                Spacer()

                // Modern arrow with subtle background
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.surfaceSecondary)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.surface)
                    .shadow(
                        color: colorScheme == .light ? Color.black.opacity(0.06) : Color.clear,
                        radius: 8,
                        x: 0,
                        y: 2
                    )
            )
        }
        .buttonStyle(ModernCardButtonStyle())
    }
}

// MARK: - Modern Card Button Style

struct ModernCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Search History Row

struct SearchHistoryRow: View {
    let text: String
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap()
        }) {
            HStack(spacing: 14) {
                Image(systemName: "clock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
                    .frame(width: 18, height: 18)
                
                Text(text)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    onDelete()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DesignSystem.Colors.border.opacity(0.5), lineWidth: 0.5)
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Search Suggestion Row

struct SearchSuggestionRow: View {
    let suggestion: SearchSuggestion
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap()
        }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.textPrimary.opacity(0.1))
                        .frame(width: 36, height: 36)

                    Image(systemName: suggestion.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(suggestion.type.displayName)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.black.opacity(0.6))
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black.opacity(0.4))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.blue.opacity(0.4),
                                        Color.blue.opacity(0.2),
                                        Color.blue.opacity(0.4)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
            )
        }
        .buttonStyle(SearchSuggestionButtonStyle())
    }

}

struct SearchSuggestionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Search Suggestion Model

struct SearchSuggestion {
    let text: String
    let type: SearchType
    let icon: String
}

// MARK: - SearchType Extension (moved to OpenAIService.swift)



// MARK: - Event Preview Row

struct EventPreviewRow: View {
    let event: CalendarEvent
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignSystem.Colors.accent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Text(formatEventTime(event))
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    if let location = event.location, !location.isEmpty {
                        Text("• \(location)")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func formatEventTime(_ event: CalendarEvent) -> String {
        let formatter = DateFormatter()
        
        if Calendar.current.isDate(event.startDate, inSameDayAs: Date()) {
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: event.startDate)
        } else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: event.startDate)
        }
    }
}

// MARK: - Todo List Preview Component

struct TodoListPreview: View {
    let todos: [TodoItem]
    let onAddTodo: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Todos")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                Button(action: onAddTodo) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("Add")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(DesignSystem.Colors.accent.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            VStack(spacing: 8) {
                ForEach(Array(todos.prefix(3)), id: \.id) { todo in
                    TodoPreviewRow(todo: todo)
                }
                
                if todos.count > 3 {
                    Button(action: onAddTodo) {
                        Text("View all \(todos.count) todos")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: colorScheme == .light ? Color.black.opacity(0.06) : Color.clear,
                    radius: 8,
                    x: 0,
                    y: 2
                )
        )
    }
}

struct TodoPreviewRow: View {
    let todo: TodoItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(todo.isCompleted ? .green : DesignSystem.Colors.textSecondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if todo.isOverdue {
                        Text("Overdue")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.red)
                    } else if todo.isDueToday {
                        Text("Today")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.orange)
                    } else {
                        Text(todo.formattedDueDate)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    if todo.priority != .medium {
                        Text("• \(todo.priority.rawValue)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(todo.priority == .high ? .red : .blue)
                    }
                    
                    if let reminderTime = todo.formattedReminderTime {
                        Text("• 🔔 \(reminderTime)")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
