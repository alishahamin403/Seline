import SwiftUI
import UIKit

struct ConversationSearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var deepSeekService = GeminiService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom: UUID?
    @State private var inputHeight: CGFloat = 44
    @State private var isStreamingResponse = false
    @State private var streamingStartTime: Date?
    @State private var elapsedTimeUpdateTrigger = UUID() // Triggers elapsed time updates
    @State private var generatedFollowUpQuestions: [String] = []
    @State private var isGeneratingFollowUps = false
    @State private var showingSettings = false
    @State private var showingTokenDetails = false
    @State private var showingHistorySheet = false
    @State private var showingHistorySidebar = false
    @StateObject private var speechService = SpeechRecognitionService.shared
    @StateObject private var ttsService = TextToSpeechService.shared
    @StateObject private var emailService = EmailService.shared
    @State private var selectedEmail: Email? = nil
    @State private var selectedNote: Note? = nil
    @State private var selectedTask: TaskItem? = nil
    @State private var selectedLocation: SavedPlace? = nil
    @State private var isProcessingResponse = false // Track if LLM is responding
    @State private var lastMeaningfulTranscript = ""
    @State private var streamingElapsedTimer: Timer?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerView
                conversationScrollView
                inputAreaView
            }
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .onChange(of: searchService.isLoadingQuestionResponse) { newValue in
            if newValue {
                // Started streaming
                isStreamingResponse = true
                streamingStartTime = Date()
            } else {
                // Stopped streaming
                isStreamingResponse = false
                streamingStartTime = nil
            }
        }
        .onAppear {
            // Don't auto-focus on appear - let user see the greeting first
            // isInputFocused = true

            // Load daily usage stats
            Task {
                await deepSeekService.loadDailyUsage()
                
                // Proactive Briefing removed to show EmptyStateView instead

            }

            // Set up timer to update elapsed time while streaming
            streamingElapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if isStreamingResponse {
                    elapsedTimeUpdateTrigger = UUID()
                }
            }
            
            // Set up transcription callback
            speechService.onTranscriptionUpdate = { text in
                messageText = text
            }

            // Auto-send on silence disabled (speak mode removed); user sends with button
            speechService.onAutoSend = { }
        }
        .onDisappear {
            streamingElapsedTimer?.invalidate()
            streamingElapsedTimer = nil
            // Persist current chat: save title and to Supabase. Do not clear conversation
            // so the same chat stays open when user switches tabs or reopens the app.
            Task {
                await searchService.generateFinalConversationTitle()
                await searchService.saveConversationToSupabase()
                DispatchQueue.main.async {
                    speechService.stopRecording()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("GeofenceVisitCreated"))) { _ in
            // Trigger proactive question for new location visits
            Task {
                await showProactiveQuestionIfNeeded()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingTokenDetails) {
            TokenUsageDetailsSheet()
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
                .presentationBg()
        }
        .sheet(isPresented: $showingHistorySheet) {
            ConversationHistorySheet(
                onSelectConversation: { conversation in
                    searchService.loadConversation(withId: conversation.id)
                    showingHistorySheet = false
                },
                onDeleteConversation: { conversation in
                    searchService.deleteConversation(withId: conversation.id)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBg()
        }
        .overlay(historySidebarOverlay)
        .fullScreenCover(item: $selectedEmail) { email in
            NavigationView {
                EmailDetailView(email: email)
            }
            .presentationBg()
        }
        .sheet(item: $selectedNote) { note in
            NoteEditView(note: note, isPresented: Binding<Bool>(
                get: { selectedNote != nil },
                set: { if !$0 { selectedNote = nil } }
            ))
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBg()
        }
        .sheet(item: $selectedTask) { task in
            NavigationStack {
                ViewEventView(
                    task: task,
                    onEdit: { selectedTask = nil },
                    onDelete: { _ in selectedTask = nil },
                    onDeleteRecurringSeries: { _ in selectedTask = nil }
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBg()
        }
        .sheet(item: $selectedLocation) { place in
            PlaceDetailSheet(place: place, onDismiss: { selectedLocation = nil }, isFromRanking: false)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBg()
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack {
            Spacer()
            
            // Claude-style centered greeting
            VStack(spacing: 20) {
                // Coral sparkle icon (no circle background)
                Image(systemName: "sparkles")
                    .font(FontManager.geist(size: 32, weight: .medium))
                    .foregroundColor(Color.claudeAccent)
                
                // Single line greeting matching Claude's style
                Text(claudeGreetingText)
                    .font(FontManager.geist(size: 26, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.claudeTextDark : Color.claudeTextLight)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hi there"
        }
    }
    
    // Claude-style greeting: "How can I help you this morning/afternoon/evening/night?"
    private var claudeGreetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "How can I help you this morning?"
        case 12..<17: return "How can I help you this afternoon?"
        case 17..<21: return "How can I help you this evening?"
        default: return "How can I help you tonight?"
        }
    }
    
    private var userFirstName: String {
        if let fullName = authManager.currentUser?.profile?.name {
            let components = fullName.components(separatedBy: " ")
            return components.first ?? fullName
        }
        return ""
    }
    
    
    private var contextualSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggestions")
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(generateContextualSuggestions(), id: \.self) { suggestion in
                        Button(action: {
                            HapticManager.shared.light()
                            messageText = suggestion
                            isInputFocused = true
                        }) {
                            Text(suggestion)
                                .font(FontManager.geist(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.2))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
    
    private func modernPromptCard(icon: String, prompt: String, gradient: [Color]) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            let question = prompt
            Task {
                await searchService.addConversationMessage(question)
            }
        }) {
            HStack(spacing: 12) {
                Text(icon)
                    .font(FontManager.geist(size: 20, weight: .regular))
                
                Text(prompt)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.2))
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(FontManager.geist(size: 18, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: gradient),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func generateContextualSuggestions() -> [String] {
        // Generate smart suggestions based on current input
        let lowercased = messageText.lowercased()

        if lowercased.contains("spend") || lowercased.contains("money") || lowercased.contains("expense") {
            return [
                "How much did I spend this month?",
                "Show my spending by category",
                "What was my biggest expense?"
            ]
        } else if lowercased.contains("calendar") || lowercased.contains("schedule") || lowercased.contains("event") {
            return [
                "What's on my calendar today?",
                "Show my upcoming events",
                "When is my next meeting?"
            ]
        } else if lowercased.contains("note") || lowercased.contains("reminder") {
            return [
                "Show my recent notes",
                "Find notes about...",
                "What did I write about yesterday?"
            ]
        } else if lowercased.contains("location") || lowercased.contains("place") || lowercased.contains("where") {
            return [
                "Where have I been today?",
                "Show my recent locations",
                "What places did I visit this week?"
            ]
        }

        // Default suggestions
        return [
            "How much did I spend this month?",
            "What's on my calendar?",
            "Show my recent notes",
            "Where have I been?"
        ]
    }

    private func generateFollowUpQuestions() -> [String] {
        return generatedFollowUpQuestions
    }

    private func generateFollowUpQuestionsFromLLM() async {
        // Only generate if we have conversation history
        guard !searchService.conversationHistory.isEmpty,
              let lastMessage = searchService.conversationHistory.last,
              !lastMessage.isUser else {
            generatedFollowUpQuestions = []
            return
        }

        isGeneratingFollowUps = true

        // Build context from last 2-3 messages
        let recentMessages = Array(searchService.conversationHistory.suffix(4))
        var conversationContext = ""
        for message in recentMessages {
            let role = message.isUser ? "User" : "Assistant"
            conversationContext += "\(role): \(message.text)\n\n"
        }

        // Create prompt for generating follow-up questions
        let prompt = """
        Based on the following conversation, generate exactly 3 short, natural follow-up questions that the user might want to ask next. These should be relevant, specific, and help the user explore their data deeper.

        Conversation:
        \(conversationContext)

        Requirements:
        - Exactly 3 questions
        - Each question should be short and natural (max 6 words)
        - Questions should be relevant to what was just discussed
        - Focus on deeper insights, comparisons, or related data
        - Don't repeat information already covered
        - Format: One question per line, no numbers or bullets

        Example good questions:
        - Show me spending trends
        - Compare to last month
        - Any location streaks?
        - What are my habits?
        - Break down by category

        Generate 3 follow-up questions now:
        """

        do {
            // Call LLM to generate questions
            let response = try await deepSeekService.generateFollowUpQuestions(prompt: prompt)

            // Parse the response into individual questions
            let questions = response
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count > 5 } // Filter out empty lines and very short ones
                .map { question in
                    // Remove leading numbers, bullets, or dashes
                    var cleaned = question
                    cleaned = cleaned.replacingOccurrences(of: "^[0-9]+\\.\\s*", with: "", options: .regularExpression)
                    cleaned = cleaned.replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression)
                    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                .prefix(3)

            await MainActor.run {
                generatedFollowUpQuestions = Array(questions)
                isGeneratingFollowUps = false
            }
        } catch {
            print("❌ Error generating follow-up questions: \(error)")
            await MainActor.run {
                generatedFollowUpQuestions = []
                isGeneratingFollowUps = false
            }
        }
    }


    // MARK: - Subviews

    private var streamingIndicatorView: some View {
        VStack(spacing: 0) {
            // Progress bar animation
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    // Animated progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background bar
                            RoundedRectangle(cornerRadius: 2)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))

                            // Animated progress
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.blue.opacity(0.6),
                                            Color.blue.opacity(0.8)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * 0.6)
                                .animation(.linear(duration: 0.8).repeatForever(autoreverses: true), value: isStreamingResponse)
                        }
                    }
                    .frame(height: 2)

                    // Status text
                    HStack(spacing: 6) {
                        Text("✍️ Writing response...")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                        Spacer()

                        if let startTime = streamingStartTime {
                            Text(formatElapsedTime(since: startTime))
                                .font(FontManager.geist(size: 10, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                        }
                    }
                }

                // Stop button
                Button(action: {
                    HapticManager.shared.medium()
                    isStreamingResponse = false
                    searchService.stopCurrentRequest()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.96))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.black.opacity(0.9))
                            .frame(width: 10, height: 10)
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .transition(.opacity)
    }

    // MARK: - Subviews

    private var headerView: some View {
        ZStack {
            // Left side: Hamburger (history sidebar)
            HStack {
                Button(action: {
                    HapticManager.shared.selection()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingHistorySidebar = true
                    }
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(FontManager.geist(size: 18, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.claudeTextDark.opacity(0.8) : Color.claudeTextLight.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            
            // Center: Title
            Text("Chat")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.claudeTextDark : Color.claudeTextLight)
            
            // Right side: Utilized pill
            HStack(spacing: 8) {
                Spacer()
                
                Button(action: {
                    HapticManager.shared.selection()
                    showingTokenDetails = true
                }) {
                    Text("\(Int(deepSeekService.quotaPercentage))% utilized")
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.claudeTextDark.opacity(0.7) : Color.claudeTextLight.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            colorScheme == .dark ? Color.black : Color.white
        )
    }
    
    private var historySidebarOverlay: some View {
        InteractiveSidebarOverlay(
            isPresented: $showingHistorySidebar,
            canOpen: true,
            sidebarWidth: min(300, UIScreen.main.bounds.width * 0.82),
            colorScheme: colorScheme
        ) {
            ConversationHistorySheet(
                onSelectConversation: { conversation in
                    searchService.loadConversation(withId: conversation.id)
                    showingHistorySidebar = false
                },
                onDeleteConversation: { conversation in
                    searchService.deleteConversation(withId: conversation.id)
                },
                onDismiss: {
                    showingHistorySidebar = false
                }
            )
        }
    }

    private var conversationScrollView: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    if searchService.conversationHistory.isEmpty {
                        // Empty state - ensure it's visible
                        emptyStateView
                            .frame(minHeight: UIScreen.main.bounds.height * 0.6)
                            .padding(.top, 60)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(searchService.conversationHistory) { message in
                                ConversationMessageView(
                                    message: message,
                                    onSendMessage: { text in
                                        await searchService.addConversationMessage(text)
                                    },
                                    onRegenerate: { messageId in
                                        await searchService.regenerateResponse(for: messageId)
                                    },
                                    selectedEmail: $selectedEmail,
                                    selectedNote: $selectedNote,
                                    selectedTask: $selectedTask,
                                    selectedLocation: $selectedLocation
                                )
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                            }

                            // Modern loading indicator
                            if searchService.isLoadingQuestionResponse || isStreamingResponse {
                                ModernLoadingIndicator(colorScheme: colorScheme)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 100)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .mask(
                    // Fade mask that creates smooth fade at top
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.02),
                            .init(color: .black, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onChange(of: searchService.conversationHistory.count) { _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if let lastMessage = searchService.conversationHistory.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }

                    // Generate follow-up questions after assistant responds
                    if let lastMessage = searchService.conversationHistory.last,
                       !lastMessage.isUser {
                        Task {
                            await generateFollowUpQuestionsFromLLM()
                        }
                    }
                }
                // Auto-scroll while assistant text is streaming (count doesn't change during streaming updates)
                .onChange(of: elapsedTimeUpdateTrigger) { _ in
                    guard searchService.isLoadingQuestionResponse || isStreamingResponse else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if let lastMessage = searchService.conversationHistory.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to bottom when user returns to LLM chat from another tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let lastMessage = searchService.conversationHistory.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: searchService.lastMessageContentVersion) { _ in
                    // Re-scroll when last message gains event card, follow-ups, or sources so they stay visible
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if let lastMessage = searchService.conversationHistory.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var inputAreaView: some View {
        VStack(spacing: 0) {
            // Follow-up question suggestions (based on conversation context)
            if !searchService.conversationHistory.isEmpty && messageText.isEmpty {
                followUpQuestionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
            }

            // Smart suggestions bar above input (only when typing in empty state)
            if isInputFocused && !messageText.isEmpty && searchService.conversationHistory.isEmpty {
                smartSuggestionsBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            inputBoxContainer
        }
        .background(colorScheme == .dark ? Color.black : Color.white)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isInputFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: messageText.isEmpty)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: searchService.conversationHistory.count)
    }
    
    private var followUpQuestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(generateFollowUpQuestions(), id: \.self) { question in
                    Button(action: {
                        HapticManager.shared.light()
                        messageText = question
                        sendMessage()
                    }) {
                        Text(question)
                            .font(FontManager.geist(size: 13, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.2))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var smartSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(generateContextualSuggestions().prefix(3), id: \.self) { suggestion in
                    Button(action: {
                        HapticManager.shared.light()
                        messageText = suggestion
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(FontManager.geist(size: 10, weight: .medium))
                            Text(suggestion)
                                .font(FontManager.geist(size: 13, weight: .medium))
                        }
                        .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.2))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1),
                                            lineWidth: 1
                                        )
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var inputBoxContainer: some View {
        HStack(alignment: .center, spacing: 12) {
            inputTextEditor
            chatMicButton
            sendButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(height: inputHeight)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var inputTextEditor: some View {
        ZStack(alignment: .leading) {
            // Claude-style placeholder - only show when not focused and text is empty
            if messageText.isEmpty && !isInputFocused {
                HStack {
                    Text(searchService.conversationHistory.isEmpty ? "Chat with Seline" : "Reply to Seline")
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.claudeTextDark.opacity(0.4) : Color.claudeTextLight.opacity(0.4))
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            AlignedTextEditor(
                text: $messageText,
                colorScheme: colorScheme,
                height: max(inputHeight - 20, 36),
                onFocusChange: { focused in
                    isInputFocused = focused
                },
                onSend: {
                    sendMessage()
                }
            )
            .onChange(of: messageText) { _ in
                updateInputHeight()
            }
            .onChange(of: speechService.transcribedText) { newText in
                if speechService.shouldIgnoreTranscriptionUpdates { return }
                // If user starts speaking while TTS is active or LLM is generating, stop everything.
                let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                let isMeaningful = trimmed.count >= 3 && trimmed.rangeOfCharacter(from: .letters) != nil
                let isNewEnough = trimmed != lastMeaningfulTranscript
                
                if isMeaningful && isNewEnough && (ttsService.isSpeaking || searchService.isLoadingQuestionResponse || isStreamingResponse) {
                    ttsService.stopSpeaking()
                    searchService.stopCurrentRequest()
                    isStreamingResponse = false
                    isProcessingResponse = false
                    HapticManager.shared.light()
                }
                
                if !trimmed.isEmpty {
                    messageText = newText
                    updateInputHeight()
                    if isMeaningful {
                        lastMeaningfulTranscript = trimmed
                    }
                }
            }
            .onAppear {
                updateInputHeight()
                speechService.onTranscriptionUpdate = { text in
                    if speechService.shouldIgnoreTranscriptionUpdates { return }
                    messageText = text
                    updateInputHeight()
                }
            }
        }
    }

    private func updateInputHeight() {
        let size = CGSize(width: UIScreen.main.bounds.width - 120, height: .infinity)
        let estimatedHeight = messageText.boundingRect(
            with: size,
            options: .usesLineFragmentOrigin,
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .regular)],
            context: nil
        ).height + 28

        let maxHeight: CGFloat = 120
        let minHeight: CGFloat = 44
        inputHeight = min(max(estimatedHeight, minHeight), maxHeight)
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🎙️ sendMessage called with text: '\(trimmed.prefix(50))...' (isProcessing: \(isProcessingResponse), isSpeaking: \(ttsService.isSpeaking))")

        guard !trimmed.isEmpty else {
            print("🎙️ sendMessage aborted - empty text")
            return
        }

        // If already processing, don't accept new messages
        // (This should be prevented by UI, but double-check)
        if isProcessingResponse || ttsService.isSpeaking {
            print("🎙️ sendMessage aborted - system is busy")
            return
        }

        // Stop recording if active
        if speechService.isRecording {
            print("🎙️ Stopping recording before sending")
            speechService.stopRecording()
        }

        HapticManager.shared.medium()
        let query = messageText

        // Clear UI immediately so previous prompt doesn't stay in the box
        messageText = ""
        speechService.clearTranscription()
        speechService.shouldIgnoreTranscriptionUpdates = true
        updateInputHeight()
        isInputFocused = false

        isProcessingResponse = true

        Task {
            await searchService.addConversationMessage(query)

            await waitForResponseToComplete()

            isProcessingResponse = false
            // Re-enable transcription updates after a short delay so next voice input works
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            speechService.shouldIgnoreTranscriptionUpdates = false
        }
    }
    
    private func waitForResponseToComplete() async {
        // Wait until streaming is complete
        while searchService.isLoadingQuestionResponse || isStreamingResponse {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }
    

    private func formatElapsedTime(since startDate: Date) -> String {
        let elapsed = Date().timeIntervalSince(startDate)
        let seconds = Int(elapsed) % 60
        let minutes = Int(elapsed) / 60

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    private var chatMicButton: some View {
        Button(action: {
            HapticManager.shared.selection()
            if speechService.isRecording {
                speechService.stopRecording()
            } else {
                Task {
                    speechService.shouldIgnoreTranscriptionUpdates = false
                    speechService.clearTranscription()
                    messageText = ""
                    try? await speechService.startRecording()
                }
            }
        }) {
            if speechService.isRecording {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.96))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.9))
                        .frame(width: 12, height: 12)
                }
            } else {
                Image(systemName: "mic.fill")
                    .font(FontManager.geist(size: 17, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.claudeTextDark.opacity(0.82) : Color.claudeTextLight.opacity(0.82))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    )
            }
        }
        .frame(width: 36, height: 36)
        .buttonStyle(PlainButtonStyle())
    }

    private var sendButton: some View {
        Button(action: {
            // If loading, stop the request; otherwise send the message
            if searchService.isLoadingQuestionResponse || isStreamingResponse {
                HapticManager.shared.medium()
                isStreamingResponse = false
                searchService.stopCurrentRequest()
            } else {
                sendMessage()
            }
        }) {
            // Claude-style: stop button when streaming, send arrow when ready
            if searchService.isLoadingQuestionResponse || isStreamingResponse {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.96))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.9))
                        .frame(width: 12, height: 12)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                                : (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.1))
                        )
                    Image(systemName: "arrow.up")
                        .font(FontManager.geist(size: 16, weight: .semibold))
                        .foregroundColor(
                            messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? (colorScheme == .dark ? Color.claudeTextDark.opacity(0.5) : Color.claudeTextLight.opacity(0.5))
                                : (colorScheme == .dark ? Color.claudeTextDark : Color.claudeTextLight)
                        )
                }
            }
        }
        .frame(width: 36, height: 36)
        .buttonStyle(PlainButtonStyle())
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(searchService.isLoadingQuestionResponse || isStreamingResponse))
        .animation(.easeInOut(duration: 0.15), value: messageText)
        .animation(.easeInOut(duration: 0.15), value: searchService.isLoadingQuestionResponse)
        .animation(.easeInOut(duration: 0.15), value: isStreamingResponse)
    }

    private var inputBoxBorder: some View {
        RoundedRectangle(cornerRadius: 22)
            .stroke(
                isInputFocused
                    ? (colorScheme == .dark ? Color.blue.opacity(0.4) : Color.blue.opacity(0.3))
                    : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)),
                lineWidth: isInputFocused ? 1.5 : 1
            )
    }
    
    // MARK: - Proactive Questioning
    
    private func showProactiveQuestionIfNeeded() async {
        // Only show proactive questions if in conversation mode
        guard searchService.isInConversationMode else { return }
        
        // Check for newly created active visits
        let geofenceManager = GeofenceManager.shared
        let locationsManager = LocationsManager.shared
        
        // Get active visits - use getActiveVisit for thread-safe access
        // Find the most recently created active visit
        let savedPlaces = locationsManager.savedPlaces
        var mostRecentVisit: (placeId: UUID, visit: LocationVisitRecord)? = nil
        
        // Iterate through saved places and check for active visits
        for place in savedPlaces {
            if let visit = geofenceManager.getActiveVisit(for: place.id) {
                if let current = mostRecentVisit {
                    if visit.entryTime > current.visit.entryTime {
                        mostRecentVisit = (place.id, visit)
                    }
                } else {
                    mostRecentVisit = (place.id, visit)
                }
            }
        }
        
        guard let (placeId, visit) = mostRecentVisit else { return }
        
        // Check if this visit is recent (created in last 30 seconds) to avoid duplicate questions
        let visitAge = Date().timeIntervalSince(visit.entryTime)
        guard visitAge < 30 else { return }
        
        // Check if we already asked about this visit recently
        let recentMessages = searchService.conversationHistory.suffix(5)
        let alreadyAsked = recentMessages.contains { message in
            message.proactiveQuestion?.locationId == placeId
        }
        guard !alreadyAsked else { return }
        
        // Get location details
        guard let place = locationsManager.savedPlaces.first(where: { $0.id == placeId }) else { return }
        
        // Check if this is first visit or returning visit
        await LocationVisitAnalytics.shared.fetchStats(for: placeId)
        let visitStats = LocationVisitAnalytics.shared.visitStats[placeId]
        let isFirstVisit = (visitStats?.totalVisits ?? 0) <= 1
        
        // Generate proactive question
        let question = ProactiveQuestionGenerator.generateQuestion(
            for: place.displayName,
            isFirstVisit: isFirstVisit
        )
        
        // Create proactive question message
        let questionInfo = ProactiveQuestionInfo(
            locationId: placeId,
            locationName: place.displayName,
            question: question,
            isFirstVisit: isFirstVisit
        )
        
        // Add as assistant message with proactive question
        let questionMessage = ConversationMessage(
            isUser: false,
            text: question,
            timestamp: Date(),
            intent: .general,
            proactiveQuestion: questionInfo
        )
        
        await MainActor.run {
            searchService.conversationHistory.append(questionMessage)
            // Note: saveConversationLocally is private, but appending to conversationHistory
            // will be saved automatically when conversation is saved to Supabase
        }
    }

}

struct ConversationMessageView: View {
    let message: ConversationMessage
    let onSendMessage: (String) async -> Void
    let onRegenerate: ((UUID) async -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @State private var showContextMenu = false
    @StateObject private var searchService = SearchService.shared
    @StateObject private var emailService = EmailService.shared
    @StateObject private var notesManager = NotesManager.shared
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var locationsManager = LocationsManager.shared
    @Binding var selectedEmail: Email?
    @Binding var selectedNote: Note?
    @Binding var selectedTask: TaskItem?
    @Binding var selectedLocation: SavedPlace?
    @State private var showingEventCreationResult = false
    @State private var eventCreationMessage = ""
    @State private var eventCreationIsError = false
    @State private var revealTokens: [String] = []
    @State private var revealedWordCount: Int = 0
    @State private var wordRevealTimer: Timer?

    // Determine if message has complex formatting
    private var hasComplexFormatting: Bool {
        message.text.contains("**") || message.text.contains("*") ||
            message.text.contains("`") || message.text.contains("- ") ||
            message.text.contains("• ") || message.text.contains("\n")
    }

    // Check if this message is currently being streamed
    private var isStreaming: Bool {
        guard !message.isUser else { return false }

        // Check if this is the last message and we're loading
        if let lastMessage = searchService.conversationHistory.last,
           lastMessage.id == message.id,
           searchService.isLoadingQuestionResponse {
            return true
        }
        return false
    }

    // Check if this is the last assistant message (for typewriter animation)
    private var isLastAssistantMessage: Bool {
        guard !message.isUser else { return false }
        if let lastMessage = searchService.conversationHistory.last,
           lastMessage.id == message.id {
            return true
        }
        return false
    }


    private var previousUserMessage: String? {
        guard let index = searchService.conversationHistory.firstIndex(where: { $0.id == message.id }) else {
            return nil
        }
        for idx in stride(from: index - 1, through: 0, by: -1) {
            let msg = searchService.conversationHistory[idx]
            if msg.isUser {
                return msg.text
            }
        }
        return nil
    }

    private var displayedMessageText: String {
        message.text
    }

    private func tokenizeWordsPreservingWhitespace(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let pattern = "\\S+\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        let tokens = matches.compactMap { match -> String? in
            guard let tokenRange = Range(match.range, in: text) else { return nil }
            return String(text[tokenRange])
        }
        return tokens.isEmpty ? [text] : tokens
    }

    private func syncWordRevealState(initial: Bool = false) {
        let tokens = tokenizeWordsPreservingWhitespace(message.text)
        revealTokens = tokens
        revealedWordCount = tokens.count
        stopWordRevealTimer()
    }

    private func startWordRevealTimerIfNeeded() {
        guard wordRevealTimer == nil else { return }
        wordRevealTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            if revealedWordCount < revealTokens.count {
                withAnimation(.easeInOut(duration: 0.1)) {
                    revealedWordCount += 1
                }
            } else if !isStreaming {
                stopWordRevealTimer()
            }
        }
    }

    private func stopWordRevealTimer() {
        wordRevealTimer?.invalidate()
        wordRevealTimer = nil
    }

    var body: some View {
        VStack {
            HStack {
                if message.isUser {
                    Spacer()
                }

                messageContent
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, message.isUser ? 14 : 0)
                    .padding(.vertical, message.isUser ? 12 : 4)
                    .background(messageBackground)
                    .overlay(messageBorder)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = message.text
                            HapticManager.shared.selection()
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }

                        if !message.isUser, let regenerate = onRegenerate {
                            Button(action: {
                                HapticManager.shared.medium()
                                Task {
                                    await regenerate(message.id)
                                }
                            }) {
                                Label("Regenerate", systemImage: "arrow.clockwise")
                            }
                        }

                        if message.isUser {
                            Button(role: .destructive, action: {
                                HapticManager.shared.delete()
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                if !message.isUser {
                    Spacer()
                }
            }
            .padding(.leading, message.isUser ? 48 : 16)
            .padding(.trailing, message.isUser ? 16 : 16)
        }
        .alert(isPresented: $showingEventCreationResult) {
            Alert(
                title: Text(eventCreationIsError ? "Error" : "Success"),
                message: Text(eventCreationMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            syncWordRevealState(initial: true)
        }
        .onChange(of: message.text) { _ in
            syncWordRevealState()
        }
        .onChange(of: isLastAssistantMessage) { _ in
            syncWordRevealState()
        }
        .onChange(of: isStreaming) { _ in
            syncWordRevealState()
        }
        .onDisappear {
            stopWordRevealTimer()
        }
    }

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            messageText
            
            // ETA Map Card - shows when there's location data
            if let locationInfo = message.locationInfo {
                ETAMapCard(locationInfo: locationInfo)
                    .padding(.top, 4)
            }
            
            // Event Creation Card - shows when there's event creation data
            if let events = message.eventCreationInfo, !events.isEmpty {
                EventCreationCard(
                    events: events,
                    onConfirm: { confirmedEvents in
                        Task {
                            await createEvents(confirmedEvents)
                        }
                    },
                    onCancel: {
                        // Just dismiss - user can ask again if needed
                    }
                )
                .padding(.top, 4)
            }
            
            // Proactive Question Card - shows when there's a proactive question
            if let questionInfo = message.proactiveQuestion {
                ProactiveQuestionCard(
                    locationName: questionInfo.locationName,
                    question: questionInfo.question,
                    onAnswer: { answer in
                        await handleProactiveQuestionAnswer(
                            locationId: questionInfo.locationId,
                            answer: answer,
                            isFirstVisit: questionInfo.isFirstVisit
                        )
                    }
                )
                .padding(.top, 4)
            }

            followUpSuggestionsView
        }
    }
    
    private func getOrCreateTagForCategory(_ category: String) -> String? {
        let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)

        // Personal is the default (nil tagId)
        if normalizedCategory.lowercased() == "personal" {
            return nil
        }

        // Check if tag already exists
        let tagManager = TagManager.shared
        if let existingTag = tagManager.tags.first(where: {
            $0.name.lowercased() == normalizedCategory.lowercased()
        }) {
            return existingTag.id
        }

        // Create new tag for this category
        if let newTag = tagManager.createTag(name: normalizedCategory) {
            return newTag.id
        }

        return nil
    }

    private func createEvents(_ events: [EventCreationInfo]) async {
        let taskManager = TaskManager.shared
        let calendar = Calendar.current

        for event in events {
            // Determine the weekday from the event date
            let weekdayNum = calendar.component(.weekday, from: event.date)
            let weekday = weekdayFromNumber(weekdayNum)

            // Convert reminder minutes to ReminderTime
            let reminderTime: ReminderTime? = {
                guard let minutes = event.reminderMinutes else { return nil }
                switch minutes {
                case 0..<10: return .fifteenMinutes
                case 10..<45: return .fifteenMinutes
                case 45..<120: return .oneHour
                case 120..<720: return .threeHours
                default: return .oneDay
                }
            }()

            // Map category to tag ID
            let tagId = getOrCreateTagForCategory(event.category)

            // Use TaskManager.addTask with correct parameters
            await MainActor.run {
                taskManager.addTask(
                    title: event.title,
                    to: weekday,
                    description: event.notes,
                    scheduledTime: event.hasTime ? event.date : nil,
                    endTime: nil,
                    targetDate: event.date,
                    reminderTime: reminderTime,
                    location: event.location,
                    isRecurring: false,
                    recurrenceFrequency: nil,
                    customRecurrenceDays: nil,
                    tagId: tagId
                )
            }
        }

        // Show feedback to user
        await MainActor.run {
            HapticManager.shared.success()
            eventCreationMessage = events.count == 1
                ? "Event created successfully"
                : "Successfully created \(events.count) events"
            eventCreationIsError = false
            showingEventCreationResult = true
        }
    }
    
    private func handleProactiveQuestionAnswer(locationId: UUID, answer: String, isFirstVisit: Bool) async {
        let extractionService = NaturalLanguageExtractionService.shared
        let memoryService = LocationMemoryService.shared
        
        // Extract information from user's answer
        let extractedInfo = extractionService.extractInfo(from: answer)
        
        // Save to location memory based on visit type
        do {
            if isFirstVisit {
                // For first visit, save as purpose
                try await memoryService.saveMemory(
                    placeId: locationId,
                    type: .purpose,
                    content: extractedInfo.rawText
                )
            } else {
                // For returning visits, save as purchase if items mentioned
                if !extractedInfo.items.isEmpty {
                    try await memoryService.saveMemory(
                        placeId: locationId,
                        type: .purchase,
                        content: extractedInfo.rawText,
                        items: extractedInfo.items,
                        frequency: extractedInfo.frequency
                    )
                } else if let purpose = extractedInfo.purpose {
                    // If no items but purpose mentioned, save as purpose
                    try await memoryService.saveMemory(
                        placeId: locationId,
                        type: .purpose,
                        content: extractedInfo.rawText
                    )
                }
            }
            
            // Add user's answer as a message in conversation
            await onSendMessage(answer)
            
            print("✅ Saved location memory for \(locationId): \(extractedInfo.rawText)")
        } catch {
            print("❌ Failed to save location memory: \(error)")
            // Still add the answer to conversation even if memory save fails
            await onSendMessage(answer)
        }
    }
    
    private func weekdayFromNumber(_ num: Int) -> WeekDay {
        switch num {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
    
    private func getCategoryId(for categoryName: String) -> String? {
        // This should match your category system
        // For now, return nil to use default category
        return nil
    }

    @ViewBuilder
    private var entityPillsRow: some View {
        let contentPills: [RelevantContentInfo] = message.relevantContent ?? []
        let eventPills: [EventCreationInfo] = message.eventCreationInfo ?? []
        if contentPills.isEmpty && eventPills.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(contentPills) { item in
                        sourcePill(
                            sourceLabel: sourceLabelForContentType(item),
                            title: displayTitle(for: item),
                            icon: iconForContentType(item.contentType)
                        ) {
                            openRelevantContent(item)
                        }
                    }
                    ForEach(eventPills) { event in
                        sourcePill(sourceLabel: "Calendar", title: event.title, icon: "calendar") {
                            // Event creation items don't have a TaskItem yet
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func sourceLabelForContentType(_ item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .email: return "Email"
        case .note:
            let folder = (item.noteFolder ?? "").lowercased()
            return folder.contains("receipt") ? "Receipt" : "Note"
        case .event: return "Calendar"
        case .location: return "Place"
        }
    }

    private func displayTitle(for item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .email: return item.emailSubject ?? "Email"
        case .note: return item.noteTitle ?? "Note"
        case .event: return item.eventTitle ?? "Event"
        case .location: return item.locationName ?? "Place"
        }
    }

    private func iconForContentType(_ type: RelevantContentInfo.ContentType) -> String {
        switch type {
        case .email: return "envelope"
        case .note: return "note.text"
        case .event: return "calendar"
        case .location: return "mappin"
        }
    }

    private func openRelevantContent(_ item: RelevantContentInfo) {
        HapticManager.shared.cardTap()
        switch item.contentType {
        case .email:
            if let id = item.emailId {
                let all = emailService.inboxEmails + emailService.sentEmails
                if let email = all.first(where: { $0.id == id }) {
                    selectedEmail = email
                }
            }
        case .note:
            if let id = item.noteId,
               let note = notesManager.notes.first(where: { $0.id == id }) {
                selectedNote = note
            }
        case .event:
            if let id = item.eventId {
                let all = taskManager.getAllTasksIncludingArchived()
                if let task = all.first(where: { $0.id == id.uuidString }) {
                    selectedTask = task
                }
            }
        case .location:
            if let id = item.locationId,
               let place = locationsManager.savedPlaces.first(where: { $0.id == id }) {
                selectedLocation = place
            }
        }
    }

    /// Inline source pill (no icon): text-only, horizontal, where [[0]] appears in the message. Tappable to open the item.
    private func inlineSourcePill(citationIndex index: Int) -> some View {
        let content = message.relevantContent ?? []
        guard index >= 0, index < content.count else { return AnyView(EmptyView()) }
        let item = content[index]
        let label = sourceLabelForContentType(item)
        return AnyView(
            Button(action: { openRelevantContent(item) }) {
                Text(label)
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color(white: 0.25))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorScheme == .dark ? Color(white: 0.25) : Color(white: 0.86))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: true, vertical: true)
        )
    }

    /// Text-only source pill for the row below message (no icon). Horizontal label only.
    private func sourcePill(sourceLabel: String, title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(sourceLabel)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color(white: 0.25))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.88))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .fixedSize(horizontal: true, vertical: true)
    }

    private func entityPill(title: String, icon: String, action: @escaping () -> Void) -> some View {
        sourcePill(sourceLabel: title, title: "", icon: icon, action: action)
    }

    private var messageText: some View {
        let segments = parseMessageSegments(displayedMessageText)
        let hasWidgets = segments.contains {
            if case .widget = $0.type { return true }
            return false
        }

        return VStack(alignment: .leading, spacing: 12) {
            if !message.isUser && !hasWidgets {
                inlineCitationTextContent(segments: segments)
            } else {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segmentView(segment)
                }
            }

            if isStreaming {
                StreamingCursor(colorScheme: colorScheme)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: displayedMessageText)
    }

    @ViewBuilder
    private func segmentView(_ segment: MessageSegment) -> some View {
        switch segment.type {
        case .text(let content):
            Group {
                if hasComplexFormatting && !message.isUser {
                    MarkdownText(markdown: content, colorScheme: colorScheme)
                } else if !message.isUser {
                    SimpleTextWithPhoneLinks(text: content, colorScheme: colorScheme)
                } else {
                    Text(content)
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor(
                            message.isUser
                                ? (colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88))
                                : Color.shadcnForeground(colorScheme)
                        )
                        .lineLimit(nil)
                }
            }
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: isStreaming ? 0.92 : 1.0),
                        .init(color: .black.opacity(isStreaming ? 0.7 : 1.0), location: isStreaming ? 0.98 : 1.0),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .animation(.easeOut(duration: 0.18), value: content.count)
        case .citation(let index):
            inlineSourcePill(citationIndex: index)
        case .widget(let type):
            renderWidget(type)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private enum InlineRun {
        case text(String)
        case citation(Int)
    }

    @ViewBuilder
    private func inlineCitationTextContent(segments: [MessageSegment]) -> some View {
        let lines = buildInlineCitationLines(from: segments)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, lineRuns in
                if isInlineLineBlank(lineRuns) {
                    Color.clear.frame(height: 10)
                } else {
                    let parsed = parseBulletLine(from: lineRuns)
                    let heading = detectInlineHeading(from: parsed.runs)
                    let showBullet = parsed.hasBullet && !heading.consumeBullet
                    if hasRenderableInlineContent(parsed.runs) {
                        VStack(alignment: .leading, spacing: 6) {
                            if shouldShowSectionDivider(for: index, in: lines) {
                                Rectangle()
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10))
                                    .frame(height: 0.5)
                                    .padding(.bottom, 4)
                            }

                            HStack(alignment: .top, spacing: 6) {
                                if showBullet {
                                    Text(parsed.level == 0 ? "•" : "◦")
                                        .font(FontManager.geist(size: 14, weight: parsed.level == 0 ? .bold : .medium))
                                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                                        .padding(.top, 1)
                                }

                                WrappingInlineLayout(spacing: 0, rowSpacing: 6) {
                                    ForEach(Array(parsed.runs.enumerated()), id: \.offset) { _, run in
                                        switch run {
                                        case .text(let token):
                                            let cleaned = cleanInlineMarkdownToken(token)
                                            if !cleaned.isEmpty {
                                                Text(cleaned)
                                                    .font(
                                                        heading.level > 0
                                                            ? FontManager.geist(size: heading.level == 1 ? 20 : 16, weight: heading.level == 1 ? .bold : .semibold)
                                                            : FontManager.geist(size: 14, weight: .regular)
                                                    )
                                                    .foregroundColor(
                                                        heading.level == 1
                                                            ? (colorScheme == .dark ? .white : .black)
                                                            : heading.level == 2
                                                                ? (colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                                                                : Color.shadcnForeground(colorScheme)
                                                    )
                                            }
                                        case .citation(let index):
                                            inlineSourcePill(citationIndex: index)
                                        }
                                    }
                                }
                            }
                            .padding(.leading, showBullet ? CGFloat(parsed.level) * 18 : 0)
                            .padding(.top, heading.level == 1 ? 5 : heading.level == 2 ? 2 : 0)
                            .padding(.bottom, heading.level > 0 ? 2 : 0)
                        }
                    }
                }
            }
        }
    }

    private func buildInlineCitationLines(from segments: [MessageSegment]) -> [[InlineRun]] {
        var lines: [[InlineRun]] = [[]]

        func appendTextTokenized(_ text: String) {
            let splitLines = text.components(separatedBy: "\n")
            for (lineIndex, part) in splitLines.enumerated() {
                let leadingWhitespaceCount = part.prefix { $0 == " " || $0 == "\t" }.count
                if leadingWhitespaceCount > 0 {
                    lines[lines.count - 1].append(.text(String(repeating: " ", count: leadingWhitespaceCount)))
                }
                if !part.isEmpty {
                    let tokens = tokenizeWordsPreservingWhitespace(part)
                    for token in tokens where !token.isEmpty {
                        lines[lines.count - 1].append(.text(token))
                    }
                }

                if lineIndex < splitLines.count - 1 {
                    lines.append([])
                }
            }
        }

        for segment in segments {
            switch segment.type {
            case .text(let content):
                appendTextTokenized(content)
            case .citation(let index):
                lines[lines.count - 1].append(.citation(index))
                lines[lines.count - 1].append(.text(" "))
            case .widget:
                break
            }
        }

        return lines
    }

    private func parseBulletLine(from runs: [InlineRun]) -> (hasBullet: Bool, level: Int, runs: [InlineRun]) {
        var mutableRuns = runs
        var leadingSpaces = 0

        if case .text(let token)? = mutableRuns.first, token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            leadingSpaces = token.count
            mutableRuns.removeFirst()
        }

        let level = max(0, leadingSpaces / 2)

        guard case .text(let firstToken)? = mutableRuns.first else {
            return (false, level, mutableRuns)
        }

        let trimmed = firstToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("•") else {
            return (false, level, mutableRuns)
        }

        var updated = firstToken
        if let range = updated.range(of: #"^\s*[-*•]\s*"#, options: .regularExpression) {
            updated.removeSubrange(range)
        }
        mutableRuns.removeFirst()
        if !updated.isEmpty {
            mutableRuns.insert(.text(updated), at: 0)
        }

        return (true, level, mutableRuns)
    }

    private func cleanInlineMarkdownToken(_ token: String) -> String {
        var cleaned = token
        cleaned = cleaned.replacingOccurrences(of: "^\\s*#{1,6}\\s*", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "__", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\\[\\s*\\d+\\s*\\]", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\*+", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
        return cleaned
    }

    private struct InlineHeading {
        let level: Int
        let consumeBullet: Bool
    }

    private func detectInlineHeading(from runs: [InlineRun]) -> InlineHeading {
        let text = runs.compactMap { run -> String? in
            if case .text(let token) = run { return token }
            return nil
        }.joined()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return InlineHeading(level: 0, consumeBullet: false) }
        if trimmed.hasPrefix("# ") { return InlineHeading(level: 1, consumeBullet: false) }
        if trimmed.hasPrefix("## ") { return InlineHeading(level: 2, consumeBullet: false) }
        if trimmed.hasPrefix("### ") { return InlineHeading(level: 3, consumeBullet: false) }
        if trimmed.hasPrefix("#### ") { return InlineHeading(level: 4, consumeBullet: false) }

        let dayPattern = #"^(?:\*\*)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|yesterday|tomorrow|[A-Za-z]+,\s+[A-Za-z]+\s+\d{1,2}(?:,\s*\d{4})?)(?:\*\*)?:\s*$"#
        if trimmed.range(of: dayPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            return InlineHeading(level: 1, consumeBullet: true)
        }

        if trimmed.hasPrefix("**"), trimmed.hasSuffix("**") || trimmed.hasSuffix(":**") {
            return InlineHeading(level: 2, consumeBullet: true)
        }
        if trimmed.hasPrefix("*"), trimmed.hasSuffix(":") {
            return InlineHeading(level: 2, consumeBullet: true)
        }
        let plain = cleanInlineMarkdownToken(trimmed)
        if plain.hasSuffix(":") {
            let words = plain.dropLast().split(separator: " ")
            if words.count <= 6 {
                return InlineHeading(level: 2, consumeBullet: true)
            }
        }
        return InlineHeading(level: 0, consumeBullet: false)
    }

    private func hasRenderableInlineContent(_ runs: [InlineRun]) -> Bool {
        for run in runs {
            switch run {
            case .citation:
                return true
            case .text(let token):
                let cleaned = cleanInlineMarkdownToken(token)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!-•◦"))
                if !cleaned.isEmpty {
                    return true
                }
            }
        }
        return false
    }

    private func isInlineLineBlank(_ runs: [InlineRun]) -> Bool {
        var hasCitation = false
        let text = runs.compactMap { run -> String? in
            switch run {
            case .citation:
                hasCitation = true
                return nil
            case .text(let token):
                return token
            }
        }.joined()
        if hasCitation { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func shouldShowSectionDivider(for index: Int, in lines: [[InlineRun]]) -> Bool {
        guard index > 0 else { return false }

        let currentParsed = parseBulletLine(from: lines[index])
        let currentHeading = detectInlineHeading(from: currentParsed.runs)
        guard currentHeading.level == 1 else { return false }

        for previous in stride(from: index - 1, through: 0, by: -1) {
            if isInlineLineBlank(lines[previous]) { continue }
            let previousParsed = parseBulletLine(from: lines[previous])
            if hasRenderableInlineContent(previousParsed.runs) {
                return true
            }
        }
        return false
    }

    @ViewBuilder
    private func renderWidget(_ type: String) -> some View {
        switch type {
        case "SpendingChart":
            SpendingAndETAWidget(
                isVisible: true,
                onAddReceipt: {},
                onAddReceiptFromGallery: {}
            )
            .frame(height: 180)
            .cornerRadius(12)
            .padding(.top, 4)
            
        case "CalendarDayView":
            EventsCardWidget(showingAddEventPopup: .constant(false))
                .frame(maxHeight: 250)
                .cornerRadius(12)
                .padding(.top, 4)
                
        case "LocationMap":
            HomeFavoriteLocationsWidget(onLocationSelected: { _ in })
                .frame(height: 160)
                .cornerRadius(12)
                .padding(.top, 4)
            
        default:
            EmptyView()
        }
    }

    private struct MessageSegment: Identifiable {
        let id = UUID()
        let type: SegmentType
        
        enum SegmentType {
            case text(String)
            case widget(String)
            case citation(Int)  // inline source pill index into message.relevantContent
        }
    }

    private func parseMessageSegments(_ text: String) -> [MessageSegment] {
        // Normalize mixed citation formats like [[0]], [0], and [[0], [1]] into [0], [1].
        let normalized = text.replacingOccurrences(of: "[[", with: "[").replacingOccurrences(of: "]]", with: "]")
        let citationRegex = try! NSRegularExpression(pattern: "\\[\\s*(\\d+)\\s*\\]")
        let citationMatches = citationRegex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))

        var segments: [MessageSegment] = []
        var lastIndex = normalized.startIndex

        for match in citationMatches {
            guard
                let rangeInText = Range(match.range, in: normalized),
                let numRange = Range(match.range(at: 1), in: normalized),
                let index = Int(String(normalized[numRange]))
            else { continue }

            if rangeInText.lowerBound > lastIndex {
                let textContent = String(normalized[lastIndex..<rangeInText.lowerBound])
                if shouldRenderTextSegment(textContent) {
                    segments.append(.init(type: .text(textContent)))
                }
            }
            segments.append(.init(type: .citation(index)))
            lastIndex = rangeInText.upperBound
        }

        // Parse [WIDGET: ...] tags in the remaining text segments.
        let widgetRegex = try! NSRegularExpression(pattern: "\\[WIDGET: (.*?)\\]")
        if !citationMatches.isEmpty, lastIndex < normalized.endIndex {
            let remainderStr = String(normalized[lastIndex...])
            var segLast = remainderStr.startIndex
            for match in widgetRegex.matches(in: remainderStr, range: NSRange(remainderStr.startIndex..., in: remainderStr)) {
                guard let rangeInText = Range(match.range, in: remainderStr) else { continue }
                if rangeInText.lowerBound > segLast {
                    let textContent = String(remainderStr[segLast..<rangeInText.lowerBound])
                    if shouldRenderTextSegment(textContent) {
                        segments.append(.init(type: .text(textContent)))
                    }
                }
                if let typeRange = Range(match.range(at: 1), in: remainderStr) {
                    segments.append(.init(type: .widget(String(remainderStr[typeRange]))))
                } else {
                    segments.append(.init(type: .widget("Unknown")))
                }
                segLast = rangeInText.upperBound
            }
            if segLast < remainderStr.endIndex {
                let textContent = String(remainderStr[segLast...])
                if shouldRenderTextSegment(textContent) {
                    segments.append(.init(type: .text(textContent)))
                }
            }
        }

        if citationMatches.isEmpty {
            segments = []
            lastIndex = normalized.startIndex
            for match in widgetRegex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                guard let rangeInText = Range(match.range, in: normalized) else { continue }
                if rangeInText.lowerBound > lastIndex {
                    let textContent = String(normalized[lastIndex..<rangeInText.lowerBound])
                    if shouldRenderTextSegment(textContent) {
                        segments.append(.init(type: .text(textContent)))
                    }
                }
                if let typeRange = Range(match.range(at: 1), in: normalized) {
                    segments.append(.init(type: .widget(String(normalized[typeRange]))))
                } else {
                    segments.append(.init(type: .widget("Unknown")))
                }
                lastIndex = rangeInText.upperBound
            }
            if lastIndex < normalized.endIndex {
                let textContent = String(normalized[lastIndex...])
                if shouldRenderTextSegment(textContent) {
                    segments.append(.init(type: .text(textContent)))
                }
            }
        }

        return segments.isEmpty ? [.init(type: .text(normalized))] : segments
    }

    private func shouldRenderTextSegment(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let bracketJunk = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[],"))
        return !bracketJunk.isEmpty
    }
    
    /// Strip markdown formatting for voice mode display
    private func stripMarkdown(_ text: String) -> String {
        var result = text
        
        // Remove bold markers **text** -> text
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        
        // Remove italic markers *text* -> text (but not ** which we already handled)
        result = result.replacingOccurrences(of: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)", with: "$1", options: .regularExpression)
        
        // Remove code blocks ```text``` -> text
        result = result.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        
        // Remove inline code `text` -> text
        result = result.replacingOccurrences(of: "`(.+?)`", with: "$1", options: .regularExpression)
        
        // Process line by line for multiline patterns
        let lines = result.components(separatedBy: .newlines)
        result = lines.map { line in
            var processedLine = line
            
            // Remove headers # ## ### -> just the text
            processedLine = processedLine.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
            
            // Remove bullet points - or • at start of lines
            processedLine = processedLine.replacingOccurrences(of: "^[\\-•]\\s*", with: "", options: .regularExpression)
            
            // Remove numbered list markers (1. 2. etc)
            processedLine = processedLine.replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
            
            return processedLine
        }.joined(separator: "\n")
        
        // Clean up any leftover asterisks that might be standalone
        result = result.replacingOccurrences(of: "\\*{2,}", with: "")
        
        // Clean up excessive whitespace
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var evidenceSection: some View {
        let hasRelevantContent = message.relevantContent?.isEmpty == false
        let hasRelatedData = message.relatedData?.isEmpty == false

        if !message.isUser, hasRelevantContent || hasRelatedData {
            VStack(alignment: .leading, spacing: 10) {
                Text("Evidence")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))

                if let relevantContent = message.relevantContent, !relevantContent.isEmpty {
                    relevantContentView(relevantContent)
                }

                if let relatedData = message.relatedData, !relatedData.isEmpty {
                    // Filter out locations as they're not accurate
                    let filteredData = relatedData.filter { $0.type != .location }
                    let groupedData = Dictionary(grouping: filteredData) { $0.type }

                    ForEach(Array(groupedData.keys).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { dataType in
                        if let items = groupedData[dataType], !items.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(iconForDataType(dataType))
                                        .font(FontManager.geist(size: 13, weight: .regular))
                                    Text(labelForDataType(dataType))
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(items.prefix(3)) { item in
                                        DataTypeCardView(
                                            item: item,
                                            colorScheme: colorScheme,
                                            onTap: {
                                                print("\(item.type) tapped: \(item.id)")
                                            }
                                        )
                                    }

                                    if items.count > 3 {
                                        Text("+ \(items.count - 3) more")
                                            .font(FontManager.geist(size: 11, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                                            .padding(.top, 4)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }


    private func iconForDataType(_ type: RelatedDataItem.DataType) -> String {
        switch type {
        case .receipt: return "🧾"
        case .event: return "📅"
        case .note: return "📝"
        case .location: return "📍"
        case .email: return "📧"
        }
    }

    private func labelForDataType(_ type: RelatedDataItem.DataType) -> String {
        switch type {
        case .receipt: return "Receipts"
        case .event: return "Events"
        case .note: return "Notes"
        case .location: return "Locations"
        case .email: return "Emails"
        }
    }

    @ViewBuilder
    private var followUpSuggestionsView: some View {
        if !message.isUser, let suggestions = message.followUpSuggestions, !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(suggestions, id: \.id) { suggestion in
                        suggestionButton(suggestion)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func suggestionButton(_ suggestion: FollowUpSuggestion) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            Task {
                await onSendMessage(suggestion.text)
            }
        }) {
            Text(suggestion.text)
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.2))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Relevant Content Display (Emails, Notes, Events)
    
    @ViewBuilder
    private func relevantContentView(_ content: [RelevantContentInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group by content type for organized display
            // Note: Only show emails - notes/folders/events are excluded per user preference
            let emails = content.filter { $0.contentType == .email }
            
            // Display emails only
            if !emails.isEmpty {
                ForEach(emails) { item in
                    emailCard(item)
                }
            }
        }
    }
    
    private func emailCard(_ item: RelevantContentInfo) -> some View {
        Button(action: {
            // Find the email by ID and open it
            if let emailId = item.emailId {
                // Search in inbox and sent emails
                let allEmails = emailService.inboxEmails + emailService.sentEmails
                if let email = allEmails.first(where: { $0.id == emailId }) {
                    HapticManager.shared.cardTap()
                    selectedEmail = email
                }
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ? Color.blue.opacity(0.2) : Color.blue.opacity(0.12))
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.emailSubject ?? "No Subject")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    HStack(spacing: 4) {
                        Text(item.emailSender ?? "Unknown")
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                            .lineLimit(1)
                        
                        if let date = item.emailDate {
                            Text("•")
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                            Text(formatRelativeDate(date))
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func noteCard(_ item: RelevantContentInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.orange)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.orange.opacity(0.2) : Color.orange.opacity(0.12))
                )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(item.noteTitle ?? "Untitled Note")
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    Text(item.noteFolder ?? "Notes")
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    private func eventCard(_ item: RelevantContentInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.green)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.green.opacity(0.2) : Color.green.opacity(0.12))
                )
            
            VStack(alignment: .leading, spacing: 3) {
                Text(item.eventTitle ?? "Untitled Event")
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if let date = item.eventDate {
                        Text(formatEventDate(date))
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))
                    }
                    
                    if let category = item.eventCategory, !category.isEmpty {
                        Text("•")
                            .font(FontManager.geist(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        Text(category)
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5))
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.3) : .black.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
    
    private func formatEventDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return "Today at \(formatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            formatter.timeStyle = .short
            return "Tomorrow at \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "MMM d 'at' h:mm a"
            return formatter.string(from: date)
        }
    }

    private var messageBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                message.isUser
                    ? (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.045))
                    : .clear
            )
            .shadow(
                color: message.isUser ? Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08) : Color.clear,
                radius: message.isUser ? 6 : 0,
                x: 0,
                y: message.isUser ? 2 : 0
            )
    }

    private var messageBorder: some View {
        Group {
            if message.isUser {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            }
        }
    }
}

// MARK: - Receipt Card Component

struct ReceiptCardView: View {
    let id: UUID
    let merchant: String
    let date: Date?
    let amount: Double?
    let colorScheme: ColorScheme
    let onTap: () -> Void

    @State private var isPressed = false

    private var dateString: String {
        guard let date = date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private var amountString: String {
        guard let amount = amount, amount > 0 else { return "—" }
        return String(format: "$%.2f", amount)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Receipt icon
            Image(systemName: "receipt.fill")
                .font(FontManager.geist(size: 16, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            colorScheme == .dark
                                ? Color.blue.opacity(0.15)
                                : Color.blue.opacity(0.1)
                        )
                )

            // Receipt details
            VStack(alignment: .leading, spacing: 4) {
                Text(merchant)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .lineLimit(1)

                Text(dateString)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            }

            Spacer()

            // Amount
            Text(amountString)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(isPressed ? 0.1 : 0.05)
                        : Color.black.opacity(isPressed ? 0.08 : 0.03)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(isPressed ? 0.2 : 0.1)
                        : Color.black.opacity(isPressed ? 0.15 : 0.08),
                    lineWidth: 0.5
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.selection()
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.01, perform: {
            HapticManager.shared.light()
        })
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Simple Text with Phone Links

struct SimpleTextWithPhoneLinks: View {
    let text: String
    let colorScheme: ColorScheme

    var body: some View {
        let phoneRegex = try! NSRegularExpression(pattern: "\\b(?:\\+?1[-.]?)?\\(?([0-9]{3})\\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})\\b", options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = phoneRegex.matches(in: text, options: [], range: range)

        if matches.isEmpty {
            Text(text)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .textSelection(.enabled)
                .lineLimit(nil)
        } else {
            let components = createPhoneComponents(text)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                    renderComponent(component)
                }
            }
        }
    }

    private struct PhoneComponent {
        let text: String
        let isPhone: Bool
        let phoneNumber: String?
    }

    private func createPhoneComponents(_ text: String) -> [PhoneComponent] {
        var components: [PhoneComponent] = []
        let phoneRegex = try! NSRegularExpression(pattern: "\\b(?:\\+?1[-.]?)?\\(?([0-9]{3})\\)?[-. ]?([0-9]{3})[-. ]?([0-9]{4})\\b", options: [])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = phoneRegex.matches(in: text, options: [], range: range)

        var lastEnd = 0
        for match in matches {
            if match.range.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                if let beforeString = Range(beforeRange, in: text) {
                    components.append(PhoneComponent(text: String(text[beforeString]), isPhone: false, phoneNumber: nil))
                }
            }
            if let phoneRange = Range(match.range, in: text) {
                let phoneText = String(text[phoneRange])
                let cleanedPhone = phoneText.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
                components.append(PhoneComponent(text: phoneText, isPhone: true, phoneNumber: cleanedPhone))
            }
            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < text.count {
            let afterRange = NSRange(location: lastEnd, length: text.count - lastEnd)
            if let afterString = Range(afterRange, in: text) {
                components.append(PhoneComponent(text: String(text[afterString]), isPhone: false, phoneNumber: nil))
            }
        }

        return components
    }

    @ViewBuilder
    private func renderComponent(_ component: PhoneComponent) -> some View {
        if component.isPhone, let phoneNumber = component.phoneNumber {
            Link(destination: URL(string: "tel:\(phoneNumber)")!) {
                Text(component.text)
                    .font(FontManager.geist(size: 16, weight: .regular))
                    .foregroundColor(.blue)
                    .underline()
                    .textSelection(.enabled)
            }
        } else {
            Text(component.text)
                .font(FontManager.geist(size: 16, weight: .regular))
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .lineLimit(nil)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Typing Indicator Component

struct TypingIndicatorView: View {
    let colorScheme: ColorScheme
    @State private var animationIndex = 0
    @State private var messageIndex = 0
    @State private var waveTimer: Timer?
    @State private var messageCycleTimer: Timer?

    var thinkingMessages = ["Thinking...", "Analyzing your data...", "Getting insights..."]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                        .frame(width: 6, height: 6)
                        .offset(y: getWaveOffset(for: index))
                        .opacity(0.8 + 0.2 * Double(index == animationIndex ? 1 : 0))
                }
                Spacer()
            }
            .frame(width: 40, height: 12)

            Text(thinkingMessages[messageIndex % thinkingMessages.count])
                .font(FontManager.geist(size: 15, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            waveTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    animationIndex = (animationIndex + 1) % 3
                }
            }
            messageCycleTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                withAnimation {
                    messageIndex = (messageIndex + 1) % thinkingMessages.count
                }
            }
        }
        .onDisappear {
            waveTimer?.invalidate()
            messageCycleTimer?.invalidate()
            waveTimer = nil
            messageCycleTimer = nil
        }
    }

    private func getWaveOffset(for index: Int) -> CGFloat {
        let distance = abs(index - animationIndex)
        if distance == 0 {
            return -4
        } else if distance == 1 {
            return -2
        } else {
            return 0
        }
    }
}

// MARK: - Unified Data Type Card Component

struct DataTypeCardView: View {
    let item: RelatedDataItem
    let colorScheme: ColorScheme
    let onTap: () -> Void

    @State private var isPressed = false

    private var backgroundColor: Color {
        Color.shadcnTileBackground(colorScheme)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(isPressed ? 0.2 : 0.1)
            : Color.black.opacity(isPressed ? 0.15 : 0.08)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Type-specific icon
            typeIcon
                .frame(width: 32, height: 32)
                .background(typeIconBackground)
                .cornerRadius(8)

            // Main content
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Right-side info based on type
            rightInfoView
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            HapticManager.shared.selection()
            onTap()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch item.type {
        case .receipt:
            Image(systemName: "receipt")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

        case .event:
            Image(systemName: "calendar")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

        case .note:
            Image(systemName: "doc.text")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

        case .location:
            Image(systemName: "mappin")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

        case .email:
            Image(systemName: "envelope")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
    }

    @ViewBuilder
    private var typeIconBackground: some View {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.05)
    }

    @ViewBuilder
    private var rightInfoView: some View {
        switch item.type {
        case .receipt:
            if let amount = item.amount {
                Text(String(format: "$%.2f", amount))
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            }

        case .event:
            if let date = item.date {
                Text(formatEventTime(date))
                    .font(FontManager.geist(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
            }

        case .note:
            Image(systemName: "chevron.right")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))

        case .location:
            if let date = item.date {
                Text(formatLocationTime(date))
                    .font(FontManager.geist(size: 10, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
            }

        case .email:
            Image(systemName: "arrow.up.right")
                .font(FontManager.geist(size: 10, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
        }
    }

    private func formatEventTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatLocationTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

// MARK: - Streaming Cursor (ChatGPT-style blinking cursor)

struct StreamingCursor: View {
    let colorScheme: ColorScheme
    @State private var opacity: Double = 0.85

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white : Color.black)
            .frame(width: 2, height: 14)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    opacity = 0.35
                }
            }
    }
}

// MARK: - Wrapping Inline Layout

struct WrappingInlineLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    init(spacing: CGFloat = 0, rowSpacing: CGFloat = 4) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                totalHeight += currentRowHeight + rowSpacing
                usedWidth = max(usedWidth, currentX - spacing)
                currentX = 0
                currentRowHeight = 0
            }

            currentX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }

        totalHeight += currentRowHeight
        usedWidth = max(usedWidth, currentX > 0 ? currentX - spacing : 0)

        let finalWidth = proposal.width ?? usedWidth
        return CGSize(width: finalWidth, height: max(0, totalHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var currentRowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && (x + size.width) > (bounds.minX + maxWidth) {
                x = bounds.minX
                y += currentRowHeight + rowSpacing
                currentRowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
    }
}

// MARK: - Modern Loading Indicator (Clean & Minimal)

struct ModernLoadingIndicator: View {
    let colorScheme: ColorScheme
    @State private var dotScale1: CGFloat = 1.0
    @State private var dotScale2: CGFloat = 1.0
    @State private var dotScale3: CGFloat = 1.0

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Simple animated dots
            HStack(spacing: 4) {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotScale1)

                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotScale2)

                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(dotScale3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Spacer()
        }
        .onAppear {
            // Dot pulse animation (staggered)
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                dotScale1 = 1.3
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    dotScale2 = 1.3
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    dotScale3 = 1.3
                }
            }
        }
    }
}

// MARK: - Aligned Text Editor (Fixes cursor alignment issue)

struct AlignedTextEditor: UIViewRepresentable {
    @Binding var text: String
    let colorScheme: ColorScheme
    let height: CGFloat
    let onFocusChange: (Bool) -> Void
    let onSend: () -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        textView.text = text
        textView.textColor = colorScheme == .dark ? .white : .black
        textView.tintColor = colorScheme == .dark ? UIColor.white.withAlphaComponent(0.8) : UIColor.black.withAlphaComponent(0.8)
        
        textView.contentInset = .zero
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        if #available(iOS 16.0, *) {
            textView.verticalScrollIndicatorInsets = .zero
        } else {
            textView.scrollIndicatorInsets = .zero
        }

        textView.isScrollEnabled = false
        updateTextInsets(for: textView)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        
        textView.textColor = colorScheme == .dark ? .white : .black
        textView.tintColor = colorScheme == .dark ? UIColor.white.withAlphaComponent(0.8) : UIColor.black.withAlphaComponent(0.8)
        textView.layoutIfNeeded()
        updateTextInsets(for: textView)
        textView.textContainer.lineFragmentPadding = 0

        let availableTextHeight = max(36, height - 16)
        textView.isScrollEnabled = textView.contentSize.height > availableTextHeight
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func updateTextInsets(for textView: UITextView) {
        let lineHeight = textView.font?.lineHeight ?? 18
        let isSingleLine = !text.contains("\n") && textView.contentSize.height <= lineHeight * 1.4

        if isSingleLine {
            let verticalInset = max(6, (height - lineHeight) / 2)
            textView.textContainerInset = UIEdgeInsets(top: verticalInset, left: 0, bottom: verticalInset, right: 0)
        } else {
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        }
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: AlignedTextEditor

        init(_ parent: AlignedTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            
            // Auto-scroll to cursor position so user can see what they're typing
            DispatchQueue.main.async {
                let selectedRange = textView.selectedRange
                if selectedRange.location != NSNotFound {
                    textView.scrollRangeToVisible(selectedRange)
                }
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Check if the user pressed return/enter
            if text == "\n" {
                // Trigger send action
                parent.onSend()
                return false // Don't insert the newline
            }
            return true
        }
    }
}


// MARK: - Expense Budget Sheet

struct ExpenseBudgetSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    let expenseName: String
    let existingBudget: ExpenseBudget?
    let onSave: (ExpenseBudget) -> Void

    @State private var name: String
    @State private var limitText: String
    @State private var period: ExpenseBudgetPeriod

    init(expenseName: String, existingBudget: ExpenseBudget?, onSave: @escaping (ExpenseBudget) -> Void) {
        self.expenseName = expenseName
        self.existingBudget = existingBudget
        self.onSave = onSave
        _name = State(initialValue: existingBudget?.name ?? expenseName)
        _limitText = State(initialValue: existingBudget.map { String(format: "%.0f", $0.limit) } ?? "")
        _period = State(initialValue: existingBudget?.period ?? .monthly)
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Budget") {
                    TextField("Expense name", text: $name)
                    TextField("Limit (e.g. 200)", text: $limitText)
                        .keyboardType(.decimalPad)
                    Picker("Period", selection: $period) {
                        ForEach(ExpenseBudgetPeriod.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }

                Section {
                    Button(existingBudget == nil ? "Save Budget" : "Update Budget") {
                        saveBudget()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color.black : Color(UIColor(white: 0.99, alpha: 1)))
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func saveBudget() {
        let cleanedLimit = limitText.replacingOccurrences(of: ",", with: "")
        guard let limit = Double(cleanedLimit), limit > 0 else { return }
        let budget = ExpenseBudgetService.shared.upsertBudget(
            name: name,
            limit: limit,
            period: period
        )
        onSave(budget)
        dismiss()
    }
}

// MARK: - Expense Reminder Sheet

struct ExpenseReminderSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    let expenseName: String
    let existingReminder: ExpenseReminder?
    let onSave: (ExpenseReminder) -> Void

    @State private var frequency: ExpenseReminderFrequency
    @State private var reminderTime: Date

    init(expenseName: String, existingReminder: ExpenseReminder?, onSave: @escaping (ExpenseReminder) -> Void) {
        self.expenseName = expenseName
        self.existingReminder = existingReminder
        self.onSave = onSave
        _frequency = State(initialValue: existingReminder?.frequency ?? .weekly)
        if let existing = existingReminder {
            var components = DateComponents()
            components.hour = existing.hour
            components.minute = existing.minute
            _reminderTime = State(initialValue: Calendar.current.date(from: components) ?? Date())
        } else {
            _reminderTime = State(initialValue: Date())
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Reminder") {
                    Text("Expense: \(expenseName)")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.6))

                    Picker("Frequency", selection: $frequency) {
                        ForEach(ExpenseReminderFrequency.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }

                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }

                Section {
                    Button(existingReminder == nil ? "Save Reminder" : "Update Reminder") {
                        saveReminder()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Color.black : Color(UIColor(white: 0.99, alpha: 1)))
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func saveReminder() {
        let hour = Calendar.current.component(.hour, from: reminderTime)
        let minute = Calendar.current.component(.minute, from: reminderTime)
        Task {
            let reminder = await ExpenseReminderService.shared.upsertReminder(
                expenseName: expenseName,
                frequency: frequency,
                hour: hour,
                minute: minute
            )
            onSave(reminder)
            dismiss()
        }
    }
}


// MARK: - Token Usage Details Sheet
struct TokenUsageDetailsSheet: View {
    @StateObject private var deepSeekService = GeminiService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    private let dailyTokenLimit: Int = 1_500_000 // 1.5M tokens per day (~$0.30/day)
    
    private var dailyTokensRemaining: Int {
        max(0, dailyTokenLimit - deepSeekService.dailyTokensUsed)
    }
    
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Usage Overview
                VStack(spacing: 12) {
                    HStack {
                        Text("Daily Usage")
                            .font(FontManager.geist(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                        Spacer()
                    }
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue)
                                .frame(width: geometry.size.width * (deepSeekService.quotaPercentage / 100.0))
                        }
                    }
                    .frame(height: 8)
                    
                    // Usage stats
                    VStack(spacing: 8) {
                        HStack {
                            Text("Used")
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            Spacer()
                            Text(formatTokenCount(deepSeekService.dailyTokensUsed))
                                .font(FontManager.geist(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        
                        HStack {
                            Text("Remaining")
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            Spacer()
                            Text(formatTokenCount(dailyTokensRemaining))
                                .font(FontManager.geist(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        
                        HStack {
                            Text("Limit")
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                            Spacer()
                            Text(formatTokenCount(dailyTokenLimit))
                                .font(FontManager.geist(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                
                Spacer()
            }
            .padding(20)
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationTitle("Token Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                }
            }
        }
    }
}

// MARK: - Conversation History Sheet (ChatGPT-style minimal sidebar)

struct ConversationHistorySheet: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @State private var searchText = ""

    private var sidebarBackgroundColor: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.99)
    }
    
    let onSelectConversation: (SavedConversation) -> Void
    let onDeleteConversation: (SavedConversation) -> Void
    var onDismiss: (() -> Void)? = nil
    
    private var groupedConversations: [(String, [SavedConversation])] {
        let calendar = Calendar.current
        let now = Date()
        var groups: [(String, [SavedConversation])] = []
        let sorted = searchService.savedConversations.sorted { $0.createdAt > $1.createdAt }
        
        let today = sorted.filter { calendar.isDateInToday($0.createdAt) }
        if !today.isEmpty { groups.append(("Today", today)) }
        
        let yesterday = sorted.filter { calendar.isDateInYesterday($0.createdAt) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }
        
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let last7Days = sorted.filter { $0.createdAt >= weekAgo && !calendar.isDateInToday($0.createdAt) && !calendar.isDateInYesterday($0.createdAt) }
        if !last7Days.isEmpty { groups.append(("Previous 7 days", last7Days)) }
        
        let older = sorted.filter { $0.createdAt < weekAgo }
        if !older.isEmpty { groups.append(("Older", older)) }
        
        return groups
    }

    private var filteredGroupedConversations: [(String, [SavedConversation])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return groupedConversations }

        return groupedConversations.compactMap { section, conversations in
            let filtered = conversations.filter { conversation in
                let title = conversation.title.lowercased()
                let firstUser = conversation.messages.first(where: { $0.isUser })?.text.lowercased() ?? ""
                return title.contains(query) || firstUser.contains(query)
            }
            return filtered.isEmpty ? nil : (section, filtered)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            searchBar

            Group {
                if searchService.savedConversations.isEmpty {
                    emptyHistoryView
                } else {
                    conversationListView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(sidebarBackgroundColor)
        }
        .background(sidebarBackgroundColor)
        .onAppear { searchService.loadConversationHistoryLocally() }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = abs(value.translation.height)
                    if horizontal < -60 && vertical < 60 {
                        if let onDismiss = onDismiss { onDismiss() } else { dismiss() }
                    }
                }
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.45))

                TextField("Search chats", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(FontManager.geist(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )

            Button(action: {
                HapticManager.shared.selection()
                searchService.startNewConversation()
                if let onDismiss = onDismiss { onDismiss() } else { dismiss() }
            }) {
                Image(systemName: "square.and.pencil")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(sidebarBackgroundColor)
    }

    private var isShowingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasAnyVisibleConversations: Bool {
        !filteredGroupedConversations.isEmpty
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 8) {
            Text("No chats found")
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
            Text("Try another search term")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.45))
        }
    }
    
    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.25) : .black.opacity(0.2))
            Text("No conversations yet")
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5))
            Text("Start a new chat and it will appear here")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var conversationListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(filteredGroupedConversations, id: \.0) { sectionTitle, conversations in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sectionTitle)
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                            .textCase(.uppercase)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 6)
                        
                        ForEach(conversations) { conversation in
                            ConversationHistoryRow(conversation: conversation)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticManager.shared.selection()
                                onSelectConversation(conversation)
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    HapticManager.shared.delete()
                                    onDeleteConversation(conversation)
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .overlay {
            if isShowingSearchResults && !hasAnyVisibleConversations {
                noSearchResultsView
            }
        }
    }
}

struct ConversationHistoryRow: View {
    let conversation: SavedConversation
    @Environment(\.colorScheme) var colorScheme
    
    private var displayTitle: String {
        if conversation.title.isEmpty {
            if let firstUserMessage = conversation.messages.first(where: { $0.isUser }) {
                return firstUserMessage.text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return "New chat"
        }
        return conversation.title
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            Text(displayTitle)
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
