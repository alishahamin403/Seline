import SwiftUI

struct ConversationSearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom: UUID?
    @State private var showingSidebar = false

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
                headerView
                conversationScrollView
                inputAreaView
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
            // Load saved conversations from local storage when conversation view appears
            searchService.loadConversationHistoryLocally()
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

    private var headerView: some View {
        HStack(spacing: 12) {
            // Sidebar toggle button on the left
            Button(action: {
                HapticManager.shared.selection()
                isInputFocused = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSidebar.toggle()
                }
            }) {
                Image(systemName: "line.3.horizontal")
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
    }

    private var conversationScrollView: some View {
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
    }

    private var inputAreaView: some View {
        VStack(spacing: 0) {
            inputBoxContainer
        }
        .background(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
    }

    private var inputBoxContainer: some View {
        HStack(spacing: 10) {
            inputTextField
            sendButton
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color.black : Color.white)
        )
        .overlay(inputBoxBorder)
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

    private var inputTextField: some View {
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
    }

    private var sendButton: some View {
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : (colorScheme == .dark ? Color.white : Color.black))
                .scaleEffect(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1.0 : 1.1, anchor: .center)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchService.isLoadingQuestionResponse)
        .animation(.easeInOut(duration: 0.15), value: messageText)
        .padding(.trailing, 10)
    }

    private var inputBoxBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(
                isInputFocused
                    ? (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.15))
                    : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)),
                lineWidth: 1
            )
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

                // Show related receipts for expense queries
                if !message.isUser, let relatedData = message.relatedData {
                    let receipts = relatedData.filter { $0.type == .receipt }
                    if !receipts.isEmpty {
                        // Deduplicate receipts by ID to avoid showing duplicates
                        var seenIds = Set<UUID>()
                        let uniqueReceipts = receipts.filter { receipt in
                            let isNew = !seenIds.contains(receipt.id)
                            seenIds.insert(receipt.id)
                            return isNew
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Divider()
                                .padding(.vertical, 4)

                            ForEach(uniqueReceipts) { receipt in
                                ReceiptCardView(
                                    id: receipt.id,
                                    merchant: receipt.merchant ?? receipt.title,
                                    date: receipt.date,
                                    amount: receipt.amount,
                                    colorScheme: colorScheme,
                                    onTap: {
                                        // TODO: Handle receipt tap - navigate to receipt detail or note
                                        print("Receipt tapped: \(receipt.id)")
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        message.isUser
                            ? (colorScheme == .dark ? Color.white : Color(white: 0.25))
                            : .clear
                    )
            )
            .overlay(
                message.isUser ? AnyView(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            colorScheme == .dark ? Color.black.opacity(0.1) : Color.white.opacity(0.15),
                            lineWidth: 0.5
                        )
                ) : AnyView(EmptyView())
            )

            if !message.isUser {
                Spacer()
            }
        }
        .padding(.leading, message.isUser ? 16 : 0)
        .padding(.trailing, message.isUser ? 16 : 16)
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
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.01, perform: {})
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
