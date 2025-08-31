//
//  VoiceChatSearchView.swift
//  Seline
//
//  Created by Assistant on 2025-08-31.
//

import SwiftUI
import AVFoundation

struct VoiceChatSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var voiceService = VoiceRecordingService.shared
    @State private var isSpeaking = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var conversationHistory: [ConversationEntry] = []
    @State private var lastResponse: String = ""
    @State private var isBusy = false
    @State private var hasSpokenChunk = false
    
    private let synthesizer = AVSpeechSynthesizer()
    @State private var speechDelegate: SpeechDelegate?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                header
                transcriptSection
                responseSection
                Spacer()
                micControl
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .navigationBarHidden(true)
            .background(DesignSystem.Colors.surface.ignoresSafeArea())
        }
        .onAppear {
            speechDelegate = SpeechDelegate(isSpeaking: $isSpeaking)
            synthesizer.delegate = speechDelegate
            Task { await voiceService.requestPermissions() }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { showingError = false }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: UI Sections
    private var header: some View {
        HStack {
            Button("Cancel") {
                stopAll()
                dismiss()
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundColor(DesignSystem.Colors.textSecondary)
            Spacer()
            Text("Voice Search")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            Spacer()
            // Placeholder for right side
            Text(" ")
                .font(.system(size: 16))
                .opacity(0)
        }
    }
    
    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You said")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            Text(voiceService.recordedText.isEmpty ? "Tap the mic to speak" : voiceService.recordedText)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(12)
        }
    }
    
    private var responseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Assistant")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Spacer()
                if isBusy { ProgressView().scaleEffect(0.8).tint(DesignSystem.Colors.accent) }
            }
            Text(lastResponse.isEmpty ? "The response will appear here." : lastResponse)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(DesignSystem.Colors.surfaceSecondary)
                .cornerRadius(12)
        }
    }
    
    private var micControl: some View {
        VStack(spacing: 16) {
            Button(action: toggleRecording) {
                ZStack {
                    Circle()
                        .fill(voiceService.isRecording ? Color.red.gradient : (colorScheme == .dark ? DesignSystem.Colors.surfaceSecondary.gradient : Color.black.gradient))
                        .frame(width: 120, height: 120)
                        .scaleEffect(voiceService.isRecording ? 1.08 : 1.0)
                        .animation(.easeInOut(duration: 0.25), value: voiceService.isRecording)
                    
                    Image(systemName: voiceService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            .disabled(isBusy)
            
            if isSpeaking {
                Button(action: stopSpeaking) {
                    Label("Stop Speaking", systemImage: "speaker.slash.fill")
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.accent)
            }
        }
    }
    
    // MARK: Actions
    private func toggleRecording() {
        if voiceService.isRecording {
            voiceService.stopRecording(userInitiated: true)
            handleFinalTranscript()
        } else {
            // stop speaking if currently speaking
            stopSpeaking()
            Task { await voiceService.startRecording() }
        }
    }
    
    private func handleFinalTranscript() {
        let query = voiceService.recordedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        askAssistant(query: query)
    }
    
    private func askAssistant(query: String) {
        // Append user entry
        let userEntry = ConversationEntry(type: .user, content: query)
        conversationHistory.append(userEntry)
        isBusy = true
        
        Task {
            do {
                var accumulated = ""
                hasSpokenChunk = false
                try await OpenAIService.shared.streamChatResponse(
                    systemPrompt: "You are a concise assistant. Keep spoken answers brief.",
                    userPrompt: query,
                    temperature: 0.6
                ) { delta in
                    accumulated += delta
                    DispatchQueue.main.async {
                        lastResponse = accumulated
                        if delta.contains(".") || delta.contains("? ") || delta.contains("! ") {
                            // speak in chunks when a sentence likely completes
                            speak(delta)
                            hasSpokenChunk = true
                        }
                    }
                }
                await MainActor.run {
                    let assistantEntry = ConversationEntry(type: .assistant, content: accumulated)
                    conversationHistory.append(assistantEntry)
                    // If no chunk triggered speech during stream, speak the final answer
                    if !hasSpokenChunk && !accumulated.isEmpty {
                        speak(accumulated)
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            await MainActor.run { isBusy = false }
        }
    }
    
    private func speak(_ text: String) {
        stopSpeaking()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch { }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        synthesizer.speak(utterance)
        isSpeaking = true
    }
    
    private func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }
    
    private func stopAll() {
        voiceService.cancelRecording()
        stopSpeaking()
    }
}

// MARK: - Speech Delegate Wrapper
private class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    @Binding var isSpeaking: Bool
    init(isSpeaking: Binding<Bool>) { self._isSpeaking = isSpeaking }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { isSpeaking = false }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { isSpeaking = false }
}


