import SwiftUI
import UIKit

// Voice mode state machine for clean coordination
enum VoiceModeState {
    case idle       // Not actively in voice mode
    case listening  // Actively listening for speech
    case processing // LLM is thinking/generating response
    case speaking   // TTS is playing response
}

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
    @StateObject private var speechService = SpeechRecognitionService.shared
    @StateObject private var ttsService = TextToSpeechService.shared
    @StateObject private var emailService = EmailService.shared
    @StateObject private var elevenLabsService = ElevenLabsTTSService.shared
    @State private var selectedEmail: Email? = nil
    @State private var isProcessingResponse = false // Track if LLM is responding
    @State private var isVoiceMode = false // Track if we're in voice/speak mode
    @State private var voiceModeState: VoiceModeState = .idle // State machine for voice mode
    @State private var voiceModeListeningPulse = false // Animation state for listening indicator
    @State private var lastMeaningfulTranscript = ""

    private let voiceDraftScrollId = "voiceDraftScrollId"


    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Removed streaming indicator bar - user doesn't want it
                headerView
                conversationScrollView
                // Show different input area based on mode
                // Voice mode stays until user manually switches back to chat
                if isVoiceMode {
                    voiceModeInputView
                } else {
                    inputAreaView
                }
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
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if isStreamingResponse {
                    elapsedTimeUpdateTrigger = UUID()
                }
            }
            
            // Set up transcription callback
            speechService.onTranscriptionUpdate = { text in
                messageText = text
            }

            // Set up auto-send callback for silence detection
            speechService.onAutoSend = {
                // Only auto-send if not already processing and we have text
                let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !isProcessingResponse && !ttsService.isSpeaking && !trimmed.isEmpty {
                    print("🎙️ Auto-send callback triggered with text: '\(trimmed.prefix(50))...'")
                    sendMessage()
                } else {
                    print("🎙️ Auto-send skipped - isProcessing: \(isProcessingResponse), isSpeaking: \(ttsService.isSpeaking), isEmpty: \(trimmed.isEmpty)")
                }
            }
        }
        .onDisappear {
            // Generate final title and save conversation before clearing
            Task {
                await searchService.generateFinalConversationTitle()

                // Save conversation to Supabase
                await searchService.saveConversationToSupabase()

                // Clear conversation state (which handles saving to local history)
                DispatchQueue.main.async {
                    searchService.isInConversationMode = false
                    searchService.clearConversation()

                    // Reset voice mode
                    isVoiceMode = false

                    // Stop any ongoing speech
                    ttsService.stopSpeaking()
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
        .onChange(of: ttsService.isSpeaking) { speaking in
            // Stop recording when TTS starts to prevent echo
            if speaking && speechService.isRecording {
                speechService.stopRecording()
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingTokenDetails) {
            TokenUsageDetailsSheet()
                .presentationDetents([.height(300)])
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
            .presentationBg()
        }
        .fullScreenCover(item: $selectedEmail) { email in
            NavigationView {
                EmailDetailView(email: email)
            }
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
                    Image(systemName: "stop.circle.fill")
                        .font(FontManager.geist(size: 18, weight: .semibold))
                        .foregroundColor(.red)
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
            // Left side: Token usage pill
            HStack {
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
                
                Spacer()
            }
            
            // Center: Title "Chat" or "Speak"
            Text(isVoiceMode ? "Speak" : "Chat")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.claudeTextDark : Color.claudeTextLight)
            
            // Right side: History button + Mode switch
            HStack(spacing: 8) {
                Spacer()
                
                // History button
                Button(action: {
                    HapticManager.shared.selection()
                    showingHistorySheet = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(FontManager.geist(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.claudeTextDark.opacity(0.8) : Color.claudeTextLight.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
                
                // Mode toggle - text only, no icons
                Button(action: {
                    HapticManager.shared.selection()
                    toggleMode()
                }) {
                    Text(isVoiceMode ? "Chat" : "Speak")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.claudeTextDark : Color.claudeTextLight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
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
    
    private func toggleMode() {
        Task {
            if isVoiceMode {
                await exitVoiceMode()
            } else {
                await enterVoiceMode()
            }
        }
    }

    private func enterVoiceMode() async {
        // Stop TTS if speaking
        if ttsService.isSpeaking {
            ttsService.stopSpeaking()
            isProcessingResponse = false
        }

        // Save conversation history in background (don't block mode switch)
        let historyToSave = searchService.conversationHistory
        if !historyToSave.isEmpty {
            Task.detached(priority: .background) {
                await SearchService.shared.generateFinalConversationTitle()
                await MainActor.run {
                    SearchService.shared.saveConversationToHistory()
                }
            }
        }

        // Clear for voice mode immediately (don't wait for save)
        searchService.conversationHistory = []
        messageText = ""
        isProcessingResponse = false
        isStreamingResponse = false

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isVoiceMode = true
        }

        // Haptic feedback
        HapticManager.shared.light()
        
        // Auto-start listening when entering voice mode
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s delay for animation
            if isVoiceMode && !speechService.isRecording && !isProcessingResponse && !ttsService.isSpeaking {
                print("🎙️ Auto-starting recording on voice mode entry")
                speechService.clearTranscription()
                try? await speechService.startRecording()
            }
        }
    }

    private func exitVoiceMode() async {
        // Stop recording
        speechService.stopRecording()

        if ttsService.isSpeaking {
            ttsService.stopSpeaking()
        }

        // Save speak mode conversation to history in background (don't block mode switch)
        let historyToSave = searchService.conversationHistory
        if !historyToSave.isEmpty {
            Task.detached(priority: .background) {
                await SearchService.shared.generateFinalConversationTitle()
                await MainActor.run {
                    SearchService.shared.saveConversationToHistory()
                }
            }
        }

        // Clear for fresh chat mode immediately (don't wait for save)
        searchService.conversationHistory = []
        messageText = ""
        speechService.clearTranscription()
        isProcessingResponse = false
        isStreamingResponse = false

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isVoiceMode = false
        }

        // Return to idle
        try? await AudioSessionCoordinator.shared.requestMode(.idle)
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
                        VStack(alignment: isVoiceMode ? .center : .leading, spacing: 16) {
                            ForEach(searchService.conversationHistory) { message in
                                ConversationMessageView(
                                    message: message,
                                    onSendMessage: { text in
                                        await searchService.addConversationMessage(text)
                                    },
                                    onRegenerate: { messageId in
                                        await searchService.regenerateResponse(for: messageId)
                                    },
                                    isVoiceMode: isVoiceMode,
                                    selectedEmail: $selectedEmail
                                )
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                            }
                            
                            // Voice mode: show live transcript as an "in-progress" user message in the main body
                            // (not above the microphone). Only show while actively recording.
                            if isVoiceMode && speechService.isRecording && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(messageText)
                                    .font(FontManager.geist(size: 14, weight: .regular))
                                    .italic()
                                    .foregroundColor(Color.gray.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 8)
                                    .id(voiceDraftScrollId)
                                    .transition(.opacity)
                            }

                            // Modern loading indicator
                            if searchService.isLoadingQuestionResponse || isStreamingResponse {
                                ModernLoadingIndicator(colorScheme: colorScheme)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                        .padding(.vertical, 16)
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
                // Auto-scroll while user is speaking (live transcript grows word-by-word)
                .onChange(of: messageText) { _ in
                    guard isVoiceMode else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(voiceDraftScrollId, anchor: .bottom)
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
                    .padding(.horizontal, 12)
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
            HStack(spacing: 8) {
                ForEach(generateFollowUpQuestions(), id: \.self) { question in
                    Button(action: {
                        HapticManager.shared.light()
                        messageText = question
                        sendMessage()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left")
                                .font(FontManager.geist(size: 10, weight: .medium))
                            Text(question)
                                .font(FontManager.geist(size: 13, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.2))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
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
        HStack(spacing: 12) {
            inputTextEditor
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
    
    // MARK: - Voice Mode Input View
    
    private var voiceModeInputView: some View {
        let isDark = colorScheme == .dark
        let isMaleSelected = elevenLabsService.selectedVoiceGender == .male
        let isFemaleSelected = elevenLabsService.selectedVoiceGender == .female

        let selectedTextColor: Color = isDark ? .black : .white
        let unselectedTextColor: Color = isDark ? .white.opacity(0.6) : .black.opacity(0.6)
        let selectedBgColor: Color = isDark ? .white : .black
        let toggleBgColor: Color = isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)

        return HStack(spacing: 16) {
            // Add some left padding to move microphone more to the right
            Spacer()
                .frame(width: 20)
            
            // Tap-and-auto-detect button (smaller, on the left)
            Button(action: {
                // Ignore taps when processing or AI is speaking
                guard !isProcessingResponse && !ttsService.isSpeaking else {
                    print("🎙️ Button tap ignored - system is busy (isProcessing: \(isProcessingResponse), isSpeaking: \(ttsService.isSpeaking))")
                    return
                }

                HapticManager.shared.medium()

                // Only start recording if not already recording
                if !speechService.isRecording {
                    Task {
                        print("🎙️ Starting new recording session")
                        speechService.clearTranscription()
                        messageText = ""
                        try? await speechService.startRecording()
                    }
                }
            }) {
                micButtonContent
            }
            .buttonStyle(PlainButtonStyle())
            .opacity((isProcessingResponse || ttsService.isSpeaking) ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isProcessingResponse)
            .animation(.easeInOut(duration: 0.2), value: ttsService.isSpeaking)
            .onAppear {
                // Start pulse animation
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    voiceModeListeningPulse = true
                }
            }
            .onChange(of: speechService.transcribedText) { newText in
                // Keep messageText in sync with transcription
                if !newText.isEmpty && !isProcessingResponse {
                    messageText = newText
                    updateInputHeight()
                }
            }
            .onDisappear {
                voiceModeListeningPulse = false
                voiceModeState = .idle
            }
            
            Spacer()
            
            // Voice gender toggle (on the right)
            HStack(spacing: 0) {
                Button(action: {
                    HapticManager.shared.selection()
                    elevenLabsService.setVoice(gender: .male)
                }) {
                    Text("Male")
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(isMaleSelected ? selectedTextColor : unselectedTextColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isMaleSelected ? selectedBgColor : Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    HapticManager.shared.selection()
                    elevenLabsService.setVoice(gender: .female)
                }) {
                    Text("Female")
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(isFemaleSelected ? selectedTextColor : unselectedTextColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isFemaleSelected ? selectedBgColor : Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(toggleBgColor)
            )
        }
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onChange(of: isVoiceMode) { newValue in
            if newValue {
                voiceModeState = .listening
            } else {
                voiceModeState = .idle
            }
        }
        .onChange(of: ttsService.isSpeaking) { isSpeaking in
            if isSpeaking {
                // Stop recording when TTS starts to prevent echo
                if speechService.isRecording {
                    print("🎙️ TTS started - stopping recording to prevent echo")
                    speechService.stopRecording()
                }
            } else {
                // TTS finished - reset processing state and auto-start listening in voice mode
                if isVoiceMode {
                    print("🎙️ TTS finished - auto-starting recording for next input")
                    isProcessingResponse = false
                    
                    // Auto-start listening after TTS finishes
                    Task {
                        // Small delay to ensure audio session is ready
                        try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s delay
                        
                        // Only start if still in voice mode and not already recording
                        if isVoiceMode && !speechService.isRecording && !isProcessingResponse && !ttsService.isSpeaking {
                            print("🎙️ Auto-resuming recording after TTS")
                            speechService.clearTranscription()
                            messageText = ""
                            try? await speechService.startRecording()
                        }
                    }
                }
            }
        }
    }
    
    private var micButtonContent: some View {
        let accent = Color.claudeAccent
        let isActive = speechService.isRecording
        let isProcessing = isProcessingResponse || ttsService.isSpeaking
        let isDark = colorScheme == .dark

        // Calculate colors based on state
        let fillColor: Color = {
            if isActive {
                return isDark ? accent.opacity(0.25) : accent.opacity(0.18)
            } else if isProcessing {
                return isDark ? Color.orange.opacity(0.2) : Color.orange.opacity(0.15)
            } else {
                return isDark ? Color.gray.opacity(0.25) : Color.gray.opacity(0.18)
            }
        }()

        let strokeColor: Color = {
            if isActive {
                return accent.opacity(0.6)
            } else if isProcessing {
                return Color.orange.opacity(0.5)
            } else {
                return Color.gray.opacity(0.35)
            }
        }()

        return ZStack {
            // Pulse animation rings - show when actively recording (smaller for horizontal layout)
            if isActive {
                Circle()
                    .stroke(accent.opacity(0.35), lineWidth: 2)
                    .frame(width: 68, height: 68)
                    .scaleEffect(voiceModeListeningPulse ? 1.3 : 1.0)
                    .opacity(voiceModeListeningPulse ? 0 : 0.6)

                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: 1.5)
                    .frame(width: 75, height: 75)
                    .scaleEffect(voiceModeListeningPulse ? 1.4 : 1.0)
                    .opacity(voiceModeListeningPulse ? 0 : 0.4)
            }

            // Main button with state-based styling (smaller size)
            Circle()
                .fill(fillColor)
                .frame(width: 60, height: 60)
                .overlay(
                    Circle()
                        .stroke(strokeColor, lineWidth: 2.5)
                )

            // Icon based on state (smaller size)
            if isProcessing {
                Image(systemName: ttsService.isSpeaking ? "waveform" : "hourglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.orange)
            } else {
                Image(systemName: isActive ? "mic.fill" : "mic")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(isActive ? accent : .gray)
            }
        }
    }

    private var voiceModeStatusText: String {
        // Show clear states with distinct text
        if speechService.isRecording {
            if !messageText.isEmpty {
                return "📝 Listening... (stop when done)"
            } else {
                return "👂 Start speaking..."
            }
        }
        if isProcessingResponse || searchService.isLoadingQuestionResponse || isStreamingResponse {
            return "🤔 Processing..."
        }
        if ttsService.isSpeaking {
            return "💬 Seline is speaking..."
        }
        return "🎤 Ready - tap to speak"
    }

    private var inputTextEditor: some View {
        ZStack(alignment: .leading) {
            // Claude-style placeholder - only show when not focused and text is empty
            if messageText.isEmpty && !isInputFocused {
                HStack {
                    Text(searchService.conversationHistory.isEmpty ? "Chat with Seline" : "Reply to Seline")
                        .font(FontManager.geist(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.claudeTextDark.opacity(0.4) : Color.claudeTextLight.opacity(0.4))
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            AlignedTextEditor(
                text: $messageText,
                colorScheme: colorScheme,
                // Ensure the editor has enough vertical space so text isn't clipped
                height: max(inputHeight - 24, 36),
                onFocusChange: { focused in
                    isInputFocused = focused
                    // Exit voice mode if user manually focuses text editor (without recording)
                    if focused && !speechService.isRecording && isVoiceMode {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isVoiceMode = false
                        }
                    }
                },
                onSend: {
                    sendMessage()
                }
            )
            .onChange(of: messageText) { newValue in
                updateInputHeight()
                // Exit voice mode if user manually types (not from voice transcription)
                if !newValue.isEmpty && !speechService.isRecording && isVoiceMode && isInputFocused {
                    // Check if this is manual typing by checking if it's different from transcribed text
                    if newValue != speechService.transcribedText {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isVoiceMode = false
                        }
                    }
                }
            }
            .onChange(of: speechService.transcribedText) { newText in
                // If user starts speaking while TTS is active or LLM is generating, stop everything.
                // Guard against accidental TTS interruption from tiny/noisy partials.
                let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
                let isMeaningful = trimmed.count >= 3 && trimmed.rangeOfCharacter(from: .letters) != nil
                let isNewEnough = trimmed != lastMeaningfulTranscript
                
                if isMeaningful && isNewEnough && (ttsService.isSpeaking || searchService.isLoadingQuestionResponse || isStreamingResponse) {
                    // Stop TTS
                    ttsService.stopSpeaking()
                    // Stop LLM streaming response
                    searchService.stopCurrentRequest()
                    isStreamingResponse = false
                    isProcessingResponse = false
                    
                    // Provide haptic feedback that we heard the user
                    HapticManager.shared.light()
                }
                
                // Update message text with transcription
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
                // Set up speech recognition callback
                speechService.onTranscriptionUpdate = { text in
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
            attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .regular)],
            context: nil
        ).height + 28

        let maxHeight: CGFloat = 120  // ~3 lines
        let minHeight: CGFloat = 44   // Compact default height
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

        // Clear UI immediately
        messageText = ""
        speechService.clearTranscription()
        updateInputHeight()
        isInputFocused = false

        isProcessingResponse = true

        // Update state machine for voice mode
        if isVoiceMode {
            voiceModeState = .processing
        }

        print("🎙️ Sending message: '\(query.prefix(50))...'")

        Task {
            // Pass voice mode to the service
            await searchService.addConversationMessage(query, isVoiceMode: isVoiceMode)

            // Wait for response to finish streaming
            await waitForResponseToComplete()

            print("🎙️ Response complete, TTS speaking: \(ttsService.isSpeaking)")

            if isVoiceMode {
                // Update state to speaking if TTS is active
                if ttsService.isSpeaking {
                    voiceModeState = .speaking
                } else {
                    // TTS finished - reset state
                    await MainActor.run {
                        isProcessingResponse = false
                        print("🎙️ Ready for next message")
                    }
                }
            } else {
                isProcessingResponse = false
            }
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
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color.claudeTextDark : Color.claudeTextLight)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "arrow.up")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(
                        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
                            ? (colorScheme == .dark ? Color.claudeTextDark.opacity(0.4) : Color.claudeTextLight.opacity(0.4))
                            : (colorScheme == .dark ? Color.claudeTextDark : Color.claudeTextLight)
                    )
            }
        }
        .frame(width: 30, height: 30)
        .background(
            Circle()
                .fill(
                    (searchService.isLoadingQuestionResponse || isStreamingResponse || !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ? (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08))
                        : Color.clear
                )
        )
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
    var isVoiceMode: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @State private var showContextMenu = false
    @StateObject private var searchService = SearchService.shared
    @StateObject private var emailService = EmailService.shared
    @Binding var selectedEmail: Email?
    @State private var showingEventCreationResult = false
    @State private var eventCreationMessage = ""
    @State private var eventCreationIsError = false

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

    var body: some View {
        VStack {
            // In voice mode, center both input and output
            if isVoiceMode {
                messageContent
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = message.text
                            HapticManager.shared.selection()
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
            } else {
                // Chat mode: original layout with bubbles
                HStack {
                    if message.isUser {
                        Spacer()
                    }

                    messageContent
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
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

                            // Regenerate option for assistant messages
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
                .padding(.leading, message.isUser ? 16 : 0)
                .padding(.trailing, 16)
            }
        }
        .alert(isPresented: $showingEventCreationResult) {
            Alert(
                title: Text(eventCreationIsError ? "Error" : "Success"),
                message: Text(eventCreationMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var messageContent: some View {
        VStack(alignment: isVoiceMode ? .center : .leading, spacing: 8) {
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

    private var messageText: some View {
        VStack(alignment: isVoiceMode ? .center : .leading, spacing: 12) {
            ForEach(parseMessageSegments(message.text), id: \.id) { segment in
                switch segment.type {
                case .text(let content):
                    Group {
                        if isVoiceMode {
                            // Voice mode: centered text with different styling for user/assistant
                            // Strip markdown formatting for clean voice display
                            let cleanContent = stripMarkdown(content)
                            if message.isUser {
                                // User: italic, smaller, light gray
                                Text(cleanContent)
                                    .font(FontManager.geist(size: 14, weight: .regular))
                                    .italic()
                                    .foregroundColor(Color.gray.opacity(0.7))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                            } else {
                                // Assistant: white, centered
                                Text(cleanContent)
                                    .font(FontManager.geist(size: 15, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white : Color.black.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                            }
                        } else if hasComplexFormatting && !message.isUser {
                            MarkdownText(markdown: content, colorScheme: colorScheme)
                        } else if !message.isUser {
                            SimpleTextWithPhoneLinks(text: content, colorScheme: colorScheme)
                        } else {
                            Text(content)
                                .font(FontManager.geist(size: 13, weight: .regular))
                                // User bubbles use a neutral translucent background now, so keep text readable in both modes.
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
                                .init(color: .black, location: isStreaming ? 0.85 : 1.0),
                                .init(color: .black.opacity(isStreaming ? 0.4 : 1.0), location: isStreaming ? 0.95 : 1.0),
                                .init(color: .clear, location: 1.0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                case .widget(let type):
                    renderWidget(type)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            
            if isStreaming {
                StreamingCursor(colorScheme: colorScheme)
            }
        }
        .animation(.easeOut(duration: 0.2), value: message.text)
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
        }
    }

    private func parseMessageSegments(_ text: String) -> [MessageSegment] {
        // Find all widget tags
        let pattern = "\\[WIDGET: (.*?)\\]"
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        var segments: [MessageSegment] = []
        var lastIndex = text.startIndex
        
        for match in matches {
            let range = match.range
            guard let rangeInText = Range(range, in: text) else { continue }
            
            // Add preceding text
            if rangeInText.lowerBound > lastIndex {
                let textContent = String(text[lastIndex..<rangeInText.lowerBound])
                if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.init(type: .text(textContent)))
                }
            }
            
            // Add widget
            if let typeRange = Range(match.range(at: 1), in: text) {
                let type = String(text[typeRange])
                segments.append(.init(type: .widget(type)))
            } else {
                // Fallback if capturing group fails (unlikely)
                segments.append(.init(type: .widget("Unknown")))
            }
            
            lastIndex = rangeInText.upperBound
        }
        
        // Remaining text
        if lastIndex < text.endIndex {
             let textContent = String(text[lastIndex...])
             if !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                 segments.append(.init(type: .text(textContent)))
             }
        }
        
        return segments.isEmpty ? [.init(type: .text(text))] : segments
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
            HStack(spacing: 8) {
                Text(suggestion.emoji).font(FontManager.geist(size: 14, weight: .regular))
                Text(suggestion.text)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.2))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
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
                .font(FontManager.geist(size: 13, weight: .regular))
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
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(.blue)
                    .underline()
                    .textSelection(.enabled)
            }
        } else {
            Text(component.text)
                .font(FontManager.geist(size: 13, weight: .regular))
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
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .onAppear {
            // Wave animation for dots
            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    animationIndex = (animationIndex + 1) % 3
                }
            }

            // Cycle through thinking messages
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                withAnimation {
                    messageIndex = (messageIndex + 1) % thinkingMessages.count
                }
            }
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
    @State private var isVisible = true

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
            .frame(width: 2, height: 14)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    isVisible = false
                }
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
        textView.font = UIFont.systemFont(ofSize: 15, weight: .regular)
        textView.textColor = colorScheme == .dark ? .white : .black
        textView.tintColor = colorScheme == .dark ? UIColor.white.withAlphaComponent(0.8) : UIColor.black.withAlphaComponent(0.8)
        
        // Use zero left/right inset because SwiftUI already pads the container.
        // This fixes the cursor starting "a few spaces ahead".
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true

        // Enable scrolling so users can see all text as they type
        textView.isScrollEnabled = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        // Update text if it changed externally
        if textView.text != text {
            textView.text = text
        }
        
        // Update colors if color scheme changed
        textView.textColor = colorScheme == .dark ? .white : .black
        textView.tintColor = colorScheme == .dark ? UIColor.white.withAlphaComponent(0.8) : UIColor.black.withAlphaComponent(0.8)
        
        // Ensure insets are maintained (important for cursor alignment)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
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
    
    private let dailyTokenLimit: Int = 2_000_000 // 2M tokens per day
    
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

// MARK: - Conversation History Sheet

struct ConversationHistorySheet: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    
    @State private var isSelectionMode = false
    @State private var selectedConversationIds: Set<UUID> = []
    @State private var showDeleteAllConfirmation = false
    
    let onSelectConversation: (SavedConversation) -> Void
    let onDeleteConversation: (SavedConversation) -> Void
    
    var body: some View {
        NavigationView {
            Group {
                if searchService.savedConversations.isEmpty {
                    emptyHistoryView
                } else {
                    conversationListView
                }
            }
            .background(colorScheme == .dark ? Color.black : Color(white: 0.98))
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !searchService.savedConversations.isEmpty {
                        if isSelectionMode {
                            Button("Cancel") {
                                isSelectionMode = false
                                selectedConversationIds.removeAll()
                            }
                            .font(FontManager.geist(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                        } else {
                            Menu {
                                Button(action: {
                                    isSelectionMode = true
                                }) {
                                    Label("Select", systemImage: "checkmark.circle")
                                }
                                
                                Button(role: .destructive, action: {
                                    showDeleteAllConfirmation = true
                                }) {
                                    Label("Delete All", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(FontManager.geist(size: 18, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.7))
                            }
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSelectionMode && !selectedConversationIds.isEmpty {
                        Button("Delete (\(selectedConversationIds.count))") {
                            HapticManager.shared.delete()
                            searchService.deleteConversations(withIds: selectedConversationIds)
                            selectedConversationIds.removeAll()
                            isSelectionMode = false
                        }
                        .font(FontManager.geist(size: 14, weight: .semibold))
                        .foregroundColor(.red)
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                        .font(FontManager.geist(size: 16, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                    }
                }
            }
        }
        .onAppear {
            // Load conversation history when sheet appears
            searchService.loadConversationHistoryLocally()
        }
        .alert("Delete All Conversations?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                HapticManager.shared.delete()
                searchService.deleteAllConversations()
            }
        } message: {
            Text("This will permanently delete all \(searchService.savedConversations.count) conversations. This action cannot be undone.")
        }
    }
    
    private var emptyHistoryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
            
            Text("No conversations yet")
                .font(FontManager.geist(size: 17, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))
            
            Text("Your chat history will appear here")
                .font(FontManager.geist(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var conversationListView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(searchService.savedConversations) { conversation in
                    HStack(spacing: 12) {
                        // Selection checkbox (only in selection mode)
                        if isSelectionMode {
                            Image(systemName: selectedConversationIds.contains(conversation.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(selectedConversationIds.contains(conversation.id) 
                                    ? .blue 
                                    : (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)))
                        }
                        
                        ConversationHistoryRow(conversation: conversation)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelectionMode {
                            // Toggle selection
                            if selectedConversationIds.contains(conversation.id) {
                                selectedConversationIds.remove(conversation.id)
                            } else {
                                selectedConversationIds.insert(conversation.id)
                            }
                            HapticManager.shared.selection()
                        } else {
                            HapticManager.shared.selection()
                            onSelectConversation(conversation)
                        }
                    }
                    .contextMenu {
                        if !isSelectionMode {
                            Button(role: .destructive) {
                                HapticManager.shared.delete()
                                onDeleteConversation(conversation)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, isSelectionMode ? 16 : 0)
        }
    }
}

struct ConversationHistoryRow: View {
    let conversation: SavedConversation
    @Environment(\.colorScheme) var colorScheme
    
    private var displayTitle: String {
        if conversation.title.isEmpty {
            // Fallback to first user message
            if let firstUserMessage = conversation.messages.first(where: { $0.isUser }) {
                let words = firstUserMessage.text.split(separator: " ").prefix(6).joined(separator: " ")
                return words + (firstUserMessage.text.split(separator: " ").count > 6 ? "..." : "")
            }
            return "Untitled conversation"
        }
        return conversation.title
    }
    
    private var previewText: String {
        if let firstUserMessage = conversation.messages.first(where: { $0.isUser }) {
            let preview = String(firstUserMessage.text.prefix(80))
            return preview + (firstUserMessage.text.count > 80 ? "..." : "")
        }
        return "No messages"
    }
    
    private var formattedDate: String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(conversation.createdAt) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: conversation.createdAt)
        } else if calendar.isDateInYesterday(conversation.createdAt) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: conversation.createdAt, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: conversation.createdAt)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: conversation.createdAt)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .frame(width: 40, height: 40)
                
                Image(systemName: "bubble.left.fill")
                    .font(FontManager.geist(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayTitle)
                        .font(FontManager.geist(size: 15, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(formattedDate)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                }
                
                Text(previewText)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                    .lineLimit(2)
                
                // Message count
                Text("\(conversation.messages.count) messages")
                    .font(FontManager.geist(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.35))
                    .padding(.top, 2)
            }
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.2))
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.black : Color.white)
    }
}

#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
