import Foundation
import AVFoundation
import Combine

@MainActor
class TextToSpeechService: NSObject, ObservableObject {
    static let shared = TextToSpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    var onSpeechFinished: (() -> Void)?

    // Queue for incremental speech (like ChatGPT)
    private var speechQueue: [String] = []
    private var isProcessingQueue = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: (() -> Void)? = nil) {
        // Stop any current speech
        stopSpeaking()

        // Request playback mode from coordinator
        Task {
            do {
                try await AudioSessionCoordinator.shared.requestMode(.playback)
            } catch {
                print("❌ Failed to configure audio for TTS: \(error)")
                completion?()
                return
            }
        }

        // Create speech utterance
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestAvailableVoice()

        // Natural speech parameters for human-like delivery
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.95
        utterance.prefersAssistiveTechnologySettings = false

        onSpeechFinished = completion
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speechQueue.removeAll()
        isProcessingQueue = false
        isSpeaking = false
    }

    /// Speak text incrementally as it streams in (like ChatGPT)
    func speakIncremental(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Add to queue
        speechQueue.append(trimmed)

        // Start processing if not already
        if !isProcessingQueue {
            processSpeechQueue()
        }
    }

    private func processSpeechQueue() {
        guard !speechQueue.isEmpty else {
            isProcessingQueue = false
            return
        }

        isProcessingQueue = true

        // Configure audio session if not already active
        if !isSpeaking {
            Task {
                do {
                    try await AudioSessionCoordinator.shared.requestMode(.playback)
                } catch {
                    print("❌ Failed to configure audio session: \(error)")
                }
            }
        }

        let textToSpeak = speechQueue.removeFirst()
        let utterance = AVSpeechUtterance(string: textToSpeak)
        utterance.voice = bestAvailableVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.95
        utterance.prefersAssistiveTechnologySettings = false

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // MARK: - Voice Selection

    private func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let premiumVoiceIdentifiers = [
            "com.apple.voice.premium.en-US.Reed",
            "com.apple.voice.premium.en-US.Aaron",
            "com.apple.eloquence.en-US.Reed",
            "com.apple.eloquence.en-US.Rocko",
            "com.apple.voice.enhanced.en-US.Alex",
            "com.apple.voice.enhanced.en-US.Tom"
        ]

        // First try premium/enhanced voices
        for identifier in premiumVoiceIdentifiers {
            if let voice = voices.first(where: { $0.identifier == identifier }) {
                return voice
            }
        }

        // Try enhanced quality voices
        if let enhanced = voices.first(where: {
            $0.language == "en-US" &&
            ($0.quality == .enhanced || $0.quality == .premium)
        }) {
            return enhanced
        }

        // Fallback to best available US English voice
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension TextToSpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false

        // Continue processing queue if there's more
        if !speechQueue.isEmpty {
            processSpeechQueue()
        } else {
            isProcessingQueue = false
            // Only call completion when queue is empty
            onSpeechFinished?()
            onSpeechFinished = nil

            // Return to idle mode via coordinator
            Task {
                try? await AudioSessionCoordinator.shared.requestMode(.idle)
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        speechQueue.removeAll()
        isProcessingQueue = false
        onSpeechFinished = nil

        // Return to idle mode via coordinator
        Task {
            try? await AudioSessionCoordinator.shared.requestMode(.idle)
        }
    }
}
