import Foundation
import AVFoundation
import Combine

@MainActor
class TextToSpeechService: NSObject, ObservableObject {
    static let shared = TextToSpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private let piperService = PiperTTSService.shared
    @Published var isSpeaking = false
    var onSpeechFinished: (() -> Void)?

    private var speechQueue: [String] = []
    private var isProcessingQueue = false

    private var usePiper: Bool {
        piperService.isAvailable
    }

    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        synthesizer.delegate = self

        piperService.$isSpeaking
            .sink { [weak self] isSpeaking in
                if isSpeaking {
                    self?.isSpeaking = true
                }
            }
            .store(in: &cancellables)
    }

    func speak(_ text: String, completion: (() -> Void)? = nil) {
        print("🎤 TTS speak() called - usePiper: \(usePiper)")
        
        stopSpeaking()

        if usePiper {
            print("🎤 Using Piper TTS")
            onSpeechFinished = completion
            piperService.onSpeechFinished = { [weak self] in
                self?.onSpeechFinished?()
                self?.onSpeechFinished = nil
            }
            piperService.speak(text, completion: nil)
            isSpeaking = true
            return
        }

        print("🎤 Using Apple TTS")
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
        if usePiper {
            piperService.stopSpeaking()
        } else {
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
        }
        speechQueue.removeAll()
        isProcessingQueue = false
        isSpeaking = false
    }

    func speakIncremental(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        print("🎤 TTS speakIncremental() called - usePiper: \(usePiper)")

        if usePiper {
            print("🎤 Using Piper TTS (incremental)")
            if onSpeechFinished != nil && piperService.onSpeechFinished == nil {
                piperService.onSpeechFinished = { [weak self] in
                    self?.onSpeechFinished?()
                    self?.onSpeechFinished = nil
                }
            }
            piperService.speak(trimmed, completion: nil)
            return
        }

        print("🎤 Using Apple TTS (incremental)")
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
        guard !usePiper else { return }

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
        guard !usePiper else { return }

        isSpeaking = false
        speechQueue.removeAll()
        isProcessingQueue = false
        onSpeechFinished = nil

        Task {
            try? await AudioSessionCoordinator.shared.requestMode(.idle)
        }
    }
}
