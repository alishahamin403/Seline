import SwiftUI

struct ConversationSearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom: UUID?
    @State private var showingSidebar = false
    @State private var thinkingElapsedTime: Int = 0
    @State private var thinkingTimer: Timer?
    @State private var showingFinalSummary = false
    @State private var generatedTitle = ""
    @State private var isGeneratingTitle = false

    var body: some View {
        HStack(spacing: 0) {
            // Chat history sidebar
            if showingSidebar {
                ConversationSidebarView(isPresented: $showingSidebar)
                    .transition(.move(edge: .leading))
            }

            // Main conversation view
            VStack(spacing: 0) {
                // Header with title and close button only
                HStack(spacing: 12) {
                    // Sidebar toggle button on the left
                    Button(action: {
                        HapticManager.shared.selection()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Only show title if this is NOT a new conversation
                    if !searchService.isNewConversation {
                        Text(searchService.conversationTitle)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button(action: {
                        HapticManager.shared.selection()
                        // If this is a new conversation, show summary before closing
                        if searchService.isNewConversation && !searchService.conversationHistory.isEmpty {
                            showingFinalSummary = true
                        } else {
                            dismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)

            // Conversation thread
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(searchService.conversationHistory) { message in
                            ConversationMessageView(message: message)
                                .id(message.id)
                        }

                        if searchService.isLoadingQuestionResponse {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(colorScheme == .dark ? Color.white : Color.black)
                                Text("Thinking... \(formatElapsedTime(thinkingElapsedTime))")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .onAppear {
                                startThinkingTimer()
                            }
                            .onChange(of: searchService.isLoadingQuestionResponse) { isLoading in
                                if !isLoading {
                                    stopThinkingTimer()
                                }
                            }
                        }
                    }
                    .padding(.vertical, 16)
                    .onChange(of: searchService.conversationHistory.count) { _ in
                        withAnimation {
                            if let lastMessage = searchService.conversationHistory.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in
                            // Dismiss keyboard when user starts scrolling
                            if isInputFocused {
                                isInputFocused = false
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                )
            }

            // Action confirmation area disabled - action creation feature removed
            // All queries now route directly to conversation mode

            // Input area - show appropriate input based on context
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField(
                        "Ask a follow-up question...",
                        text: $messageText
                    )
                    .font(.system(size: 13, weight: .regular))
                    .focused($isInputFocused)
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .textFieldStyle(PlainTextFieldStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(colorScheme == .dark ? Color.black : Color.white)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )

                    Button(action: {
                        if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HapticManager.shared.selection()
                            // Send conversation message
                            let query = messageText
                            messageText = ""
                            Task {
                                await searchService.addConversationMessage(query)
                            }
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : (colorScheme == .dark ? Color.white : Color.black))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchService.isLoadingQuestionResponse)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            }
            // Main VStack
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        }
        // HStack with sidebar
        .onAppear {
            isInputFocused = true
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
        .sheet(isPresented: $showingFinalSummary) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Save Conversation")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button(action: { showingFinalSummary = false }) {
                        Image(systemName: "xmark")
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    }
                }
                .padding(16)
                .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                .border(Color.gray.opacity(0.2), width: 0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Generate title section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Generated Title")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            if isGeneratingTitle {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Generating title...")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(Color.gray)
                                }
                            } else {
                                // Display generated title or let user edit
                                TextField(
                                    "Enter title or use generated one",
                                    text: Binding(
                                        get: { generatedTitle.isEmpty ? searchService.conversationTitle : generatedTitle },
                                        set: { generatedTitle = $0 }
                                    )
                                )
                                .font(.system(size: 14, weight: .regular))
                                .padding(12)
                                .background(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.top, 4)
                            }
                        }

                        // Summary of conversation
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Conversation Summary")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(searchService.conversationHistory.count) messages")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(Color.gray)

                                // Show first and last user messages as preview
                                if let firstUserMsg = searchService.conversationHistory.first(where: { $0.isUser }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Started with:")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Color.gray)
                                        Text(firstUserMsg.text.prefix(100) + (firstUserMsg.text.count > 100 ? "..." : ""))
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .padding(12)
                            .background(colorScheme == .dark ? Color.gray.opacity(0.1) : Color.gray.opacity(0.05))
                            .cornerRadius(8)
                        }

                        Spacer()
                    }
                    .padding(16)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: {
                        showingFinalSummary = false
                    }) {
                        Text("Continue Conversation")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.gray.opacity(0.2))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                            .cornerRadius(8)
                    }

                    Button(action: {
                        // Use generated title if provided, otherwise use current
                        if !generatedTitle.isEmpty {
                            searchService.conversationTitle = generatedTitle
                        }
                        showingFinalSummary = false
                        dismiss()
                    }) {
                        Text("Save & Close")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color.blue)
                            .foregroundColor(Color.white)
                            .cornerRadius(8)
                    }
                }
                .padding(16)
                .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                .border(Color.gray.opacity(0.2), width: 0.5)
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .onAppear {
                // Generate final title when summary sheet appears
                isGeneratingTitle = true
                Task {
                    await searchService.generateFinalConversationTitle()
                    DispatchQueue.main.async {
                        generatedTitle = searchService.conversationTitle
                        isGeneratingTitle = false
                    }
                }
            }
        }
    }

    // MARK: - Thinking Timer Helpers

    private func startThinkingTimer() {
        thinkingElapsedTime = 0
        thinkingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            thinkingElapsedTime += 1
        }
    }

    private func stopThinkingTimer() {
        thinkingTimer?.invalidate()
        thinkingTimer = nil
        thinkingElapsedTime = 0
    }

    private func formatElapsedTime(_ seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        if seconds < 60 {
            return "(\(seconds)s)"
        } else {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "(\(minutes)m \(remainingSeconds)s)"
        }
    }
}

struct ConversationMessageView: View {
    let message: ConversationMessage
    @Environment(\.colorScheme) var colorScheme

    // Determine if message has complex formatting
    private var hasComplexFormatting: Bool {
        message.text.contains("**") || message.text.contains("*") ||
            message.text.contains("`") || message.text.contains("- ") ||
            message.text.contains("• ") || message.text.contains("\n")
    }

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                if hasComplexFormatting && !message.isUser {
                    // Use markdown renderer for AI responses with formatting
                    MarkdownText(markdown: message.text, colorScheme: colorScheme)
                } else {
                    // Simple text for user messages or unformatted AI responses
                    Text(message.text)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(message.isUser ? (colorScheme == .dark ? Color.black : Color.white) : Color.shadcnForeground(colorScheme))
                        .textSelection(.enabled)
                        .lineLimit(nil)
                }

                // Show time taken for AI responses after streaming completes
                if !message.isUser, let timeTaken = message.timeTakenFormatted {
                    Text("⏱️ Took \(timeTaken) to think")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        message.isUser
                            ? (colorScheme == .dark ? Color.white : Color.black)
                            : (colorScheme == .dark
                                ? Color.gray.opacity(0.15)
                                : Color.gray.opacity(0.15))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        message.isUser ? Color.clear : Color.gray.opacity(0.2),
                        lineWidth: 0.5
                    )
            )

            if !message.isUser {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
