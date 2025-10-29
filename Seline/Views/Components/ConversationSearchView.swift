import SwiftUI

struct ConversationSearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Minimalist header - just close button
            HStack {
                Button(action: {
                    HapticManager.shared.selection()
                    searchService.clearConversation()
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
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

            // Input area
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField(
                        "Ask a follow-up question...",
                        text: $messageText
                    )
                    .focused($isInputFocused)
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .textFieldStyle(PlainTextFieldStyle())
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
