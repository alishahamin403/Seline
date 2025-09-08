//
//  ContentView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Binding var selectedTab: Tab
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var viewModel: ContentViewModel
    @StateObject private var todoManager = TodoManager.shared
    @StateObject private var voiceRecordingService = VoiceRecordingService.shared
    @State private var showingSettings = false
    @State private var showingSearchResults = false
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
    @State private var selectedVoiceMode: VoiceMode?
    @FocusState private var isSearchFocused: Bool
    @State private var actionCompleted = false
    @State private var lastDebugLogTime: Date?
    
    // MARK: - Date and Time Helper Functions
    
    private func isToday(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = Date()
        
        // Get start of today (12:00 AM)
        let startOfToday = calendar.startOfDay(for: today)
        
        // Get end of today (11:59:59 PM)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)?.addingTimeInterval(-1) ?? today
        
        // Check if email date falls within today's range
        return date >= startOfToday && date <= endOfToday
    }
    
    private func getTimeRangeLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        switch hour {
        case 0..<6:
            return "Night"
        case 6..<12:
            return "Morning"
        case 12..<18:
            return "Afternoon"
        case 18..<24:
            return "Evening"
        default:
            return "Unknown"
        }
    }
    
    private var todayImportantCount: Int {
        // Show emails from today (12:00 AM to 11:59 PM)
        let todaysEmails = viewModel.emails.filter { email in
            isToday(email.date)
        }
        
#if DEBUG
        // Throttle debug logs to prevent spam (only log every 5 seconds)
        let now = Date()
        let shouldLog = lastDebugLogTime == nil || now.timeIntervalSince(lastDebugLogTime!) > 5.0
        
        if shouldLog {
            lastDebugLogTime = now
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            
            // Enhanced logging
            print("🏠 HOME: Total emails: \(viewModel.emails.count)")
            print("🏠 HOME: Today's emails: \(todaysEmails.count)")
            print("🏠 HOME: Current date: \(dateFormatter.string(from: now))")
            
            if viewModel.emails.count > 0 {
                print("🏠 HOME: First 3 email dates:")
                for (index, email) in viewModel.emails.prefix(3).enumerated() {
                    let isToday = isToday(email.date) ? "✓" : "✗"
                    print("🏠   \(index + 1). \(dateFormatter.string(from: email.date)) \(isToday)")
                }
            }
        }
        #endif
        
        return todaysEmails.count
    }
    
    private var todayEventsCount: Int {
        // Show only TODAY's events, not the 7-day upcoming events
        viewModel.upcomingEvents.filter { Calendar.current.isDateInToday($0.startDate) }.count
    }
    
    private var todayTodosCount: Int {
        todoManager.todayTodos.count
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top area: Clean header with minimal elements
                topSection
                
                // Search bar - now positioned above content
                topSearchSection
                
                if isSearchFocused {
                    // When focused, show search interface with suggestions
                    searchFocusedView
                } else {
                    // Normal view with personalized greeting
                    personalizedGreetingView
                        .gesture(
                            DragGesture(minimumDistance: 30)
                                .onEnded { value in
                                    // Swipe down gesture to focus search
                                    if value.translation.height > 50 && abs(value.translation.width) < 100 {
                                        withAnimation(.easeOut(duration: 0.3)) {
                                            isSearchFocused = true
                                        }
                                        // Haptic feedback
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                        impactFeedback.impactOccurred()
                                    }
                                }
                        )
                }
                
                // Spacer to push content up when keyboard appears
                if keyboardHeight > 0 {
                    Spacer()
                        .frame(height: keyboardHeight - geometry.safeAreaInsets.bottom)
                } else {
                    Spacer()
                }
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
        // Search is now triggered only when user presses Enter/Return
        // This prevents the refresh screen behavior
        .onAppear {
            // Data loading is now handled by MainTabView to prevent redundant fetches
        }
        .onChange(of: voiceRecordingService.isRecording) { isRecording in
            // Reset voice mode when recording stops
            if !isRecording && !voiceRecordingService.isProcessing {
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
            // Reset voice mode when transcription completes
            Task { @MainActor in
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
        VStack(spacing: 12) {
            HStack {
                Spacer()
                
                // Settings button
                Button(action: {
                    showingSettings = true
                }) {
                    Image(systemName: "person.circle")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.md)
            
            // Date display moved to top area
            Text(todayDateString)
                .font(.system(size: 23, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.sm)
        }
    }
    
    // MARK: - Personalized Greeting View (Normal State)
    
    private var personalizedGreetingView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)
            
            personalizedGreetingSection
            
            // Daily Brain Teaser
            VStack {
                DailyBrainTeaserCard()
                    .padding(.horizontal, DesignSystem.Spacing.lg)
            }
            .padding(.top, 16)
            
            Spacer(minLength: 20)
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
                .padding(.horizontal, DesignSystem.Spacing.lg)
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
                            .padding(.horizontal, DesignSystem.Spacing.xl)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
    }
    
    // MARK: - Recent Search Previews Section
    
    
    // MARK: - Personalized Greeting Section
    
    private var personalizedGreetingSection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 20) {
                // Day time tracker
                DayTimeTracker()
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                
                VStack(spacing: 16) {
                    personalizedGreetingText
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
            }
        }
    }
    
    private var personalizedGreetingText: some View {
        let userName = AuthenticationService.shared.user?.name.components(separatedBy: " ").first ?? "there"
        
        return (Text("Hi ") + 
                Text("\(userName)") +
                Text(", you have ") +
                Text("\(todayImportantCount)").foregroundColor(DesignSystem.Colors.accent).fontWeight(.bold) +
                Text(" emails, ") +
                Text("\(todayEventsCount)").foregroundColor(DesignSystem.Colors.accent).fontWeight(.bold) +
                Text(" calendar events, and ") +
                Text("\(todayTodosCount)").foregroundColor(DesignSystem.Colors.accent).fontWeight(.bold) +
                Text(" todos today"))
            .font(.system(size: 28, weight: .regular, design: .rounded))
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
    }
    
    // MARK: - Greeting Computed Properties
    
    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
    
    private var logoImageName: String {
        let hour = Calendar.current.component(.hour, from: Date())
        // Use light logo during day (6 AM - 6 PM), dark logo at night (6 PM - 6 AM)
        return hour >= 6 && hour < 18 ? "seline-light" : "SelineLogo"
    }
    
    // MARK: - Top Search Section
    
    private var searchBarBackground: some View {
        RoundedRectangle(cornerRadius: isSearchFocused ? 20 : 16)
            .fill(DesignSystem.Colors.surfaceSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: isSearchFocused ? 20 : 16)
                    .stroke(
                        isSearchFocused ? 
                        DesignSystem.Colors.accent.opacity(0.6) : 
                        Color.clear,
                        lineWidth: isSearchFocused ? 2 : 0
                    )
            )
            .animation(.easeInOut(duration: 0.3), value: isSearchFocused)
    }
    
    private var topSearchSection: some View {
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
                
                // Inline voice recording interface
                if isSearchFocused {
                    HStack(spacing: 8) {
                        // Voice visualizer bars (show when recording)
                        if voiceRecordingService.isRecording {
                            VoiceVisualizerBars(
                                audioLevels: voiceRecordingService.audioLevels,
                                isRecording: voiceRecordingService.isRecording
                            )
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        // Stop button (show when recording)
                        if voiceRecordingService.isRecording {
                            Button(action: {
                                voiceRecordingService.stopRecording(userInitiated: true)
                                selectedVoiceMode = nil
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(DesignSystem.Colors.danger)
                                    
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.alwaysWhite)
                                }
                                .frame(width: 24, height: 24)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        // Microphone button
                        Button(action: {
                            if voiceRecordingService.isRecording {
                                voiceRecordingService.stopRecording(userInitiated: true)
                                selectedVoiceMode = nil
                            } else {
                                selectedVoiceMode = .search
                                startVoiceRecording(for: .search)
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(voiceRecordingService.isRecording ? DesignSystem.Colors.danger : DesignSystem.Colors.accent)
                                
                                if voiceRecordingService.isProcessing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.alwaysWhite))
                                } else {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                                }
                            }
                            .frame(width: 28, height: 28)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Voice search button: when not focused, focus search and start recording
                    Button(action: {
                        isSearchFocused = true
                        selectedVoiceMode = .search
                        startVoiceRecording(for: .search)
                    }) {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.Colors.accent)
                            
                            Image(systemName: "mic.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                        }
                        .frame(width: 28, height: 28)
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
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(searchBarBackground)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.sm)
            .padding(.bottom, DesignSystem.Spacing.sm)
            
            
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
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
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
                            .foregroundColor(DesignSystem.Colors.danger)
                    } else if todo.isDueToday {
                        Text("Today")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.warning)
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
        ContentView(selectedTab: .constant(.home))
            .environmentObject(ContentViewModel())
    }
}
