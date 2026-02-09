import Foundation
import AVFoundation
import Combine

@MainActor
class TextToSpeechService: NSObject, ObservableObject {
    static let shared = TextToSpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private let elevenLabsService = ElevenLabsTTSService.shared
    @Published var isSpeaking = false
    var onSpeechFinished: (() -> Void)?

    // Queue for incremental speech (like ChatGPT)
    private var speechQueue: [String] = []
    private var isProcessingQueue = false

    // Use ElevenLabs first (high quality), fall back to Apple AVSpeech
    private var useElevenLabs: Bool {
        elevenLabsService.isAvailable
    }

    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        synthesizer.delegate = self

        // Observe ElevenLabs speaking state
        elevenLabsService.$isSpeaking
            .sink { [weak self] isSpeaking in
                self?.isSpeaking = isSpeaking
            }
            .store(in: &cancellables)
    }

    func speak(_ text: String, completion: (() -> Void)? = nil) {
        // Stop any current speech
        stopSpeaking()

        // Use ElevenLabs if available (high quality)
        if useElevenLabs {
            onSpeechFinished = completion
            elevenLabsService.onSpeechFinished = { [weak self] in
                self?.onSpeechFinished?()
                self?.onSpeechFinished = nil
            }
            elevenLabsService.speak(text, completion: nil)
            isSpeaking = true
            return
        }

        // Fall back to system TTS
        Task {
            do {
                try await AudioSessionCoordinator.shared.requestMode(.playback)
            } catch {
                print("❌ Failed to configure audio for TTS: \(error)")
                completion?()
                return
            }
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestAvailableVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.95
        utterance.prefersAssistiveTechnologySettings = false

        onSpeechFinished = completion
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if useElevenLabs {
            elevenLabsService.stopSpeaking()
        } else {
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
        }
        speechQueue.removeAll()
        isProcessingQueue = false
        isSpeaking = false
    }

    /// Speak text incrementally as it streams in (like ChatGPT)
    func speakIncremental(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Use ElevenLabs if available (high quality)
        if useElevenLabs {
            // Bridge ElevenLabs queue completion into our onSpeechFinished callback.
            // This is critical for voice mode UX (resume listening after the assistant finishes speaking).
            if onSpeechFinished != nil && elevenLabsService.onSpeechFinished == nil {
                elevenLabsService.onSpeechFinished = { [weak self] in
                    self?.onSpeechFinished?()
                    self?.onSpeechFinished = nil
                }
            }
            elevenLabsService.speakIncremental(trimmed)
            return
        }

        // Fall back to system TTS queue
        speechQueue.append(trimmed)

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

        for identifier in premiumVoiceIdentifiers {
            if let voice = voices.first(where: { $0.identifier == identifier }) {
                return voice
            }
        }

        if let enhanced = voices.first(where: {
            $0.language == "en-US" &&
            ($0.quality == .enhanced || $0.quality == .premium)
        }) {
            return enhanced
        }

        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension TextToSpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Only handle system TTS callbacks (ElevenLabs handles its own)
        guard !useElevenLabs else { return }

        isSpeaking = false

        if !speechQueue.isEmpty {
            processSpeechQueue()
        } else {
            isProcessingQueue = false
            onSpeechFinished?()
            onSpeechFinished = nil

            Task {
                try? await AudioSessionCoordinator.shared.requestMode(.idle)
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Only handle system TTS callbacks (ElevenLabs handles its own)
        guard !useElevenLabs else { return }

        isSpeaking = false
        speechQueue.removeAll()
        isProcessingQueue = false
        onSpeechFinished = nil

        Task {
            try? await AudioSessionCoordinator.shared.requestMode(.idle)
        }
    }
}
