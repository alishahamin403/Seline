//
//  FollowUpConversationView.swift
//  Seline
//
//  Created by Claude on 2025-08-26.
//

import SwiftUI

struct FollowUpConversationView: View {
    @Environment(\.dismiss) private var dismiss
    let initialContext: String
    let initialQuery: String
    let searchType: SearchType
    
    @State private var conversationHistory: [ConversationEntry] = []
    @State private var followUpText: String = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage: String = ""
        @FocusState private var isTextFieldFocused: Bool
    @ObservedObject var voiceRecordingService = VoiceRecordingService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            // Conversation history
            conversationScrollView
            
            // Follow-up input
            followUpInputSection
        }
        .background(DesignSystem.Colors.surface)
        .onAppear {
            setupInitialConversation()
            isTextFieldFocused = true
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text("Follow-up Chat")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text(searchType.displayName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                Button(action: {
                    clearConversation()
                }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(DesignSystem.Colors.surface)
            
            Divider()
                .background(DesignSystem.Colors.border)
        }
    }
    
    // MARK: - Conversation Scroll View
    
    private var conversationScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(conversationHistory) { entry in
                        ConversationBubble(entry: entry)
                            .id(entry.id)
                    }
                    
                    if isLoading {
                        loadingIndicator
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onChange(of: conversationHistory.count) { _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    if let lastEntry = conversationHistory.last {
                        proxy.scrollTo(lastEntry.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: isLoading) { loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var loadingIndicator: some View {
        HStack {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(DesignSystem.Colors.accent)
                
                Text("AI is thinking...")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(DesignSystem.Colors.surfaceSecondary)
            )
            
            Spacer()
        }
        .id("loading")
    }
    
    // MARK: - Follow-up Input Section
    
    private var followUpInputSection: some View {
        VStack(spacing: 16) {
            Divider()
                .background(DesignSystem.Colors.border)
            
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left")
                        .font(.title3)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    TextField("Ask a follow-up question...", text: $followUpText, axis: .vertical)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .textFieldStyle(PlainTextFieldStyle())
                        .focused($isTextFieldFocused)
                        .lineLimit(1...4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(DesignSystem.Colors.surfaceSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(isTextFieldFocused ? DesignSystem.Colors.accent.opacity(0.5) : DesignSystem.Colors.border, lineWidth: 1)
                        )
                )
                
                Button(action: sendFollowUp) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(followUpText.isEmpty ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.accent)
                        )
                }
                .disabled(followUpText.isEmpty || isLoading)
                .animation(.easeInOut(duration: 0.2), value: followUpText.isEmpty)

                Button(action: toggleVoiceRecording) {
                    Image(systemName: voiceRecordingService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(voiceRecordingService.isRecording ? Color.red : DesignSystem.Colors.accent)
                        )
                }
                .disabled(isLoading) // Disable while AI is thinking
                .animation(.easeInOut(duration: 0.2), value: voiceRecordingService.isRecording)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(DesignSystem.Colors.surface)
    }
    
    // MARK: - Helper Methods
    
    private func setupInitialConversation() {
        // Add the initial context as the first entry
        let contextEntry = ConversationEntry(
            type: searchType == .email ? .emailSummary : .assistant,
            content: initialContext
        )
        conversationHistory.append(contextEntry)
    }
    
    private func sendFollowUp() {
        let query = followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        // Add user's question to history
        let userEntry = ConversationEntry(type: .user, content: query)
        conversationHistory.append(userEntry)
        
        // Clear input and start loading
        followUpText = ""
        isLoading = true
        
        Task {
            do {
                let response = try await IntelligentSearchService.shared.generateFollowUpResponse(
                    query: query,
                    context: initialContext,
                    conversationHistory: conversationHistory
                )
                
                await MainActor.run {
                    let assistantEntry = ConversationEntry(type: .assistant, content: response)
                    conversationHistory.append(assistantEntry)
                    isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to get AI response: \(error.localizedDescription)"
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func clearConversation() {
        conversationHistory = []
        setupInitialConversation()
    }

    private func toggleVoiceRecording() {
        if voiceRecordingService.isRecording {
            voiceRecordingService.stopRecording(userInitiated: true)
        } else {
            // Dismiss keyboard before starting recording
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            
            voiceRecordingService.startOneShotTranscription(for: .search) { transcript in
                if let text = transcript, !text.isEmpty {
                    followUpText = text // Populate the text field with the transcription
                    sendFollowUp() // Automatically send the follow-up question
                }
            }
        }
    }
}

// MARK: - Conversation Bubble

struct ConversationBubble: View {
    let entry: ConversationEntry
    
    var body: some View {
        HStack {
            if entry.type == .user {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: entry.type == .user ? .trailing : .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if entry.type != .user {
                        Image(systemName: bubbleIcon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(bubbleColor)
                    }
                    
                    Text(bubbleTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(bubbleColor)
                    
                    if entry.type == .user {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
                
                Text(entry.content)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(entry.type == .user ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            
            if entry.type != .user {
                Spacer(minLength: 50)
            }
        }
    }
    
    private var bubbleIcon: String {
        switch entry.type {
        case .user:
            return "person.fill"
        case .assistant:
            return "brain.head.profile"
        case .emailSummary:
            return "envelope.badge.fill"
        }
    }
    
    private var bubbleTitle: String {
        switch entry.type {
        case .user:
            return "You"
        case .assistant:
            return "AI Assistant"
        case .emailSummary:
            return "Email Summary"
        }
    }
    
    private var bubbleColor: Color {
        switch entry.type {
        case .user:
            return DesignSystem.Colors.textSecondary
        case .assistant:
            return DesignSystem.Colors.accent
        case .emailSummary:
            return .blue
        }
    }
    
    private var backgroundColor: Color {
        switch entry.type {
        case .user:
            return DesignSystem.Colors.accent.opacity(0.1)
        case .assistant, .emailSummary:
            return DesignSystem.Colors.surfaceSecondary
        }
    }
    
    private var borderColor: Color {
        switch entry.type {
        case .user:
            return DesignSystem.Colors.accent.opacity(0.3)
        case .assistant:
            return DesignSystem.Colors.accent.opacity(0.2)
        case .emailSummary:
            return Color.blue.opacity(0.2)
        }
    }
}

// MARK: - Preview

struct FollowUpConversationView_Previews: PreviewProvider {
    static var previews: some View {
        FollowUpConversationView(
            initialContext: "Based on your recent emails, the main themes are meeting coordination and project updates. Several messages discuss upcoming deadlines and team collaboration requirements.",
            initialQuery: "summarize important emails",
            searchType: .email
        )
    }
}