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
            relatedReceiptsView
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
    private var relatedReceiptsView: some View {
        if !message.isUser, let relatedData = message.relatedData {
            let receipts = relatedData.filter { $0.type == .receipt }
            if !receipts.isEmpty {
                var seenIds = Set<UUID>()
                let uniqueReceipts = receipts.filter { receipt in
                    let isNew = !seenIds.contains(receipt.id)
                    seenIds.insert(receipt.id)
                    return isNew
                }

                VStack(alignment: .leading, spacing: 8) {
                    Divider().padding(.vertical, 4)
                    ForEach(uniqueReceipts) { receipt in
                        ReceiptCardView(
                            id: receipt.id,
                            merchant: receipt.merchant ?? receipt.title,
                            date: receipt.date,
                            amount: receipt.amount,
                            colorScheme: colorScheme,
                            onTap: {
                                print("Receipt tapped: \(receipt.id)")
                            }
                        )
                    }
                }
            }
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

#Preview {
    ConversationSearchView()
        .environmentObject(SearchService.shared)
}
