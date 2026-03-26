import SwiftUI
import UIKit
import AudioToolbox

struct ConversationSearchView: View {
    var isVisible: Bool = true

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @StateObject private var pageState = ConversationPageState()
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var chatUsageTracker = ChatUsageTracker.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom: UUID?
    @State private var inputHeight: CGFloat = 48
    @State private var measuredInputTextHeight: CGFloat = 24
    @State private var isStreamingResponse = false
    @State private var streamingStartTime: Date?
    @State private var shouldAutoScrollConversation = true
    @State private var showingSettings = false
    @State private var showingHistorySheet = false
    @State private var showingHistorySidebar = false
    @State private var showingTrackerRulesSheet = false
    @State private var showingTrackerActivitySheet = false
    @StateObject private var speechService = SpeechRecognitionService.shared
    @StateObject private var ttsService = TextToSpeechService.shared
    @State private var selectedEmail: Email? = nil
    @State private var selectedNote: Note? = nil
    @State private var selectedTask: TaskItem? = nil
    @State private var selectedLocation: SavedPlace? = nil
    @State private var isProcessingResponse = false // Track if LLM is responding
    @State private var lastMeaningfulTranscript = ""

    private var chatBackgroundColor: Color {
        Color.appBackground(colorScheme)
    }

    private var isAssistantStreamingActive: Bool {
        pageState.isLoadingQuestionResponse || isStreamingResponse
    }

    private var isChatUsageCapped: Bool {
        chatUsageTracker.isLimitReached
    }

    private var isTrackerConversation: Bool {
        pageState.isTrackerConversation
    }

    private var visibleConversationHistory: [ConversationMessage] {
        pageState.conversationHistory.filter { $0.proactiveQuestion == nil }
    }

    private var trackerHeaderTitle: String {
        guard isTrackerConversation else { return "Chat" }
        guard
            let title = pageState.currentTrackerThread?.title.trackerNonEmpty,
            title != "Tracker",
            title != "New Tracker"
        else {
            return "Tracker"
        }
        return title
    }

    var body: some View {
        ZStack {
            AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .centerRight)

            VStack(spacing: 0) {
                headerView
                if isTrackerConversation {
                    trackerPinnedSummaryCard
                }
                conversationScrollView

                if isStreamingResponse || pageState.isLoadingQuestionResponse {
                    streamingIndicatorView
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: isStreamingResponse)
                }

                inputAreaView
            }
        }
        .background(chatBackgroundColor)
        .contentShape(Rectangle())
        .simultaneousGesture(keyboardDismissDragGesture, including: .subviews)
        .onChange(of: pageState.isLoadingQuestionResponse) { newValue in
            if newValue {
                // Started streaming
                isStreamingResponse = true
                streamingStartTime = Date()
                shouldAutoScrollConversation = true
                // Subtle click when LLM starts thinking
                playLoadingStartSound()
            } else {
                // Stopped streaming — play a subtle completion sound + haptic
                isStreamingResponse = false
                streamingStartTime = nil
                shouldAutoScrollConversation = true
                playResponseCompleteSound()
            }
        }
        .onAppear {
            searchService.restoreMostRecentConversationIfNeeded()

            // Don't auto-focus on appear - let user see the greeting first
            // isInputFocused = true

            // Load daily usage stats
            Task {
                await chatUsageTracker.loadDailyUsage()
                
                // Proactive Briefing removed to show EmptyStateView instead

            }

            // Set up transcription callback
            speechService.onTranscriptionUpdate = { text in
                if speechService.shouldIgnoreTranscriptionUpdates { return }
                messageText = text
            }

            // Auto-send on silence disabled (speak mode removed); user sends with button
            speechService.onAutoSend = { }

            if pageState.isLoadingQuestionResponse {
                isStreamingResponse = true
                streamingStartTime = streamingStartTime ?? Date()
            }
        }
        .onChange(of: isVisible) { newValue in
            handleVisibilityChange(newValue)
        }
        .onChange(of: isChatUsageCapped) { newValue in
            if newValue {
                messageText = ""
                speechService.clearTranscription()
                speechService.shouldIgnoreTranscriptionUpdates = true
                if speechService.isRecording {
                    speechService.stopRecording()
                }
                dismissKeyboard()
            } else if !isProcessingResponse {
                speechService.shouldIgnoreTranscriptionUpdates = false
            }
        }
        .onDisappear {
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        .sheet(isPresented: $showingTrackerRulesSheet) {
            TrackerRulesSheet(thread: pageState.currentTrackerThread)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBg()
        }
        .sheet(isPresented: $showingTrackerActivitySheet) {
            TrackerActivitySheet(thread: pageState.currentTrackerThread)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBg()
        }
        .overlay(alignment: .leading) {
            historySidebarOverlay
        }
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

    private func pauseConversationAutoscroll() {
        guard shouldAutoScrollConversation else { return }
        shouldAutoScrollConversation = false
    }

    @MainActor
    private func handleVisibilityChange(_ visible: Bool) {
        if visible {
            searchService.restoreMostRecentConversationIfNeeded()
            if !isProcessingResponse {
                speechService.shouldIgnoreTranscriptionUpdates = false
            }
            if pageState.isLoadingQuestionResponse {
                isStreamingResponse = true
                streamingStartTime = streamingStartTime ?? Date()
            }
            return
        }

        shouldAutoScrollConversation = false
        speechService.stopRecording()
        speechService.shouldIgnoreTranscriptionUpdates = true
        ttsService.stopSpeaking()
        if pageState.isLoadingQuestionResponse {
            searchService.stopCurrentRequest()
            isStreamingResponse = false
            streamingStartTime = nil
        }
        dismissKeyboard()
    }

    private func resumeConversationAutoscroll() {
        shouldAutoScrollConversation = true
        scrollToBottom = UUID()
    }

    private var keyboardDismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onEnded { value in
                let verticalDrag = value.translation.height
                let horizontalDrag = abs(value.translation.width)
                guard verticalDrag > 24, verticalDrag > horizontalDrag else { return }
                dismissKeyboard()
            }
    }

    private func dismissKeyboard() {
        isInputFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func playLoadingStartSound() {}

    private func playResponseCompleteSound() {}

    private func startTrackerRuleEdit() {
        HapticManager.shared.selection()
        messageText = "Update the tracker rules: "
        isInputFocused = true
        scrollToBottom = UUID()
    }

    private func draftUndoLastTrackerChange() {
        HapticManager.shared.selection()
        dismissKeyboard()
        Task {
            await searchService.draftUndoLastTrackerChange()
            scrollToBottom = UUID()
        }
    }

    private func startNewChat() {
        HapticManager.shared.selection()
        searchService.stopCurrentRequest()
        speechService.stopRecording()
        speechService.clearTranscription()
        speechService.shouldIgnoreTranscriptionUpdates = false
        messageText = ""
        lastMeaningfulTranscript = ""
        measuredInputTextHeight = 24
        updateInputHeight(contentHeight: measuredInputTextHeight)
        dismissKeyboard()
        searchService.startNewConversation()
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack {
            Spacer()
            
            // Claude-style centered greeting
            VStack(spacing: 16) {
                // Use the same branded S icon as the bottom tab.
                Image("AITabSIcon")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundColor(
                        colorScheme == .dark
                            ? Color(red: 0.98, green: 0.64, blue: 0.41).opacity(0.95)
                            : Color(red: 0.98, green: 0.64, blue: 0.41)
                    )
                
                // Single line greeting matching Claude's style
                Text(isTrackerConversation ? "Describe what to track" : claudeGreetingText)
                    .font(FontManager.geist(size: 26, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackerPinnedSummaryCard: some View {
        Group {
            if let thread = pageState.currentTrackerThread,
               let state = thread.cachedState {
                TrackerSummaryCard(
                    state: state,
                    colorScheme: colorScheme,
                    canUndo: !state.recentChanges.isEmpty,
                    onShowRules: {
                        showingTrackerRulesSheet = true
                    },
                    onShowActivity: {
                        showingTrackerActivitySheet = true
                    },
                    onEditRules: {
                        startTrackerRuleEdit()
                    },
                    onUndoLastChange: {
                        draftUndoLastTrackerChange()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)
            } else {
                TrackerEmptyHeaderCard(colorScheme: colorScheme)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
        }
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
                        .disabled(isChatUsageCapped)
                        .opacity(isChatUsageCapped ? 0.45 : 1)
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
        .disabled(isChatUsageCapped)
        .opacity(isChatUsageCapped ? 0.45 : 1)
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

    // MARK: - Subviews

    private var streamingIndicatorView: some View {
        VStack(spacing: 0) {
            // Thinking label + progress bar + stop button
            HStack(spacing: 10) {
                // Dynamic contextual label — updates as the agent switches phases
                Text(pageState.chatLoadingStatusLabel)
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.40))
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.25), value: pageState.chatLoadingStatusLabel)

                streamingProgressBar
                    .frame(height: 2)

                // Stop button
                Button(action: {
                    HapticManager.shared.medium()
                    isStreamingResponse = false
                    searchService.stopCurrentRequest()
                }) {
                    ZStack {
                        Circle()
                            .fill((colorScheme == .dark ? Color.white : Color.black))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(chatBackgroundColor)
                            .frame(width: 10, height: 10)
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()
                .background((colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)))
        }
        .background(chatBackgroundColor)
        .transition(.opacity)
    }

    private var streamingProgressBar: some View {
        GeometryReader { geometry in
            SwiftUI.TimelineView(.animation(minimumInterval: 0.12)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate * 2.4
                let normalized = (sin(phase) + 1) / 2
                let widthFactor = 0.28 + (normalized * 0.44)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))

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
                        .frame(width: geometry.size.width * widthFactor)
                }
            }
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack(spacing: 10) {
            Button(action: {
                HapticManager.shared.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    showingHistorySidebar = true
                }
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.appChip(colorScheme))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 42, height: 42)

            Spacer(minLength: 0)

            Text(trackerHeaderTitle)
                .font(FontManager.geist(size: 18, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)

            Color.clear
                .frame(width: 42, height: 42)
        }
        .padding(.horizontal, ShadcnSpacing.screenEdgeHorizontal)
        .padding(.top, -4)
        .padding(.bottom, 10)
    }
    
    private var historySidebarOverlay: some View {
        InteractiveSidebarOverlay(
            isPresented: $showingHistorySidebar,
            canOpen: true,
            sidebarWidth: min(336, UIScreen.main.bounds.width * 0.86),
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
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    if visibleConversationHistory.isEmpty {
                        // Empty state - ensure it's visible
                        emptyStateView
                            .frame(minHeight: UIScreen.main.bounds.height * 0.6)
                            .padding(.top, 60)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(visibleConversationHistory) { message in
                                ConversationMessageView(
                                    message: message,
                                    isStreaming: pageState.isStreaming(message),
                                    isPendingTrackerDraft: pageState.isPendingTrackerDraft(message),
                                    onSendMessage: { text in
                                        await searchService.addConversationMessage(text)
                                    },
                                    onRegenerate: { messageId in
                                        await searchService.regenerateResponse(for: messageId)
                                    },
                                    onApplyTrackerDraft: {
                                        searchService.applyPendingTrackerDraft()
                                    },
                                    onCancelTrackerDraft: {
                                        searchService.cancelPendingTrackerDraft()
                                    },
                                    selectedEmail: $selectedEmail,
                                    selectedNote: $selectedNote,
                                    selectedTask: $selectedTask,
                                    selectedLocation: $selectedLocation
                                )
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .opacity
                                            .combined(with: .scale(scale: 0.96, anchor: .bottom))
                                            .combined(with: .move(edge: .bottom)),
                                        removal: .opacity
                                    ))
                            }

                            // Keep status row visible during the full generation lifecycle.
                            if isAssistantStreamingActive {
                                ModernLoadingIndicator(
                                    colorScheme: colorScheme,
                                    label: pageState.chatLoadingStatusLabel
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .id("assistant-status-row")
                            }
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 88)
                    }
                }
                .selinePrimaryPageScroll()
                .scrollDismissesKeyboard(.interactively)
                // Tap anywhere in the conversation to dismiss keyboard — fires alongside message taps
                .simultaneousGesture(TapGesture().onEnded {
                    if isInputFocused { dismissKeyboard() }
                })
                .drawingGroup()
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
                .onChange(of: pageState.conversationHistory.count) { _ in
                    guard shouldAutoScrollConversation else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if isAssistantStreamingActive {
                            guard !isInputFocused else { return }
                            proxy.scrollTo("assistant-status-row", anchor: .bottom)
                        } else if let lastMessage = visibleConversationHistory.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: isAssistantStreamingActive) { active in
                    guard active, !isInputFocused, shouldAutoScrollConversation else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("assistant-status-row", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to bottom when user returns to LLM chat from another tab
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        guard shouldAutoScrollConversation else { return }
                        if let lastMessage = visibleConversationHistory.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: scrollToBottom) { _ in
                    withAnimation(.easeOut(duration: 0.22)) {
                        if isAssistantStreamingActive {
                            proxy.scrollTo("assistant-status-row", anchor: .bottom)
                        } else if let lastMessage = visibleConversationHistory.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: pageState.lastMessageContentVersion) { _ in
                    guard shouldAutoScrollConversation else { return }
                    // Re-scroll when last message gains event card or sources so they stay visible
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            if isAssistantStreamingActive {
                                guard !isInputFocused else { return }
                                proxy.scrollTo("assistant-status-row", anchor: .bottom)
                            } else if let lastMessage = visibleConversationHistory.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .local)
                        .onChanged { value in
                            guard isAssistantStreamingActive else { return }
                            if value.translation.height < -12 {
                                pauseConversationAutoscroll()
                            }
                        }
                )
            }

            if isAssistantStreamingActive && !shouldAutoScrollConversation {
                Button(action: {
                    HapticManager.shared.light()
                    resumeConversationAutoscroll()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Latest")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .appAmbientCardStyle(
                        colorScheme: colorScheme,
                        variant: .bottomLeading,
                        cornerRadius: 18,
                        highlightStrength: 0.5
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 18)
                .padding(.bottom, 18)
            }
        }
    }
    
    private var inputAreaView: some View {
        VStack(spacing: 0) {
            // Smart suggestions bar above input (only when typing in empty state)
            if isInputFocused && !messageText.isEmpty && visibleConversationHistory.isEmpty && !isChatUsageCapped {
                smartSuggestionsBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            if isChatUsageCapped {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(FontManager.geist(size: 13, weight: .semibold))
                    Text("Daily LLM chat limit reached. New messages unlock tomorrow.")
                        .font(FontManager.geist(size: 12, weight: .medium))
                        .lineLimit(2)
                }
                .foregroundColor(colorScheme == .dark ? Color.orange.opacity(0.92) : Color.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.bottom, 8)
            }

            inputBoxContainer
        }
        .background(chatBackgroundColor)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isInputFocused)
    }

    private var smartSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(generateContextualSuggestions().prefix(3), id: \.self) { suggestion in
                    Button(action: {
                        guard !isChatUsageCapped else { return }
                        HapticManager.shared.light()
                        messageText = suggestion
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(FontManager.geist(size: 10, weight: .medium))
                            Text(suggestion)
                                .font(FontManager.geist(size: 13, weight: .medium))
                        }
                        .foregroundColor((colorScheme == .dark ? Color.white : Color.black))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill((colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
                                .overlay(
                                    Capsule()
                                        .stroke((colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isChatUsageCapped)
                    .opacity(isChatUsageCapped ? 0.45 : 1)
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
        .padding(.vertical, 8)
        .frame(height: inputHeight)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .bottomLeading,
            cornerRadius: 24,
            highlightStrength: 0.55
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    isInputFocused
                        ? (colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.18))
                        : (colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)),
                    lineWidth: isInputFocused ? 1.2 : 0.8
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var inputTextEditor: some View {
        ZStack(alignment: .leading) {
            if messageText.isEmpty && !isInputFocused {
                HStack {
                    Text(
                        isChatUsageCapped
                            ? "Daily chat limit reached for today"
                            : isTrackerConversation
                            ? "Describe rules or add a tracked update"
                            : "Message Seline"
                    )
                        .font(FontManager.geist(size: 14, weight: .regular))
                        .foregroundColor((colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5)))
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            AlignedTextEditor(
                text: $messageText,
                colorScheme: colorScheme,
                height: max(inputHeight - 16, 38),
                onContentHeightChange: { contentHeight in
                    measuredInputTextHeight = contentHeight
                    updateInputHeight(contentHeight: contentHeight)
                },
                onFocusChange: { focused in
                    isInputFocused = focused
                },
                onSwipeDown: {
                    dismissKeyboard()
                }
            )
            .onChange(of: speechService.transcribedText) { newText in
                if speechService.shouldIgnoreTranscriptionUpdates || isChatUsageCapped { return }
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
                    if isMeaningful {
                        lastMeaningfulTranscript = trimmed
                    }
                }
            }
            .onAppear {
                updateInputHeight(contentHeight: measuredInputTextHeight)
                speechService.onTranscriptionUpdate = { text in
                    if speechService.shouldIgnoreTranscriptionUpdates { return }
                    messageText = text
                }
            }
            .disabled(isChatUsageCapped)
        }
    }

    private func updateInputHeight(contentHeight: CGFloat? = nil) {
        let maxHeight: CGFloat = 170
        let minHeight: CGFloat = 48
        let textHeight = max(24, contentHeight ?? measuredInputTextHeight)
        let estimatedHeight = textHeight + 20
        let clamped = min(max(estimatedHeight, minHeight), maxHeight)
        if abs(inputHeight - clamped) > 0.5 {
            inputHeight = clamped
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🎙️ sendMessage called with text: '\(trimmed.prefix(50))...' (isProcessing: \(isProcessingResponse), isSpeaking: \(ttsService.isSpeaking))")

        guard !trimmed.isEmpty else {
            print("🎙️ sendMessage aborted - empty text")
            return
        }

        guard !isChatUsageCapped else {
            print("🎙️ sendMessage aborted - daily chat limit reached")
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
        measuredInputTextHeight = 24
        updateInputHeight(contentHeight: measuredInputTextHeight)
        isInputFocused = true

        isProcessingResponse = true
        shouldAutoScrollConversation = true
        scrollToBottom = UUID()

        Task {
            await searchService.addConversationMessage(query)

            await waitForResponseToComplete()

            isProcessingResponse = false
            // Re-enable transcription updates after a short delay so next voice input works
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            speechService.shouldIgnoreTranscriptionUpdates = isChatUsageCapped
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
            guard !isChatUsageCapped else { return }
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
                        .fill((colorScheme == .dark ? Color.white : Color.black))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(chatBackgroundColor)
                        .frame(width: 12, height: 12)
                }
            } else {
                Image(systemName: "mic.fill")
                    .font(FontManager.geist(size: 17, weight: .medium))
                    .foregroundColor((colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        Circle()
                            .fill((colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)))
                    )
            }
        }
        .frame(width: 36, height: 36)
        .buttonStyle(PlainButtonStyle())
        .disabled(isChatUsageCapped)
        .opacity(isChatUsageCapped ? 0.45 : 1)
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
                        .fill((colorScheme == .dark ? Color.white : Color.black))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(chatBackgroundColor)
                        .frame(width: 12, height: 12)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(
                            isChatUsageCapped
                                ? (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                                : messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                                : (colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.1))
                        )
                    Image(systemName: "arrow.up")
                        .font(FontManager.geist(size: 16, weight: .semibold))
                        .foregroundColor(
                            isChatUsageCapped
                                ? (colorScheme == .dark ? Color.white.opacity(0.32) : Color.black.opacity(0.32))
                                : messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? (colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                : (colorScheme == .dark ? Color.white : Color.black)
                        )
                }
            }
        }
        .frame(width: 36, height: 36)
        .buttonStyle(PlainButtonStyle())
        .disabled((isChatUsageCapped && !(searchService.isLoadingQuestionResponse || isStreamingResponse)) || (messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !(searchService.isLoadingQuestionResponse || isStreamingResponse)))
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
    
}

struct ConversationMessageView: View {
    // Pre-compiled regex for citation parsing — avoids recompiling on every streaming chunk
    private static let citationRegex = try! NSRegularExpression(pattern: "\\[\\s*(\\d+)\\s*\\]")

    private struct MessageRenderCache {
        let version: Int
        let displayedText: String
        let segments: [MessageSegment]
        let hasWidgets: Bool
        let hasInlineCitations: Bool
        let hasComplexFormatting: Bool

        static let empty = MessageRenderCache(
            version: 0,
            displayedText: "",
            segments: [],
            hasWidgets: false,
            hasInlineCitations: false,
            hasComplexFormatting: false
        )
    }

    let message: ConversationMessage
    let isStreaming: Bool
    let isPendingTrackerDraft: Bool
    let onSendMessage: (String) async -> Void
    let onRegenerate: ((UUID) async -> Void)?
    let onApplyTrackerDraft: () -> Void
    let onCancelTrackerDraft: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var showContextMenu = false
    private let emailService = EmailService.shared
    private let mapsService = GoogleMapsService.shared
    private let notesManager = NotesManager.shared
    private let taskManager = TaskManager.shared
    private let locationsManager = LocationsManager.shared
    private let sharedLocationManager = SharedLocationManager.shared
    private let searchService = SearchService.shared
    @Binding var selectedEmail: Email?
    @Binding var selectedNote: Note?
    @Binding var selectedTask: TaskItem?
    @Binding var selectedLocation: SavedPlace?
    @State private var showingEventCreationResult = false
    @State private var eventCreationMessage = ""
    @State private var eventCreationIsError = false
    @State private var renderCache: MessageRenderCache = .empty

    private var messageRenderVersion: Int {
        var hasher = Hasher()
        hasher.combine(message.id)
        hasher.combine(message.isUser)
        hasher.combine(message.text)
        hasher.combine(message.relevantContent?.count ?? 0)
        hasher.combine(message.actionDraft?.status.rawValue ?? "")
        hasher.combine(message.presentation?.eventDraftCard?.count ?? 0)
        hasher.combine(message.presentation?.emailPreviewCard?.emailId ?? "")
        hasher.combine(message.presentation?.livePlaceCard?.selectedPlaceId ?? "")
        return hasher.finalize()
    }

    private var activeRenderCache: MessageRenderCache {
        if renderCache.version == messageRenderVersion {
            return renderCache
        }
        return buildRenderCache()
    }

    private var citedLocationResults: [PlaceSearchResult] {
        savedPlaceResults(from: message.relevantContent ?? [])
    }

    private var shouldShowLocationSnippetMap: Bool {
        guard !message.isUser,
              message.locationInfo == nil,
              message.presentation?.livePlaceCard == nil,
              !citedLocationResults.isEmpty
        else { return false }
        // Only show map when all cited records are location/visit type.
        // Mixed responses (e.g. "describe my day") cite visits alongside
        // receipts, notes, etc. — showing a map there is misleading.
        let content = message.relevantContent ?? []
        let nonLocationCount = content.filter {
            $0.contentType != .visit && $0.contentType != .location
        }.count
        return nonLocationCount == 0
    }

    var body: some View {
        VStack {
            HStack {
                if message.isUser {
                    Spacer()
                }

                messageContent
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, message.isUser ? 18 : 0)
                    .padding(.vertical, message.isUser ? 14 : 4)
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
        .task(id: messageRenderVersion) {
            let nextCache = buildRenderCache()
            await MainActor.run {
                renderCache = nextCache
            }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        let eventDrafts = message.presentation?.eventDraftCard ?? message.actionDraft?.eventDrafts ?? message.eventCreationInfo

        VStack(alignment: .leading, spacing: 8) {
            messageText

            if !message.isUser {
                eventPillsRow
            }
            
            // ETA Map Card - shows when there's location data
            if let locationInfo = message.locationInfo {
                ETAMapCard(locationInfo: locationInfo)
                    .padding(.top, 4)
            }

            if shouldShowLocationSnippetMap {
                VStack(alignment: .leading, spacing: 8) {
                    Text(citedLocationResults.count == 1 ? "Location" : "Locations")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.52))
                        .textCase(.uppercase)
                        .tracking(0.55)

                    SearchResultsMapView(
                        searchResults: citedLocationResults,
                        currentLocation: sharedLocationManager.currentLocation,
                        onResultTap: { result in
                            openSavedPlaceMapResult(result)
                        }
                    )
                }
                .padding(.top, 4)
            }
            
            // Event Creation Card - shows when there's event creation data
            if let events = eventDrafts, !events.isEmpty {
                EventCreationCard(
                    events: events,
                    status: message.actionDraft?.status ?? .pending,
                    onConfirm: { confirmedEvents in
                        Task {
                            if message.actionDraft != nil {
                                await searchService.confirmActionDraft(
                                    for: message.id,
                                    confirmedEvents: confirmedEvents
                                )
                            } else {
                                await createEvents(confirmedEvents)
                            }
                        }
                    },
                    onCancel: {
                        if message.actionDraft != nil {
                            searchService.cancelActionDraft(for: message.id)
                        }
                    }
                )
                .padding(.top, 4)
            }

            if let noteDraft = message.presentation?.noteDraftCard ?? message.actionDraft?.noteDraft {
                NoteDraftCard(
                    draft: noteDraft,
                    status: message.actionDraft?.status ?? .pending,
                    onConfirm: {
                        Task {
                            await searchService.confirmActionDraft(for: message.id)
                        }
                    },
                    onCancel: {
                        searchService.cancelActionDraft(for: message.id)
                    }
                )
                .padding(.top, 4)
            }

            if let emailPreview = message.presentation?.emailPreviewCard ?? message.actionDraft?.emailPreview {
                EmailPreviewCard(
                    preview: emailPreview,
                    onOpenEmail: {
                        openEmailPreview(emailPreview)
                    }
                )
                .padding(.top, 4)
            }

            if let livePlacePreview = message.presentation?.livePlaceCard {
                let canSaveLivePlace = message.actionDraft?.type == .saveLocation
                let livePlaceStatus: AgentActionDraftStatus? = canSaveLivePlace
                    ? (message.actionDraft?.status ?? .pending)
                    : nil

                LivePlacePreviewCard(
                    preview: livePlacePreview,
                    folderName: message.actionDraft?.placeDraft?.folderName,
                    status: livePlaceStatus,
                    showSaveActions: canSaveLivePlace,
                    onOpenPlace: { result in
                        openLivePlacePreview(result)
                    },
                    onConfirmSave: { folder in
                        Task {
                            await searchService.confirmActionDraft(for: message.id, folderName: folder)
                        }
                    },
                    onCancel: {
                        searchService.cancelActionDraft(for: message.id)
                    }
                )
                .padding(.top, 4)
            }
            
            if let draft = message.trackerOperationDraft {
                TrackerDraftCard(
                    draft: draft,
                    colorScheme: colorScheme,
                    isPending: isPendingTrackerDraft,
                    onConfirm: onApplyTrackerDraft,
                    onCancel: onCancelTrackerDraft
                )
                .padding(.top, 4)
            }

            if let trackerStateSnapshot = message.trackerStateSnapshot, !message.isUser {
                TrackerInlineStateCard(
                    state: trackerStateSnapshot,
                    colorScheme: colorScheme
                )
                .padding(.top, 4)
            }

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
    private var eventPillsRow: some View {
        let eventPills: [EventCreationInfo] = message.presentation?.eventDraftCard ?? message.actionDraft?.eventDrafts ?? message.eventCreationInfo ?? []
        if eventPills.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Event drafts")
                    .font(FontManager.geist(size: 10, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45))
                    .textCase(.uppercase)
                    .tracking(0.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(eventPills) { event in
                            sourcePill(sourceLabel: "Calendar", title: event.title, icon: "calendar") {
                                // Event creation items don't have a TaskItem yet
                            }
                        }
                    }
                }
            }
            .padding(.top, 6)
        }
    }

    private func openEmailPreview(_ preview: EmailPreviewInfo) {
        HapticManager.shared.cardTap()
        let allEmails = emailService.inboxEmails + emailService.sentEmails
        if let email = allEmails.first(where: { $0.id == preview.emailId }) {
            selectedEmail = email
        }
    }

    private func openLivePlacePreview(_ result: PlaceSearchResult) {
        HapticManager.shared.cardTap()

        if let existingPlace = locationsManager.savedPlaces.first(where: { $0.googlePlaceId == result.id }) {
            selectedLocation = existingPlace
            return
        }

        Task {
            let place = await hydratedLivePlace(result)
            await MainActor.run {
                selectedLocation = place
            }
        }
    }

    private func hydratedLivePlace(_ result: PlaceSearchResult) async -> SavedPlace {
        if !result.id.hasPrefix("mapkit:"),
           let details = try? await mapsService.getPlaceDetails(placeId: result.id) {
            var place = details.toSavedPlace(googlePlaceId: result.id)
            place.category = livePlaceCategory(for: result)
            return place
        }

        var fallbackPlace = SavedPlace(
            googlePlaceId: result.id,
            name: result.name,
            address: result.address,
            latitude: result.latitude,
            longitude: result.longitude,
            photos: result.photoURL.map { [$0] } ?? []
        )
        fallbackPlace.category = livePlaceCategory(for: result)
        return fallbackPlace
    }

    private func livePlaceCategory(for result: PlaceSearchResult) -> String {
        if result.types.contains("current_location") {
            return "Current Location"
        }

        if let firstType = result.types.first, !firstType.isEmpty {
            return firstType
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }

        let loweredName = result.name.lowercased()
        if loweredName.contains("clinic") {
            return "Clinic"
        }
        if loweredName.contains("hospital") {
            return "Hospital"
        }
        if loweredName.contains("pharmacy") {
            return "Pharmacy"
        }

        return "Nearby Place"
    }

    private func sourceLabelForContentType(_ item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .email: return "Email"
        case .note:
            let folder = (item.noteFolder ?? "").lowercased()
            if folder.contains("receipt") { return "Receipt" }
            if folder.contains("weekly summary") || folder.contains("weekly recap") { return "Weekly Summary" }
            if folder.contains("journal") { return "Journal" }
            return "Note"
        case .receipt: return "Receipt"
        case .event: return "Calendar"
        case .location: return "Place"
        case .visit: return "Visit"
        case .person: return "Person"
        }
    }

    private func displayTitle(for item: RelevantContentInfo) -> String {
        switch item.contentType {
        case .email: return item.emailSubject ?? "Email"
        case .note: return item.noteTitle ?? "Note"
        case .receipt: return item.receiptTitle ?? item.noteTitle ?? "Receipt"
        case .event: return item.eventTitle ?? "Event"
        case .location: return item.locationName ?? "Place"
        case .visit: return item.visitPlaceName ?? item.locationName ?? "Visit"
        case .person: return item.personName ?? "Person"
        }
    }

    private func inlineSourceLabel(for item: RelevantContentInfo) -> String {
        let rawLabel: String
        switch item.contentType {
        case .email:
            rawLabel = item.emailSubject ?? item.emailSender ?? "Email"
        case .note:
            rawLabel = item.noteTitle ?? "Note"
        case .receipt:
            rawLabel = item.receiptTitle ?? item.noteTitle ?? "Receipt"
        case .event:
            rawLabel = item.eventTitle ?? "Event"
        case .location:
            rawLabel = item.locationName ?? "Place"
        case .visit:
            rawLabel = item.visitPlaceName ?? item.locationName ?? "Visit"
        case .person:
            rawLabel = item.personName ?? "Person"
        }

        let cleaned = rawLabel
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !cleaned.isEmpty else {
            return sourceLabelForContentType(item)
        }

        if cleaned.count <= 32 {
            return cleaned
        }

        let truncated = String(cleaned.prefix(29)).trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(truncated)..."
    }

    private func iconForContentType(_ type: RelevantContentInfo.ContentType) -> String {
        switch type {
        case .email: return "envelope"
        case .note: return "note.text"
        case .receipt: return "creditcard"
        case .event: return "calendar"
        case .location: return "mappin"
        case .visit: return "location.viewfinder"
        case .person: return "person"
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
        case .receipt:
            if let id = item.receiptId ?? item.noteId,
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
        case .visit:
            if let id = item.visitPlaceId ?? item.locationId,
               let place = locationsManager.savedPlaces.first(where: { $0.id == id }) {
                selectedLocation = place
            } else if let placeName = item.visitPlaceName ?? item.locationName,
                      let place = locationsManager.savedPlaces.first(where: { $0.displayName.caseInsensitiveCompare(placeName) == .orderedSame }) {
                selectedLocation = place
            }
        case .person:
            break
        }
    }

    private func savedPlaceResults(from content: [RelevantContentInfo]) -> [PlaceSearchResult] {
        var seenPlaceIds = Set<UUID>()
        var results: [PlaceSearchResult] = []

        for item in content {
            guard let place = savedPlace(from: item) else { continue }
            guard seenPlaceIds.insert(place.id).inserted else { continue }

            results.append(
                PlaceSearchResult(
                    id: place.id.uuidString,
                    name: place.displayName,
                    address: place.address,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    types: [place.category, place.userCuisine ?? ""].filter { !$0.isEmpty },
                    photoURL: place.photos.first,
                    isSaved: true
                )
            )
        }

        return results
    }

    private func savedPlace(from item: RelevantContentInfo) -> SavedPlace? {
        if let placeId = item.visitPlaceId ?? item.locationId,
           let place = locationsManager.savedPlaces.first(where: { $0.id == placeId }) {
            return place
        }

        let candidateName = item.visitPlaceName ?? item.locationName
        if let candidateName,
           let place = locationsManager.savedPlaces.first(where: { $0.displayName.caseInsensitiveCompare(candidateName) == .orderedSame }) {
            return place
        }

        return nil
    }

    private func openSavedPlaceMapResult(_ result: PlaceSearchResult) {
        HapticManager.shared.cardTap()

        if let uuid = UUID(uuidString: result.id),
           let place = locationsManager.savedPlaces.first(where: { $0.id == uuid }) {
            selectedLocation = place
            return
        }

        if let place = locationsManager.savedPlaces.first(where: {
            $0.displayName.caseInsensitiveCompare(result.name) == .orderedSame
                || $0.address.caseInsensitiveCompare(result.address) == .orderedSame
        }) {
            selectedLocation = place
        }
    }

    /// Inline source pill (no icon): text-only, horizontal, where [[0]] appears in the message. Tappable to open the item.
    private func inlineSourcePill(citationIndex index: Int) -> some View {
        let content = message.relevantContent ?? []
        guard index >= 0, index < content.count else { return AnyView(EmptyView()) }
        let item = content[index]
        let label = inlineSourceLabel(for: item)
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
        let renderCache = activeRenderCache

        return VStack(alignment: .leading, spacing: 12) {
            if !message.isUser && !renderCache.hasWidgets {
                if renderCache.hasInlineCitations {
                    inlineCitationTextContent(segments: renderCache.segments)
                } else {
                    MarkdownText(markdown: renderCache.displayedText, colorScheme: colorScheme)
                }
            } else {
                ForEach(Array(renderCache.segments.enumerated()), id: \.offset) { _, segment in
                    segmentView(segment, hasComplexFormatting: renderCache.hasComplexFormatting)
                }
            }

            if isStreaming {
                StreamingCursor(colorScheme: colorScheme)
            }
        }
        .animation(.easeOut(duration: 0.12), value: renderCache.displayedText)
    }

    @ViewBuilder
    private func segmentView(_ segment: MessageSegment, hasComplexFormatting: Bool) -> some View {
        switch segment.type {
        case .text(let content):
            Group {
                if hasComplexFormatting && !message.isUser {
                    MarkdownText(markdown: content, colorScheme: colorScheme)
                } else if !message.isUser {
                    SimpleTextWithPhoneLinks(text: content, colorScheme: colorScheme)
                } else {
                    Text(content)
                        .font(FontManager.geist(size: 15, weight: .regular))
                        .foregroundColor(
                            message.isUser
                                ? (colorScheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.90))
                                : Color.shadcnForeground(colorScheme)
                        )
                        .lineSpacing(3)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .animation(.linear(duration: 0.1), value: content.count)
        case .citation(let index):
            inlineSourcePill(citationIndex: index)
        case .widget(let type):
            renderWidget(type)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private func buildRenderCache() -> MessageRenderCache {
        let remappedText = remappedDisplayedCitationText(message.text)
        let displayedText = sanitizeDisplayedMessageText(remappedText)
        let hasComplexFormatting = displayedText.contains("**")
            || displayedText.contains("*")
            || displayedText.contains("`")
            || displayedText.contains("- ")
            || displayedText.contains("• ")
            || displayedText.contains("\n")
        let maxCitationIndex = (message.relevantContent?.count ?? 0) - 1
        let segments = parseMessageSegments(displayedText, maxCitationIndex: maxCitationIndex)

        var hasWidgets = false
        var hasInlineCitations = false
        for segment in segments {
            switch segment.type {
            case .widget:
                hasWidgets = true
            case .citation:
                hasInlineCitations = true
            case .text:
                break
            }

            if hasWidgets && hasInlineCitations {
                break
            }
        }

        return MessageRenderCache(
            version: messageRenderVersion,
            displayedText: displayedText,
            segments: segments,
            hasWidgets: hasWidgets,
            hasInlineCitations: hasInlineCitations,
            hasComplexFormatting: hasComplexFormatting
        )
    }

    private func remappedDisplayedCitationText(_ text: String) -> String {
        guard
            let evidenceBundle = message.evidenceBundle,
            let relevantContent = message.relevantContent,
            !relevantContent.isEmpty
        else {
            return text
        }

        let originalIndices = evidenceCitationIndices(
            in: text,
            maxIndex: evidenceBundle.records.count - 1
        )
        guard !originalIndices.isEmpty else {
            return text
        }

        let expectedLocalOrder = Array(0..<min(originalIndices.count, relevantContent.count))
        let alreadyLocal = Array(originalIndices.prefix(expectedLocalOrder.count)) == expectedLocalOrder
        let isOneToOneReceiptStyleProjection = originalIndices.count == relevantContent.count
        if alreadyLocal || !isOneToOneReceiptStyleProjection {
            return text
        }

        var localCitationIndexByEvidenceIndex: [Int: Int] = [:]
        for (localIndex, evidenceIndex) in originalIndices.enumerated() where localIndex < relevantContent.count {
            localCitationIndexByEvidenceIndex[evidenceIndex] = localIndex
        }

        return remapEvidenceCitationMarkers(
            in: text,
            localCitationIndexByEvidenceIndex: localCitationIndexByEvidenceIndex,
            maxEvidenceIndex: evidenceBundle.records.count - 1
        )
    }

    private func sanitizeDisplayedMessageText(_ text: String) -> String {
        let normalized = normalizeCitationMarkers(in: text)
        return normalized
            .components(separatedBy: "\n")
            .map { line in
                let leading = String(line.prefix { $0 == " " || $0 == "\t" })
                let remainder = String(line.dropFirst(leading.count))
                    .replacingOccurrences(of: "[ \t]{2,}", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
                return leading + remainder
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\\s+([,.!?;:])", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func evidenceCitationIndices(in text: String, maxIndex: Int) -> [Int] {
        guard maxIndex >= 0 else { return [] }
        let normalized = normalizeCitationMarkers(in: text)
        let matches = Self.citationRegex.matches(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized))
        var ordered: [Int] = []
        var seen = Set<Int>()

        for match in matches {
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: normalized),
                let value = Int(normalized[range]),
                value >= 0,
                value <= maxIndex,
                seen.insert(value).inserted
            else {
                continue
            }
            ordered.append(value)
        }

        return ordered
    }

    private func remapEvidenceCitationMarkers(
        in text: String,
        localCitationIndexByEvidenceIndex: [Int: Int],
        maxEvidenceIndex: Int
    ) -> String {
        let normalized = normalizeCitationMarkers(in: text)
        guard let regex = try? NSRegularExpression(pattern: "\\[\\s*(\\d+)\\s*\\]") else {
            return normalized
        }

        let mutable = NSMutableString(string: normalized)
        let matches = regex.matches(in: normalized, range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized))

        for match in matches.reversed() {
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: normalized),
                let value = Int(normalized[range]),
                value >= 0,
                value <= maxEvidenceIndex
            else {
                continue
            }

            if let localIndex = localCitationIndexByEvidenceIndex[value] {
                mutable.replaceCharacters(in: match.range, with: "[\(localIndex)]")
            }
        }

        return mutable as String
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
                    let effectiveLevel = effectiveInlineLineLevel(for: index, in: lines)
                    let showBullet = parsed.hasBullet && !heading.consumeBullet
                    let lineLeadingPadding = inlineLineLeadingPadding(
                        showBullet: showBullet,
                        effectiveLevel: effectiveLevel
                    )
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
                                    Text(effectiveLevel == 0 ? "•" : "◦")
                                        .font(FontManager.geist(size: 15, weight: effectiveLevel == 0 ? .bold : .medium))
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
                                                            ? FontManager.geist(size: heading.level == 1 ? 20 : 15, weight: heading.level == 1 ? .bold : .semibold)
                                                            : FontManager.geist(size: 15, weight: .regular)
                                                    )
                                                    .foregroundColor(
                                                        heading.level == 1
                                                            ? (colorScheme == .dark ? .white : .black)
                                                            : heading.level == 2
                                                                ? (colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.9))
                                                                : Color.shadcnForeground(colorScheme)
                                                    )
                                                    .lineSpacing(4)
                                            }
                                        case .citation(let index):
                                            inlineSourcePill(citationIndex: index)
                                        }
                                    }
                                }
                            }
                            .padding(.leading, lineLeadingPadding)
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

    private func effectiveInlineLineLevel(for index: Int, in lines: [[InlineRun]]) -> Int {
        var insideDayBreakdownSection = false
        var lastBulletLevel = 0

        for currentIndex in 0...index {
            let lineRuns = lines[currentIndex]
            if isInlineLineBlank(lineRuns) {
                continue
            }

            let parsed = parseBulletLine(from: lineRuns)
            if parsed.hasBullet {
                if parsed.level > 0 {
                    lastBulletLevel = parsed.level
                } else if isDayBreakdownBullet(parsed.runs) {
                    lastBulletLevel = 0
                    insideDayBreakdownSection = true
                } else if insideDayBreakdownSection {
                    lastBulletLevel = 1
                } else {
                    lastBulletLevel = 0
                    insideDayBreakdownSection = false
                }

                if currentIndex == index {
                    return lastBulletLevel
                }
            } else if currentIndex == index {
                if insideDayBreakdownSection {
                    return max(lastBulletLevel, 1)
                }
                return lastBulletLevel
            }
        }

        return 0
    }

    private func inlineLineLeadingPadding(showBullet: Bool, effectiveLevel: Int) -> CGFloat {
        if showBullet {
            return CGFloat(effectiveLevel) * 18
        }
        if effectiveLevel > 0 {
            return CGFloat(effectiveLevel) * 18 + 22
        }
        return 0
    }

    private func isDayBreakdownBullet(_ runs: [InlineRun]) -> Bool {
        let text = runs.compactMap { run -> String? in
            if case .text(let token) = run { return token }
            return nil
        }.joined()

        let cleaned = cleanInlineMarkdownToken(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^\s*[-*•]\s*"#, with: "", options: .regularExpression)

        let pattern = #"^(monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|yesterday|tomorrow)\b.*:\s*\$?\d"#
        return cleaned.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func cleanInlineMarkdownToken(_ token: String) -> String {
        var cleaned = token
        cleaned = cleaned.replacingOccurrences(of: "^\\s*#{1,6}\\s*", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\*\\*", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "__", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "`", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\\[\\s*\\d+\\s*\\]", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[\\s*(?:evidenceBundle\\.)?aggregates\\.\\d+\\s*\\]", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "\\[\\s*(?:evidenceBundle\\.)?aggregate_rows\\.\\d+\\s*\\]", with: "", options: .regularExpression)
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

    private func parseMessageSegments(_ text: String, maxCitationIndex: Int) -> [MessageSegment] {
        // Normalize mixed citation formats like [[0]], [0], and [[0], [1]] into [0], [1].
        let normalized = normalizeCitationMarkers(in: text)
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

            guard maxCitationIndex >= 0, index >= 0, index <= maxCitationIndex else {
                lastIndex = rangeInText.upperBound
                continue
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

        if segments.isEmpty {
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

    private func normalizeCitationMarkers(in text: String) -> String {
        var normalizedBrackets = text
            .replacingOccurrences(of: "[[", with: "[")
            .replacingOccurrences(of: "]]", with: "]")

        let replacements: [(pattern: String, template: String)] = [
            ("\\[\\s*(?:evidenceBundle\\.)?records\\.(\\d+)\\s*\\]", "[$1]"),
            ("\\[\\s*(?:evidenceBundle\\.)?citations\\.(\\d+)\\s*\\]", "[$1]")
        ]
        for replacement in replacements {
            normalizedBrackets = normalizedBrackets.replacingOccurrences(
                of: replacement.pattern,
                with: replacement.template,
                options: .regularExpression
            )
        }

        let stripPatterns = [
            "\\[\\s*(?:evidenceBundle\\.)?aggregates\\.\\d+\\s*\\]",
            "\\[\\s*(?:evidenceBundle\\.)?aggregate_rows\\.\\d+\\s*\\]"
        ]
        for pattern in stripPatterns {
            normalizedBrackets = normalizedBrackets.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        let groupedCitationRegex = try! NSRegularExpression(pattern: "\\[(\\s*\\d+\\s*(?:,\\s*\\d+\\s*)+)\\]")
        let matches = groupedCitationRegex.matches(
            in: normalizedBrackets,
            range: NSRange(normalizedBrackets.startIndex..., in: normalizedBrackets)
        )

        guard !matches.isEmpty else { return normalizedBrackets }

        let mutable = NSMutableString(string: normalizedBrackets)
        for match in matches.reversed() {
            guard let contentRange = Range(match.range(at: 1), in: normalizedBrackets) else { continue }
            let numbers = normalizedBrackets[contentRange]
                .split(separator: ",")
                .compactMap { part in
                    Int(String(part).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            guard !numbers.isEmpty else {
                mutable.replaceCharacters(in: match.range, with: "")
                continue
            }

            let replacement = numbers
                .map { "[\($0)]" }
                .joined(separator: " ")
            mutable.replaceCharacters(in: match.range, with: replacement)
        }

        return mutable as String
    }

    private func shouldRenderTextSegment(_ text: String) -> Bool {
        let trimmed = text
            .replacingOccurrences(of: "\\[\\s*(?:evidenceBundle\\.)?aggregates\\.\\d+\\s*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[\\s*(?:evidenceBundle\\.)?aggregate_rows\\.\\d+\\s*\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color.primary.opacity(0.2) : Color.primary.opacity(0.12))
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
        RoundedRectangle(cornerRadius: message.isUser ? 26 : 12)
            .fill(
                message.isUser
                    ? (colorScheme == .dark
                        ? Color.white.opacity(0.085)
                        : Color(red: 0.95, green: 0.95, blue: 0.96))
                    : .clear
            )
            .shadow(
                color: message.isUser ? Color.black.opacity(colorScheme == .dark ? 0.18 : 0.05) : Color.clear,
                radius: message.isUser ? 10 : 0,
                x: 0,
                y: message.isUser ? 1 : 0
            )
    }

    private var messageBorder: some View {
        Group {
            if message.isUser {
                RoundedRectangle(cornerRadius: 26)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.05),
                        lineWidth: 0.8
                    )
            }
        }
    }
}

private enum TrackerTheme {
    static func accent(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.98, green: 0.62, blue: 0.34).opacity(0.95)
            : Color(red: 0.89, green: 0.46, blue: 0.16)
    }

    static func pinnedCardGradient(_ colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    accent(colorScheme).opacity(0.14),
                    Color.white.opacity(0.04)
                ]
                : [
                    Color.white.opacity(0.88),
                    accent(colorScheme).opacity(0.10)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func pinnedCardBorder(_ colorScheme: ColorScheme) -> Color {
        accent(colorScheme).opacity(colorScheme == .dark ? 0.24 : 0.16)
    }

    static func pinnedCardShadow(_ colorScheme: ColorScheme) -> Color {
        accent(colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.07)
    }

    static func neutralCardFill(_ colorScheme: ColorScheme) -> Color {
        Color.appSurface(colorScheme)
    }

    static func neutralCardBorder(_ colorScheme: ColorScheme) -> Color {
        Color.appBorder(colorScheme)
    }

    static func subtleFill(_ colorScheme: ColorScheme) -> Color {
        Color.appInnerSurface(colorScheme)
    }

    static func pillFill(_ colorScheme: ColorScheme) -> Color {
        accent(colorScheme).opacity(colorScheme == .dark ? 0.12 : 0.08)
    }

    static func pillBorder(_ colorScheme: ColorScheme) -> Color {
        accent(colorScheme).opacity(colorScheme == .dark ? 0.20 : 0.14)
    }

    static func border(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.orange.opacity(0.22) : Color.orange.opacity(0.16)
    }

    static func bullet(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.orange.opacity(0.72)
            : Color(red: 0.86, green: 0.44, blue: 0.15)
    }
}

private func parsedRuleHighlights(from text: String) -> [String] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed != "No rules saved yet." else { return [] }

    let lineItems = trimmed
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    if lineItems.count > 1 {
        return Array(lineItems.prefix(6))
    }

    let sentenceItems = trimmed
        .split(whereSeparator: { ".!?".contains($0) })
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    return Array(sentenceItems.prefix(6))
}

private func trackerStateHighlights(from state: TrackerDerivedState, limit: Int) -> [String] {
    var highlights: [String] = []
    var seen = Set<String>()

    for fact in extractTrackerSummaryFacts(from: state.currentSummary) {
        let key = fact.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        highlights.append(fact)
        if highlights.count == limit {
            return highlights
        }
    }

    for fact in state.quickFacts.compactMap(cleanTrackerHighlight) {
        let key = fact.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        highlights.append(fact)
        if highlights.count == limit {
            break
        }
    }

    return highlights
}

private func trackerKeyActionHighlights(from state: TrackerDerivedState, limit: Int) -> [String] {
    let highlights = trackerStateHighlights(from: state, limit: max(limit, 6))
    let prioritized = highlights.filter(isTrackerKeyActionHighlight)
    let source = prioritized.isEmpty ? highlights : prioritized
    return Array(source.prefix(limit))
}

private func isTrackerKeyActionHighlight(_ text: String) -> Bool {
    let normalized = text.lowercased()
    let keywords = [
        "left to spend",
        "remaining",
        "remaining budget",
        "remaining to spend",
        "leaving ",
        "left with",
        "available",
        "budget left",
        "can still spend",
        "still spend"
    ]

    return keywords.contains(where: { normalized.contains($0) })
}

private func extractTrackerSummaryFacts(from text: String) -> [String] {
    let normalized = text
        .replacingOccurrences(of: "•", with: "\n")
        .replacingOccurrences(of: "\u{2022}", with: "\n")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !normalized.isEmpty else { return [] }

    let lineCandidates = normalized
        .components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    let sourceSegments = lineCandidates.isEmpty ? [normalized] : lineCandidates
    var facts: [String] = []
    var seen = Set<String>()

    for segment in sourceSegments {
        let sentenceNormalized = segment
            .replacingOccurrences(of: ". ", with: ".\n")
            .replacingOccurrences(of: "? ", with: "?\n")
            .replacingOccurrences(of: "! ", with: "!\n")
            .replacingOccurrences(of: "; ", with: ";\n")
        let sentenceCandidates = sentenceNormalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let clauses = sentenceCandidates.isEmpty ? [segment] : sentenceCandidates
        for clause in clauses {
            let fragments = splitTrackerClauseIfNeeded(clause)
            for fragment in fragments {
                guard let cleaned = cleanTrackerHighlight(fragment) else { continue }
                let dedupeKey = cleaned.lowercased()
                guard !seen.contains(dedupeKey) else { continue }
                seen.insert(dedupeKey)
                facts.append(cleaned)
            }
        }
    }

    return facts
}

private func splitTrackerClauseIfNeeded(_ text: String) -> [String] {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > 72, trimmed.contains(",") else {
        return [trimmed]
    }

    let commaParts = trimmed
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    return commaParts.count > 1 && commaParts.count <= 4 ? commaParts : [trimmed]
}

private func cleanTrackerHighlight(_ text: String) -> String? {
    let cleaned = text
        .replacingOccurrences(of: #"^\s*[-•]\s*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

    return cleaned.isEmpty ? nil : cleaned
}

struct TrackerSummaryCard: View {
    let state: TrackerDerivedState
    let colorScheme: ColorScheme
    let canUndo: Bool
    let onShowRules: () -> Void
    let onShowActivity: () -> Void
    let onEditRules: () -> Void
    let onUndoLastChange: () -> Void
    @State private var isExpanded = false
    @State private var isRulesExpanded = false
    @State private var isRecentExpanded = false

    private var ruleHighlights: [String] {
        let parsedRules = parsedRuleHighlights(from: state.ruleSummary)
        return parsedRules.isEmpty ? Array(state.quickFacts.prefix(4)) : parsedRules
    }

    private var visibleRuleHighlights: [String] {
        Array(ruleHighlights.prefix(isRulesExpanded ? 6 : 2))
    }

    private var visibleRecentChanges: [TrackerChange] {
        Array(state.recentChanges.prefix(isRecentExpanded ? 6 : 2))
    }

    private var latestStateHighlights: [String] {
        trackerKeyActionHighlights(from: state, limit: isExpanded ? 4 : 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    actionPill(icon: "doc.text", text: "Rules", action: onShowRules)
                    actionPill(icon: "clock.arrow.circlepath", text: "Activity", action: onShowActivity)
                    actionPill(icon: "slider.horizontal.3", text: "Edit Rules", action: onEditRules)
                    actionPill(
                        icon: "arrow.uturn.backward",
                        text: "Undo Last",
                        isEnabled: canUndo,
                        action: onUndoLastChange
                    )
                    iconActionPill(systemName: isExpanded ? "chevron.up" : "chevron.down") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                currentStateSection

                if isExpanded, !ruleHighlights.isEmpty {
                    disclosureSection(
                        title: "Key Rules",
                        count: ruleHighlights.count,
                        isExpanded: isRulesExpanded,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRulesExpanded.toggle()
                            }
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(visibleRuleHighlights, id: \.self) { rule in
                                bulletRow(rule)
                            }
                        }
                    }
                }

                if isExpanded, !state.recentChanges.isEmpty {
                    disclosureSection(
                        title: "Recent Changes",
                        count: state.recentChanges.count,
                        isExpanded: isRecentExpanded,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isRecentExpanded.toggle()
                            }
                        }
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(visibleRecentChanges) { change in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(change.title?.trackerNonEmpty ?? change.content)
                                        .font(FontManager.geist(size: 13, weight: .medium))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .lineLimit(2)
                                    Text(compactTrackerDate(change.effectiveAt))
                                        .font(FontManager.geist(size: 11, weight: .regular))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45))
                                }
                            }
                        }
                    }
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(TrackerTheme.pinnedCardGradient(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(TrackerTheme.pinnedCardBorder(colorScheme), lineWidth: 1)
        )
        .shadow(color: TrackerTheme.pinnedCardShadow(colorScheme), radius: 18, x: 0, y: 10)
    }

    private var currentStateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if latestStateHighlights.isEmpty {
                Text(state.summaryLine)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.78) : Color.black.opacity(0.74))
                    .lineLimit(isExpanded ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(latestStateHighlights, id: \.self) { highlight in
                        bulletRow(highlight)
                    }
                }
            }
        }
    }

    private func actionPill(
        icon: String,
        text: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(text)
                    .font(FontManager.geist(size: 11, weight: .medium))
            }
            .foregroundColor(isEnabled ? Color.appTextPrimary(colorScheme) : (colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.28)))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(TrackerTheme.pillFill(colorScheme))
            )
            .overlay(
                Capsule()
                    .stroke(TrackerTheme.pillBorder(colorScheme), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.65)
    }

    private func iconActionPill(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(TrackerTheme.accent(colorScheme))
                .frame(width: 28, height: 28)
                .background(
                    Capsule()
                        .fill(TrackerTheme.pillFill(colorScheme))
                )
                .overlay(
                    Capsule()
                        .stroke(TrackerTheme.pillBorder(colorScheme), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
    }

    private func disclosureSection<Content: View>(
        title: String,
        count: Int,
        isExpanded: Bool,
        onToggle: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack {
                    Text(title)
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.5))
                        .textCase(.uppercase)

                    Spacer()

                    Text("\(count)")
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(TrackerTheme.accent(colorScheme))

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TrackerTheme.accent(colorScheme))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
            }
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(TrackerTheme.bullet(colorScheme))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))
        }
    }

    private func compactTrackerDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct TrackerEmptyHeaderCard: View {
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tracker mode")
                .font(FontManager.geist(size: 15, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
            Text("Describe what should be tracked and the rules in plain language. I will draft the tracker, show the saved rules and summary, and wait for confirmation before saving anything.")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.68) : Color.black.opacity(0.6))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(TrackerTheme.pinnedCardGradient(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(TrackerTheme.pinnedCardBorder(colorScheme), lineWidth: 1)
        )
        .shadow(color: TrackerTheme.pinnedCardShadow(colorScheme), radius: 18, x: 0, y: 10)
    }
}

struct TrackerRulesSheet: View {
    let thread: TrackerThread?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let thread {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(thread.title)
                                .font(FontManager.geist(size: 20, weight: .semibold))
                                .foregroundColor(Color.appTextPrimary(colorScheme))
                            Text(thread.cachedState?.ruleSummary ?? TrackerRuleSummaryBuilder.summary(for: thread.memorySnapshot))
                                .font(FontManager.geist(size: 14, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.76) : Color.black.opacity(0.7))

                            if !thread.memorySnapshot.quickFacts.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Key Points")
                                        .font(FontManager.geist(size: 12, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.5))
                                    ForEach(thread.memorySnapshot.quickFacts, id: \.self) { fact in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(TrackerTheme.bullet(colorScheme))
                                                .frame(width: 5, height: 5)
                                                .padding(.top, 6)
                                            Text(fact)
                                                .font(FontManager.geist(size: 13, weight: .regular))
                                                .foregroundColor(Color.appTextPrimary(colorScheme))
                                        }
                                    }
                                }
                            }

                            if let notes = thread.memorySnapshot.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !notes.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Notes")
                                        .font(FontManager.geist(size: 12, weight: .semibold))
                                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.5))
                                    Text(notes)
                                        .font(FontManager.geist(size: 13, weight: .regular))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                }
                            }
                        }
                    } else {
                        Text("No tracker rules yet.")
                            .font(FontManager.geist(size: 15, weight: .medium))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground(colorScheme))
            .navigationTitle("Tracker Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TrackerActivitySheet: View {
    let thread: TrackerThread?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var sortedChanges: [TrackerChange] {
        guard let thread else { return [] }
        return thread.memorySnapshot.changeLog.sorted { lhs, rhs in
            if lhs.effectiveAt == rhs.effectiveAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.effectiveAt > rhs.effectiveAt
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let thread {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(thread.title)
                                .font(FontManager.geist(size: 20, weight: .semibold))
                                .foregroundColor(Color.appTextPrimary(colorScheme))
                            Text("Recent activity")
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.66) : Color.black.opacity(0.58))
                        }

                        if sortedChanges.isEmpty {
                            trackerEmptyState
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(sortedChanges) { change in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .top, spacing: 10) {
                                            Circle()
                                                .fill(activityColor(for: change.type))
                                                .frame(width: 8, height: 8)
                                                .padding(.top, 6)

                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(change.title?.trackerNonEmpty ?? change.content)
                                                    .font(FontManager.geist(size: 14, weight: .medium))
                                                    .foregroundColor(Color.appTextPrimary(colorScheme))
                                                    .fixedSize(horizontal: false, vertical: true)

                                                HStack(spacing: 8) {
                                                    Text(activityLabel(for: change.type))
                                                    Text(compactActivityDate(change.effectiveAt))
                                                }
                                                .font(FontManager.geist(size: 11, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45))
                                            }
                                        }

                                        if let title = change.title?.trackerNonEmpty, title != change.content {
                                            Text(change.content)
                                                .font(FontManager.geist(size: 12, weight: .regular))
                                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.66))
                                                .padding(.leading, 18)
                                        }
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(TrackerTheme.neutralCardFill(colorScheme))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(TrackerTheme.neutralCardBorder(colorScheme), lineWidth: 0.8)
                                    )
                                }
                            }
                        }
                    } else {
                        trackerEmptyState
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground(colorScheme))
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var trackerEmptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No tracker changes yet.")
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))
            Text("Confirmed tracker updates will appear here in order.")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.64) : Color.black.opacity(0.56))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(TrackerTheme.neutralCardFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(TrackerTheme.neutralCardBorder(colorScheme), lineWidth: 0.8)
        )
    }

    private func activityColor(for type: TrackerChangeType) -> Color {
        switch type {
        case .ruleChange:
            return TrackerTheme.accent(colorScheme)
        case .correction:
            return colorScheme == .dark ? Color.orange.opacity(0.85) : Color.orange
        case .note:
            return colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.5)
        case .stateUpdate:
            return TrackerTheme.bullet(colorScheme)
        }
    }

    private func activityLabel(for type: TrackerChangeType) -> String {
        switch type {
        case .ruleChange:
            return "Rule change"
        case .stateUpdate:
            return "State update"
        case .correction:
            return "Correction"
        case .note:
            return "Note"
        }
    }

    private func compactActivityDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct TrackerDraftCard: View {
    let draft: TrackerOperationDraft
    let colorScheme: ColorScheme
    let isPending: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pending change")
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.56))
                    .textCase(.uppercase)
                Spacer()
                if !isPending {
                    Text("Resolved")
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.54) : Color.black.opacity(0.5))
                }
            }

            Text(draft.summaryText)
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            if !draft.validationErrors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.validationErrors, id: \.self) { error in
                        Text(error)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.68))
                    }
                }
            }

            if isPending && draft.requiresConfirmation {
                HStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Text("Confirm")
                            .font(FontManager.geist(size: 13, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.88))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(FontManager.geist(size: 13, weight: .semibold))
                            .foregroundColor(Color.appTextPrimary(colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(TrackerTheme.neutralCardBorder(colorScheme), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(TrackerTheme.neutralCardFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(TrackerTheme.neutralCardBorder(colorScheme), lineWidth: 0.8)
        )
    }
}

struct TrackerInlineStateCard: View {
    let state: TrackerDerivedState
    let colorScheme: ColorScheme

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.78) : Color.black.opacity(0.72)
    }

    private var visibleFacts: [String] {
        trackerStateHighlights(from: state, limit: 3)
    }

    private var latestChange: TrackerChange? {
        state.recentChanges.first
    }

    private func changeLabel(for change: TrackerChange) -> String {
        change.title?.trackerNonEmpty ?? change.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(latestChange == nil ? "Current state" : "Latest change")
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.52))
                    .textCase(.uppercase)

                Spacer()

                if let latestChange {
                    Text(compactTrackerDate(latestChange.effectiveAt))
                        .font(FontManager.geist(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.45))
                }
            }

            Text(latestChange.map { changeLabel(for: $0) } ?? state.headline)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(2)

            if !visibleFacts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleFacts, id: \.self) { fact in
                        Text("• \(fact)")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(state.summaryLine)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(secondaryTextColor)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(TrackerTheme.neutralCardFill(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(TrackerTheme.neutralCardBorder(colorScheme), lineWidth: 0.8)
        )
    }

    private func compactTrackerDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        formatter.dateStyle = .medium
        return formatter.string(from: date)
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
                .font(FontManager.geist(size: 15, weight: .regular))
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .textSelection(.enabled)
                .lineSpacing(4)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
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
                    .font(FontManager.geist(size: 15, weight: .regular))
                    .foregroundColor(.blue)
                    .underline()
                    .textSelection(.enabled)
                    .lineSpacing(4)
            }
        } else {
            Text(component.text)
                .font(FontManager.geist(size: 15, weight: .regular))
                .foregroundColor(Color.shadcnForeground(colorScheme))
                .lineSpacing(4)
                .lineLimit(nil)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Typing Indicator Component

struct TypingIndicatorView: View {
    let colorScheme: ColorScheme

    var thinkingMessages = ["Thinking...", "Analyzing your data...", "Getting insights..."]

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 0.18)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let animationIndex = Int(elapsed / 0.18) % 3
            let messageIndex = Int(elapsed / 3.0) % thinkingMessages.count

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(colorScheme == .dark ? Color.white : Color.black)
                            .frame(width: 6, height: 6)
                            .offset(y: getWaveOffset(for: index, animationIndex: animationIndex))
                            .opacity(0.8 + 0.2 * Double(index == animationIndex ? 1 : 0))
                    }
                    Spacer()
                }
                .frame(width: 40, height: 12)

                Text(thinkingMessages[messageIndex])
                    .font(FontManager.geist(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    private func getWaveOffset(for index: Int, animationIndex: Int) -> CGFloat {
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

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 0.2)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 1.25
            let opacity = 0.35 + (((sin(phase) + 1) / 2) * 0.5)

            Rectangle()
                .fill(colorScheme == .dark ? Color.white : Color.black)
                .frame(width: 2, height: 14)
                .opacity(opacity)
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

// MARK: - Modern Loading Indicator (ChatGPT-style waiting row)

struct ModernLoadingIndicator: View {
    let colorScheme: ColorScheme
    let label: String

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 0.18)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate

            HStack {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.55))
                            .frame(width: 7, height: 7)
                            .scaleEffect(dotScale(for: index, elapsed: elapsed))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                )
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }

    private func dotScale(for index: Int, elapsed: TimeInterval) -> CGFloat {
        let phase = elapsed + (Double(index) * 0.2)
        return 1.0 + (sin(phase * .pi * 1.6) * 0.15)
    }
}

// MARK: - Aligned Text Editor (Fixes cursor alignment issue)

struct AlignedTextEditor: UIViewRepresentable {
    @Binding var text: String
    let colorScheme: ColorScheme
    let height: CGFloat
    let onContentHeightChange: (CGFloat) -> Void
    let onFocusChange: (Bool) -> Void
    let onSwipeDown: () -> Void
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = UIFont(name: "Geist-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16, weight: .regular)
        textView.text = text
        textView.textColor = colorScheme == .dark ? .white : .black
        textView.tintColor = colorScheme == .dark ? UIColor.white.withAlphaComponent(0.8) : UIColor.black.withAlphaComponent(0.8)
        
        textView.contentInset = .zero
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        if #available(iOS 16.0, *) {
            textView.verticalScrollIndicatorInsets = .zero
        } else {
            textView.scrollIndicatorInsets = .zero
        }

        textView.isScrollEnabled = false
        updateTextInsets(for: textView)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let dismissPanGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSwipeDownPan(_:))
        )
        dismissPanGesture.cancelsTouchesInView = false
        dismissPanGesture.delegate = context.coordinator
        textView.addGestureRecognizer(dismissPanGesture)
        
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }

        textView.font = UIFont(name: "Geist-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16, weight: .regular)
        textView.textColor = colorScheme == .dark ? .white : .black
        textView.tintColor = colorScheme == .dark ? UIColor.white.withAlphaComponent(0.8) : UIColor.black.withAlphaComponent(0.8)
        textView.layoutIfNeeded()
        updateTextInsets(for: textView)
        textView.textContainer.lineFragmentPadding = 0

        let availableTextHeight = max(42, height - 16)
        let fittingHeight = textView.sizeThatFits(CGSize(width: max(textView.bounds.width, 1), height: .greatestFiniteMagnitude)).height
        textView.isScrollEnabled = fittingHeight > availableTextHeight + 1

        context.coordinator.reportContentHeight(textView)

        DispatchQueue.main.async {
            let selectedRange = textView.selectedRange
            if selectedRange.location != NSNotFound {
                textView.scrollRangeToVisible(selectedRange)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func updateTextInsets(for textView: UITextView) {
        textView.textContainerInset = UIEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
    }
    
    class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: AlignedTextEditor
        private var didTriggerSwipeDismiss = false

        init(_ parent: AlignedTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            reportContentHeight(textView)
            
            // Auto-scroll to cursor position so user can see what they're typing
            DispatchQueue.main.async {
                let selectedRange = textView.selectedRange
                if selectedRange.location != NSNotFound {
                    textView.scrollRangeToVisible(selectedRange)
                }
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            reportContentHeight(textView)
            parent.onFocusChange(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onFocusChange(false)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // Keep return for newline so users can format prompts naturally.
            if text == "\n" {
                return true
            }
            return true
        }

        @objc
        func handleSwipeDownPan(_ gesture: UIPanGestureRecognizer) {
            guard let textView = gesture.view as? UITextView else { return }

            switch gesture.state {
            case .began:
                didTriggerSwipeDismiss = false
            case .changed, .ended:
                guard !didTriggerSwipeDismiss else { return }
                let translation = gesture.translation(in: textView)
                let verticalDrag = translation.y
                let horizontalDrag = abs(translation.x)
                let isAtTop = textView.contentOffset.y <= 0.5
                guard isAtTop, verticalDrag > 24, verticalDrag > horizontalDrag else { return }
                didTriggerSwipeDismiss = true
                parent.onSwipeDown()
            default:
                didTriggerSwipeDismiss = false
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func reportContentHeight(_ textView: UITextView) {
            DispatchQueue.main.async {
                let fitting = textView.sizeThatFits(
                    CGSize(width: max(textView.bounds.width, 1), height: .greatestFiniteMagnitude)
                ).height
                let clamped = max(24, ceil(fitting))
                self.parent.onContentHeightChange(clamped)
            }
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
    @StateObject private var chatUsageTracker = ChatUsageTracker.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
    }

    private var cardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : .white
    }

    private var cardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                usageOverviewCard
                Spacer()
            }
            .padding(20)
            .background(backgroundColor)
            .navigationTitle("Chat Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(primaryTextColor)
                }
            }
        }
    }

    private var usageOverviewCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Daily Usage")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                Spacer()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * (chatUsageTracker.usagePercentage / 100.0))
                }
            }
            .frame(height: 8)

            VStack(spacing: 8) {
                usageStatRow("Used", formatTokenCount(chatUsageTracker.dailyTokensUsed))
                usageStatRow("Remaining", formatTokenCount(chatUsageTracker.dailyTokensRemaining))
                usageStatRow("Limit", formatTokenCount(chatUsageTracker.dailyTokenLimit))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardFillColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(cardStrokeColor, lineWidth: 0.5)
                )
        )
    }

    private func usageStatRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(secondaryTextColor)
            Spacer()
            Text(value)
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(primaryTextColor)
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
        colorScheme == .dark ? Color.black : .white
    }

    private var topControlFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }

    private var topControlBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.05)
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color.black.opacity(0.40)
    }
    
    let onSelectConversation: (SavedConversation) -> Void
    let onDeleteConversation: (SavedConversation) -> Void
    var onDismiss: (() -> Void)? = nil

    private var trackerConversations: [SavedConversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = searchService.savedConversations
            .filter { $0.kind == .tracker }
            .sorted { $0.updatedAt > $1.updatedAt }

        guard !query.isEmpty else { return sorted }
        return sorted.filter { conversation in
            let title = conversation.title.lowercased()
            let subtitle = (conversation.subtitle ?? "").lowercased()
            let firstUser = conversation.messages.first(where: { $0.isUser })?.text.lowercased() ?? ""
            return title.contains(query) || subtitle.contains(query) || firstUser.contains(query)
        }
    }
    
    private var groupedConversations: [(String, [SavedConversation])] {
        let calendar = Calendar.current
        let now = Date()
        var groups: [(String, [SavedConversation])] = []
        let sorted = searchService.savedConversations
            .filter { $0.kind != .tracker }
            .sorted { $0.updatedAt > $1.updatedAt }
        
        let today = sorted.filter { calendar.isDateInToday($0.updatedAt) }
        if !today.isEmpty { groups.append(("Today", today)) }

        let yesterday = sorted.filter { calendar.isDateInYesterday($0.updatedAt) }
        if !yesterday.isEmpty { groups.append(("Yesterday", yesterday)) }

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let last7Days = sorted.filter { $0.updatedAt >= weekAgo && !calendar.isDateInToday($0.updatedAt) && !calendar.isDateInYesterday($0.updatedAt) }
        if !last7Days.isEmpty { groups.append(("Previous 7 days", last7Days)) }

        let older = sorted.filter { $0.updatedAt < weekAgo }
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
        ZStack {
            sidebarBackgroundColor
                .ignoresSafeArea()

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            searchService.loadConversationHistoryLocally()
            Task {
                await searchService.loadConversationsFromSupabase()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.45))

                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(FontManager.geist(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(topControlFillColor)
                    .overlay(
                        Capsule()
                            .stroke(topControlBorderColor, lineWidth: 0.8)
                    )
            )

            Button(action: {
                HapticManager.shared.selection()
                searchService.startNewConversation()
                if let onDismiss = onDismiss { onDismiss() } else { dismiss() }
            }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(topControlFillColor)
                            .overlay(
                                Circle()
                                    .stroke(topControlBorderColor, lineWidth: 0.8)
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("New chat")

            Button(action: {
                HapticManager.shared.selection()
                searchService.startNewTrackerConversation()
                if let onDismiss = onDismiss { onDismiss() } else { dismiss() }
            }) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(topControlFillColor)
                            .overlay(
                                Circle()
                                    .stroke(topControlBorderColor, lineWidth: 0.8)
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("New tracker")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(sidebarBackgroundColor)
        .frame(maxWidth: .infinity)
    }

    private var isShowingSearchResults: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasAnyVisibleConversations: Bool {
        !trackerConversations.isEmpty || !filteredGroupedConversations.isEmpty
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
            Text("Start a new chat or tracker and it will appear here")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var conversationListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !trackerConversations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trackers")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(sectionLabelColor)
                            .textCase(.uppercase)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)

                        ForEach(trackerConversations) { conversation in
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
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                }

                ForEach(filteredGroupedConversations, id: \.0) { sectionTitle, conversations in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sectionTitle)
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(sectionLabelColor)
                            .textCase(.uppercase)
                            .padding(.horizontal, 16)
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
                    .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 12)
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
    @StateObject private var searchService = SearchService.shared
    
    private var displayTitle: String {
        if conversation.title.isEmpty {
            if conversation.kind == .tracker {
                return "Tracker"
            }
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

    private var isActive: Bool {
        searchService.currentConversationId == conversation.id
    }
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(displayTitle)
                    .font(FontManager.geist(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.88))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    isActive
                        ? (colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055))
                        : Color.clear
                )
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
