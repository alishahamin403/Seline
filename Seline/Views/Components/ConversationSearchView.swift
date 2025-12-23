import SwiftUI
import UIKit

struct ConversationSearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var deepSeekService = DeepSeekService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom: UUID?
    @State private var inputHeight: CGFloat = 44
    @State private var isStreamingResponse = false
    @State private var streamingStartTime: Date?
    @State private var elapsedTimeUpdateTrigger = UUID() // Triggers elapsed time updates
    @State private var generatedFollowUpQuestions: [String] = []
    @State private var isGeneratingFollowUps = false

    var body: some View {
        VStack(spacing: 0) {
            // Removed streaming indicator bar - user doesn't want it
            headerView
            conversationScrollView
            inputAreaView
        }
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
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
            isInputFocused = true

            // Load daily usage stats
            Task {
                await deepSeekService.loadDailyUsage()
            }

            // Set up timer to update elapsed time while streaming
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if isStreamingResponse {
                    elapsedTimeUpdateTrigger = UUID()
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
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 40)

                // Modern greeting section with icon badge
                VStack(spacing: 16) {
                    // Icon badge
                    ZStack {
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                            .frame(width: 64, height: 64)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.8))
                    }
                    
                    VStack(spacing: 8) {
                        Text(userFirstName.isEmpty ? greetingText : "\(greetingText), \(userFirstName)")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)

                        Text("How can I help you today?")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.65))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)

                // Only show default suggestions when input is empty
                // When typing, suggestions appear above input box instead
                if messageText.isEmpty {
                    defaultSuggestionsView
                        .padding(.horizontal, 12)
                        .padding(.bottom, 32)
                }

                Spacer()
                    .frame(height: 100)
            }
        }
        .scrollDismissesKeyboard(.interactively)
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
    
    private var userFirstName: String {
        if let fullName = authManager.currentUser?.profile?.name {
            let components = fullName.components(separatedBy: " ")
            return components.first ?? fullName
        }
        return ""
    }
    
    private var defaultSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Modern card-based suggestions
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                suggestionChip(icon: "chart.line.uptrend.xyaxis", title: "Spending", color: colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
                suggestionChip(icon: "calendar", title: "Schedule", color: colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
                suggestionChip(icon: "note.text", title: "Notes", color: colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
                suggestionChip(icon: "mappin.circle", title: "Locations", color: colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    colorScheme == .dark 
                        ? Color.white.opacity(0.08)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .shadow(
            color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.04),
            radius: 20,
            x: 0,
            y: 4
        )
    }
    
    private var contextualSuggestionsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggestions")
                .font(.system(size: 12, weight: .medium))
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
                                .font(.system(size: 14, weight: .medium))
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
    
    private func suggestionChip(icon: String, title: String, color: Color) -> some View {
        Button(action: {
            HapticManager.shared.light()
            // Set contextual message based on category
            switch title {
            case "Spending":
                messageText = "Show me my spending analysis"
            case "Schedule":
                messageText = "What's on my calendar?"
            case "Notes":
                messageText = "Show me my recent notes"
            case "Locations":
                messageText = "Where have I been recently?"
            default:
                break
            }
            isInputFocused = true
        }) {
            VStack(spacing: 10) {
                // Icon with colored background
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        colorScheme == .dark 
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.05),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
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
                    .font(.system(size: 20))
                
                Text(prompt)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : Color(white: 0.2))
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18, weight: .medium))
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
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))

                        Spacer()

                        if let startTime = streamingStartTime {
                            Text(formatElapsedTime(since: startTime))
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.red)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
        }
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        .transition(.opacity)
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 12) {
            // Token usage stats on the left (replacing "New Conversation" text)
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10, weight: .medium))
                Text(deepSeekService.dailyUsageString)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
            )

            Spacer()

            // Modern close button - circular with subtle background
            Button(action: {
                HapticManager.shared.selection()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            // Gradient fade background that blends with content
            colorScheme == .dark ? Color.gmailDarkBackground : Color.white
        )
    }

    private var conversationScrollView: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    if searchService.conversationHistory.isEmpty {
                        // Empty state
                        emptyStateView
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(searchService.conversationHistory) { message in
                                ConversationMessageView(
                                    message: message,
                                    onSendMessage: { text in
                                        await searchService.addConversationMessage(text)
                                    },
                                    onRegenerate: { messageId in
                                        await searchService.regenerateResponse(for: messageId)
                                    }
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
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
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
                                .font(.system(size: 10, weight: .medium))
                            Text(question)
                                .font(.system(size: 13, weight: .medium))
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
                                .font(.system(size: 10, weight: .medium))
                            Text(suggestion)
                                .font(.system(size: 13, weight: .medium))
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
        .frame(height: inputHeight)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    colorScheme == .dark 
                        ? (isInputFocused ? Color(white: 0.12) : Color(white: 0.08))
                        : (isInputFocused ? Color.white : Color(white: 0.96))
                )
        )
        .overlay(inputBoxBorder)
        .shadow(
            color: isInputFocused
                ? (colorScheme == .dark ? Color.blue.opacity(0.15) : Color.blue.opacity(0.08))
                : (colorScheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.06)),
            radius: isInputFocused ? 12 : 6,
            x: 0,
            y: isInputFocused ? 4 : 2
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isInputFocused)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: inputHeight)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var inputTextEditor: some View {
        ZStack(alignment: .leading) {
            // Modern placeholder with better styling - perfectly aligned
            if messageText.isEmpty {
                HStack {
                    Text(searchService.conversationHistory.isEmpty ? "Ask me anything..." : "Ask a follow-up question...")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: inputHeight - 24, alignment: .center)
                .allowsHitTesting(false)
            }

            AlignedTextEditor(
                text: $messageText,
                colorScheme: colorScheme,
                height: inputHeight - 24,
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
            .onAppear {
                updateInputHeight()
            }
        }
    }

    private func updateInputHeight() {
        let size = CGSize(width: UIScreen.main.bounds.width - 80, height: .infinity)
        let estimatedHeight = messageText.boundingRect(
            with: size,
            options: .usesLineFragmentOrigin,
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .regular)],
            context: nil
        ).height + 20

        let maxHeight: CGFloat = 200  // Increased to show 4-5 lines
        let minHeight: CGFloat = 44
        inputHeight = min(max(estimatedHeight, minHeight), maxHeight)
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        HapticManager.shared.medium()
        let query = messageText
        messageText = ""
        updateInputHeight()
        isInputFocused = false // Dismiss keyboard
        Task {
            await searchService.addConversationMessage(query)
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
            Image(systemName: (searchService.isLoadingQuestionResponse || isStreamingResponse) ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(
                    (searchService.isLoadingQuestionResponse || isStreamingResponse) 
                        ? .red 
                        : (messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : (colorScheme == .dark ? Color.white : Color.black))
                )
                .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(searchService.isLoadingQuestionResponse || isStreamingResponse) ? 0.5 : 1.0)
                .scaleEffect(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(searchService.isLoadingQuestionResponse || isStreamingResponse) ? 0.9 : 1.0, anchor: .center)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(searchService.isLoadingQuestionResponse || isStreamingResponse))
        .animation(.easeInOut(duration: 0.15), value: messageText)
        .animation(.easeInOut(duration: 0.15), value: searchService.isLoadingQuestionResponse)
        .animation(.easeInOut(duration: 0.15), value: isStreamingResponse)
        .padding(.trailing, 12)
        .padding(.bottom, 2)
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

}

struct ConversationMessageView: View {
    let message: ConversationMessage
    let onSendMessage: (String) async -> Void
    let onRegenerate: ((UUID) async -> Void)?
    @Environment(\.colorScheme) var colorScheme
    @State private var isLongPressed = false
    @State private var showContextMenu = false
    @StateObject private var searchService = SearchService.shared

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

    var body: some View {
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
                .scaleEffect(isLongPressed ? 0.98 : 1.0, anchor: message.isUser ? .topTrailing : .topLeading)
                .brightness(isLongPressed ? -0.05 : 0)
                .animation(.easeInOut(duration: 0.15), value: isLongPressed)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.4, perform: {
                    HapticManager.shared.medium()
                    showContextMenu = true
                }, onPressingChanged: { isPressing in
                    isLongPressed = isPressing
                })
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

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            messageText
            // relatedDataView  // Removed - user doesn't want to see related items
            followUpSuggestionsView
        }
    }

    private var messageText: some View {
        HStack(alignment: .top, spacing: 2) {
            Group {
                if hasComplexFormatting && !message.isUser {
                    MarkdownText(markdown: message.text, colorScheme: colorScheme)
                } else if !message.isUser {
                    SimpleTextWithPhoneLinks(text: message.text, colorScheme: colorScheme)
                } else {
                    Text(message.text)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(message.isUser ? (colorScheme == .dark ? Color.black : Color.white) : Color.shadcnForeground(colorScheme))
                        .lineLimit(nil)
                }
            }
            .mask(
                // Gradient mask that creates fade effect on streaming text
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
            .animation(.easeOut(duration: 0.2), value: message.text)

            // Removed blinking cursor during streaming
        }
    }

    @ViewBuilder
    private var relatedDataView: some View {
        if !message.isUser, let relatedData = message.relatedData, !relatedData.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Divider().padding(.vertical, 4)

                // Group data by type
                let groupedData = Dictionary(grouping: relatedData) { $0.type }

                // Display each data type group
                ForEach(Array(groupedData.keys).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { dataType in
                    if let items = groupedData[dataType], !items.isEmpty {
                        // Data type header
                        HStack(spacing: 6) {
                            Text(iconForDataType(dataType))
                                .font(.system(size: 14))
                            Text(labelForDataType(dataType))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                        .padding(.top, 4)

                        // Items for this type
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(items.prefix(3)) { item in // Limit to 3 items per type
                                DataTypeCardView(
                                    item: item,
                                    colorScheme: colorScheme,
                                    onTap: {
                                        print("\(item.type) tapped: \(item.id)")
                                    }
                                )
                            }

                            // Show "more" indicator if there are additional items
                            if items.count > 3 {
                                Text("+ \(items.count - 3) more")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                                    .padding(.top, 4)
                            }
                        }
                    }
                }
            }
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
                Text(suggestion.emoji).font(.system(size: 14))
                Text(suggestion.text)
                    .font(.system(size: 12, weight: .regular))
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

    private var messageBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                message.isUser
                    ? (colorScheme == .dark ? Color.white : Color(white: 0.25))
                    : .clear
            )
            .shadow(
                color: message.isUser ? (colorScheme == .dark ? Color.black.opacity(0.1) : Color.black.opacity(0.05)) : Color.clear,
                radius: message.isUser ? 4 : 0,
                x: 0,
                y: message.isUser ? 2 : 0
            )
    }

    private var messageBorder: some View {
        Group {
            if message.isUser {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        colorScheme == .dark ? Color.black.opacity(0.15) : Color.white.opacity(0.2),
                        lineWidth: 0.5
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
                .font(.system(size: 16, weight: .medium))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .lineLimit(1)

                Text(dateString)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            }

            Spacer()

            // Amount
            Text(amountString)
                .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 13, weight: .regular))
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
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.blue)
                    .underline()
                    .textSelection(.enabled)
            }
        } else {
            Text(component.text)
                .font(.system(size: 13, weight: .regular))
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
                .font(.system(size: 13, weight: .regular))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .lineLimit(1)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

        case .event:
            Image(systemName: "calendar")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

        case .note:
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

        case .location:
            Image(systemName: "mappin")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)

        case .email:
            Image(systemName: "envelope")
                .font(.system(size: 16, weight: .semibold))
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            }

        case .event:
            if let date = item.date {
                Text(formatEventTime(date))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
            }

        case .note:
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))

        case .location:
            if let date = item.date {
                Text(formatLocationTime(date))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
            }

        case .email:
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
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
        
        // Critical: Set proper insets to align cursor with text baseline
        // Matching the placeholder padding of 16px horizontal and 11px vertical center alignment
        textView.textContainerInset = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true

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
        // These insets match the placeholder padding exactly for perfect alignment
        textView.textContainerInset = UIEdgeInsets(top: 11, left: 16, bottom: 11, right: 16)
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


#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
