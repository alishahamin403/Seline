import SwiftUI

struct ConversationSearchView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var searchService = SearchService.shared
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var scrollToBottom: UUID?
    @State private var showingSidebar = false
    @State private var inputHeight: CGFloat = 44
    @State private var isStreamingResponse = false
    @State private var streamingStartTime: Date?
    @State private var elapsedTimeUpdateTrigger = UUID() // Triggers elapsed time updates

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
                // Streaming indicator bar
                if isStreamingResponse {
                    streamingIndicatorView
                }

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
            // Load saved conversations from local storage when conversation view appears
            searchService.loadConversationHistoryLocally()

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
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                // Icon/greeting
                Text("👋")
                    .font(.system(size: 64))

                Text("Hi! I'm Seline")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)

                Text("Your intelligent personal assistant")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            }
            .frame(maxWidth: .infinity)

            // Help section
            VStack(alignment: .leading, spacing: 12) {
                Text("I can help with:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 16)

                VStack(spacing: 8) {
                    emptyStateCard(emoji: "💰", title: "Spending analysis", subtitle: "Track your expenses")
                    emptyStateCard(emoji: "📅", title: "Schedule planning", subtitle: "Manage your calendar")
                    emptyStateCard(emoji: "📝", title: "Note search", subtitle: "Find your notes")
                    emptyStateCard(emoji: "📍", title: "Location insights", subtitle: "Explore places you go")
                }
                .padding(.horizontal, 16)
            }

            // Example questions
            VStack(alignment: .leading, spacing: 12) {
                Text("Try asking:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .padding(.horizontal, 16)

                VStack(spacing: 6) {
                    emptyStateExample("💡 How much did I spend on coffee this month?")
                    emptyStateExample("💡 What's my busiest day this week?")
                    emptyStateExample("💡 Show me my recent dining expenses")
                }
                .padding(.horizontal, 16)
            }

            VStack(alignment: .center, spacing: 8) {
                Text("Start typing below or tap an example above!")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)

            Spacer()
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyStateCard(emoji: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
        .cornerRadius(8)
    }

    private func emptyStateExample(_ text: String) -> some View {
        Button(action: {
            // Extract the question without the emoji
            let question = String(text.dropFirst(2))
            HapticManager.shared.selection()
            Task {
                await searchService.addConversationMessage(question)
            }
        }) {
            HStack(spacing: 8) {
                Text(text)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
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
        VStack(spacing: 0) {
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

            Divider()
                .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
        }
    }

    private var conversationScrollView: some View {
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
                                }
                            )
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }

                        if searchService.isLoadingQuestionResponse {
                            TypingIndicatorView(colorScheme: colorScheme)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .padding(.vertical, 16)
                }
                .onChange(of: searchService.conversationHistory.count) { _ in
                    withAnimation(.easeInOut(duration: 0.3)) {
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
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Swipe down to dismiss keyboard
                    if value.translation.height > 20 && isInputFocused {
                        isInputFocused = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
        )
    }

    private var inputBoxContainer: some View {
        HStack(spacing: 12) {
            inputTextEditor
            sendButton
        }
        .frame(height: inputHeight)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(colorScheme == .dark ? Color(white: 0.08) : Color(white: 0.96))
        )
        .overlay(inputBoxBorder)
        .shadow(
            color: isInputFocused
                ? (colorScheme == .dark ? Color.black.opacity(0.3) : Color.black.opacity(0.1))
                : (colorScheme == .dark ? Color.black.opacity(0.15) : Color.black.opacity(0.05)),
            radius: isInputFocused ? 10 : 4,
            x: 0,
            y: isInputFocused ? 6 : 1
        )
        .animation(.easeInOut(duration: 0.2), value: isInputFocused)
        .animation(.easeInOut(duration: 0.15), value: inputHeight)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var inputTextEditor: some View {
        ZStack(alignment: .topLeading) {
            // Placeholder
            if messageText.isEmpty {
                Text("Ask a follow-up question...")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.45))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $messageText)
                .font(.system(size: 15, weight: .regular))
                .focused($isInputFocused)
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                .accentColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                .textFieldStyle(PlainTextFieldStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .scrollContentBackground(.hidden)
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
            if !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HapticManager.shared.medium()
                let query = messageText
                messageText = ""
                updateInputHeight()
                Task {
                    await searchService.addConversationMessage(query)
                }
            }
        }) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.3) : (colorScheme == .dark ? Color.white : Color.black))
                .opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                .scaleEffect(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.9 : 1.0, anchor: .center)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || searchService.isLoadingQuestionResponse)
        .animation(.easeInOut(duration: 0.15), value: messageText)
        .padding(.trailing, 12)
        .padding(.bottom, 2)
    }

    private var inputBoxBorder: some View {
        RoundedRectangle(cornerRadius: 18)
            .stroke(
                isInputFocused
                    ? (colorScheme == .dark ? Color.white.opacity(0.25) : Color.black.opacity(0.12))
                    : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)),
                lineWidth: 1
            )
    }

}

struct ConversationMessageView: View {
    let message: ConversationMessage
    let onSendMessage: (String) async -> Void
    @Environment(\.colorScheme) var colorScheme
    @State private var isLongPressed = false
    @State private var showContextMenu = false

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
            relatedDataView
            followUpSuggestionsView
        }
    }

    private var messageText: some View {
        Group {
            if hasComplexFormatting && !message.isUser {
                MarkdownText(markdown: message.text, colorScheme: colorScheme)
            } else if !message.isUser {
                SimpleTextWithPhoneLinks(text: message.text, colorScheme: colorScheme)
            } else {
                Text(message.text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(message.isUser ? (colorScheme == .dark ? Color.black : Color.white) : Color.shadcnForeground(colorScheme))
                    .textSelection(.enabled)
                    .lineLimit(nil)
            }
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
        colorScheme == .dark
            ? Color.white.opacity(isPressed ? 0.1 : 0.05)
            : Color.black.opacity(isPressed ? 0.08 : 0.03)
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
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
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
            Image(systemName: "receipt.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.green)

        case .event:
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.blue)

        case .note:
            Image(systemName: "doc.text.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.orange)

        case .location:
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.red)

        case .email:
            Image(systemName: "envelope.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.purple)
        }
    }

    @ViewBuilder
    private var typeIconBackground: some View {
        switch item.type {
        case .receipt:
            Color.green.opacity(colorScheme == .dark ? 0.15 : 0.1)
        case .event:
            Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.1)
        case .note:
            Color.orange.opacity(colorScheme == .dark ? 0.15 : 0.1)
        case .location:
            Color.red.opacity(colorScheme == .dark ? 0.15 : 0.1)
        case .email:
            Color.purple.opacity(colorScheme == .dark ? 0.15 : 0.1)
        }
    }

    @ViewBuilder
    private var rightInfoView: some View {
        switch item.type {
        case .receipt:
            if let amount = item.amount {
                Text(String(format: "$%.2f", amount))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
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
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.yellow)
                .opacity(0.6)
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

#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
