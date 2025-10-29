import SwiftUI

struct ConversationSearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom: UUID?
    @State private var showingHistory = false

    private var eventConfirmationDetails: String {
        guard let eventData = searchService.pendingEventCreation else { return "" }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let targetDate = ISO8601DateFormatter().date(from: eventData.date) ?? Date()

        let dateStr = dateFormatter.string(from: targetDate)
        let timeStr = eventData.time ?? "all day"

        return "Date: \(dateStr)\nTime: \(timeStr)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and close button
            HStack(spacing: 12) {
                Text(searchService.conversationTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .lineLimit(1)

                Spacer()

                Button(action: {
                    HapticManager.shared.selection()
                    showingHistory = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
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
                                Text("Thinking...")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
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

            // Action confirmation area (shown when pending action exists)
            if searchService.pendingEventCreation != nil {
                ActionConfirmationView(
                    title: searchService.pendingEventCreation?.title ?? "Event",
                    details: eventConfirmationDetails,
                    onConfirm: {
                        HapticManager.shared.selection()
                        searchService.confirmEventCreation()
                    },
                    onCancel: {
                        HapticManager.shared.selection()
                        searchService.cancelAction()
                    },
                    colorScheme: colorScheme
                )
            } else if searchService.pendingNoteCreation != nil {
                ActionConfirmationView(
                    title: searchService.pendingNoteCreation?.title ?? "Note",
                    details: "Content: \(searchService.pendingNoteCreation?.content ?? "")",
                    onConfirm: {
                        HapticManager.shared.selection()
                        searchService.confirmNoteCreation()
                    },
                    onCancel: {
                        HapticManager.shared.selection()
                        searchService.cancelAction()
                    },
                    colorScheme: colorScheme
                )
            } else if searchService.pendingNoteUpdate != nil {
                ActionConfirmationView(
                    title: searchService.pendingNoteUpdate?.noteTitle ?? "Note",
                    details: "Adding: \(searchService.pendingNoteUpdate?.contentToAdd ?? "")",
                    onConfirm: {
                        HapticManager.shared.selection()
                        searchService.confirmNoteUpdate()
                    },
                    onCancel: {
                        HapticManager.shared.selection()
                        searchService.cancelAction()
                    },
                    colorScheme: colorScheme
                )
            }

            // Input area
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
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
        .onAppear {
            isInputFocused = true
        }
        .sheet(isPresented: $showingHistory) {
            ConversationHistoryView()
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
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(message.isUser ? (colorScheme == .dark ? Color.black : Color.white) : Color.shadcnForeground(colorScheme))
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.isUser ? (colorScheme == .dark ? Color.white : Color.black) : Color.gray.opacity(0.2))
                )

                if !message.isUser {
                    Spacer()
                }
            }

            Text(message.formattedTime)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                .padding(.horizontal, 12)
        }
        .padding(.horizontal, 16)
    }
}

struct ActionConfirmationView: View {
    let title: String
    let details: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)

                Text(details)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                    .lineLimit(4)
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onConfirm) {
                    Text("Confirm")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(colorScheme == .dark ? Color.white : Color.black)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
    }
}

#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
