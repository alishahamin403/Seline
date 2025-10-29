import SwiftUI

struct ConversationSearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var searchService = SearchService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom: UUID?

    var body: some View {
        print("DEBUG ConversationSearchView: body is rendering, conversation history count: \(searchService.conversationHistory.count)")

        return VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    HapticManager.shared.selection()
                    // Clear conversation state when dismissing
                    searchService.clearConversation()
                    searchService.clearSearch()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                    Text("AI Assistant")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Spacer()

                // Invisible spacer for centering
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .opacity(0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)

            Divider()

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
                                Text("Thinking...")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
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
            }

            Divider()

            // Input area
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField(
                        "Ask a follow-up question...",
                        text: $messageText
                    )
                    .focused($isInputFocused)
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button(action: {
                        if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            HapticManager.shared.selection()
                            let query = messageText
                            messageText = ""
                            Task {
                                await searchService.addConversationMessage(query)
                            }
                        }
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchService.isLoadingQuestionResponse)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        }
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        .onAppear {
            isInputFocused = true
        }
    }
}

struct ConversationMessageView: View {
    let message: ConversationMessage
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.isUser {
                    Spacer()
                }

                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                    Text(message.text)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(message.isUser ? Color.white : Color.shadcnForeground(colorScheme))
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.isUser ? Color.blue : Color.gray.opacity(0.2))
                )

                if !message.isUser {
                    Spacer()
                }
            }

            Text(message.formattedTime)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
