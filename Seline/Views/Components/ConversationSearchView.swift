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

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dismiss overlay on right 25% (tap to close sidebar)
            if showingSidebar {
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: UIScreen.main.bounds.width * 0.25)
                        .onTapGesture {
                            HapticManager.shared.selection()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingSidebar = false
                            }
                        }
                }
                .frame(maxHeight: .infinity)
            }

            // Main conversation view
            VStack(spacing: 0) {
                // Header with title and close button only
                HStack(spacing: 12) {
                    // Sidebar toggle button on the left
                    Button(action: {
                        HapticManager.shared.selection()
                        isInputFocused = false
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showingSidebar.toggle()
                        }
                    }) {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .zIndex(10)

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
                        dismiss()
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

            // Input area - ChatGPT-style modern design
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TextField(
                        "Ask a follow-up question...",
                        text: $messageText
                    )
                    .font(.system(size: 14, weight: .regular))
                    .focused($isInputFocused)
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .accentColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                    .textFieldStyle(PlainTextFieldStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

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
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : (colorScheme == .dark ? Color.white : Color.black))
                            .scaleEffect(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1.0 : 1.1, anchor: .center)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchService.isLoadingQuestionResponse)
                    .animation(.easeInOut(duration: 0.15), value: messageText)
                    .padding(.trailing, 10)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color.black : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isInputFocused
                                ? (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.15))
                                : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: isInputFocused
                        ? (colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12))
                        : (colorScheme == .dark ? Color.black.opacity(0.2) : Color.black.opacity(0.08)),
                    radius: isInputFocused ? 12 : 6,
                    x: 0,
                    y: isInputFocused ? 8 : 2
                )
                .animation(.easeInOut(duration: 0.2), value: isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            }
            // Main VStack
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
            .offset(x: showingSidebar ? UIScreen.main.bounds.width * 0.75 : 0)
            .animation(.easeInOut(duration: 0.2), value: showingSidebar)

            // Chat history sidebar overlay
            if showingSidebar {
                ConversationSidebarView(isPresented: $showingSidebar)
                    .transition(.move(edge: .leading))
                    .zIndex(20)
            }
        }
        // ZStack with sidebar overlay
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
                        .foregroundColor(message.isUser ? (colorScheme == .dark ? Color.white : Color.black) : Color.shadcnForeground(colorScheme))
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
                            ? (colorScheme == .dark ? Color.black : Color.white)
                            : (colorScheme == .dark
                                ? Color.gray.opacity(0.15)
                                : Color.gray.opacity(0.15))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        message.isUser ? (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1)) : Color.gray.opacity(0.2),
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
