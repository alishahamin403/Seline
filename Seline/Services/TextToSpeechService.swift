import Foundation
import AVFoundation
import Combine

@MainActor
class TextToSpeechService: NSObject, ObservableObject {
    static let shared = TextToSpeechService()
    
    private let synthesizer = AVSpeechSynthesizer()
    private let edgeTTSService = EdgeTTSService.shared
    @Published var isSpeaking = false
    var onSpeechFinished: (() -> Void)?

    // Queue for incremental speech (like ChatGPT)
    private var speechQueue: [String] = []
    private var isProcessingQueue = false

    // Use EdgeTTS first (free, high quality), fall back to Apple AVSpeech
    private var useEdgeTTS: Bool {
        edgeTTSService.isAvailable
    }

    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()
        synthesizer.delegate = self

        // Observe EdgeTTS speaking state
        edgeTTSService.$isSpeaking
            .sink { [weak self] isSpeaking in
                self?.isSpeaking = isSpeaking
            }
            .store(in: &cancellables)
    }
    
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        // Stop any current speech
        stopSpeaking()

        // Use EdgeTTS if available (free, high quality)
        if useEdgeTTS {
            onSpeechFinished = completion
            edgeTTSService.onSpeechFinished = { [weak self] in
                self?.onSpeechFinished?()
                self?.onSpeechFinished = nil
            }
            edgeTTSService.speak(text, completion: nil)
            isSpeaking = true
            return
        }

        // Fall back to system TTS
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

        // Use enhanced/premium voices for more human-like quality
        let voices = AVSpeechSynthesisVoice.speechVoices()

        // Priority order: Enhanced > Premium > Compact voices
        // Look for high-quality voices
        let premiumVoiceIdentifiers = [
            "com.apple.voice.premium.en-US.Reed",
            "com.apple.voice.premium.en-US.Aaron",
            "com.apple.eloquence.en-US.Reed",
            "com.apple.eloquence.en-US.Rocko",
            "com.apple.voice.enhanced.en-US.Alex",
            "com.apple.voice.enhanced.en-US.Tom"
        ]

        var selectedVoice: AVSpeechSynthesisVoice? = nil

        // First try premium/enhanced voices
        for identifier in premiumVoiceIdentifiers {
            if let voice = voices.first(where: { $0.identifier == identifier }) {
                selectedVoice = voice
                print("🎙️ Using voice: \(identifier)")
                break
            }
        }

        // If no premium voice, try enhanced quality voices
        if selectedVoice == nil {
            selectedVoice = voices.first(where: {
                $0.language == "en-US" &&
                ($0.quality == .enhanced || $0.quality == .premium)
            })
        }

        // Fallback to best available US English voice
        if selectedVoice == nil {
            selectedVoice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.voice = selectedVoice

        // Natural speech parameters for human-like delivery
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05 // Slightly faster for more natural conversation
        utterance.pitchMultiplier = 1.0 // Natural pitch
        utterance.volume = 0.95 // Slightly softer for pleasant listening
        utterance.prefersAssistiveTechnologySettings = false

        onSpeechFinished = completion
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    
    func stopSpeaking() {
        if useEdgeTTS {
            edgeTTSService.stopSpeaking()
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
        
        // Use EdgeTTS if available (free, high quality)
        if useEdgeTTS {
            // Bridge EdgeTTS queue completion into our onSpeechFinished callback.
            // This is critical for voice mode UX (resume listening after the assistant finishes speaking).
            if onSpeechFinished != nil && edgeTTSService.onSpeechFinished == nil {
                edgeTTSService.onSpeechFinished = { [weak self] in
                    self?.onSpeechFinished?()
                    self?.onSpeechFinished = nil
                }
            }
            edgeTTSService.speakIncremental(trimmed)
            return
        }
        
        // Fall back to system TTS queue
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
        
        // Use the same voice selection logic
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let premiumVoiceIdentifiers = [
            "com.apple.voice.premium.en-US.Reed",
            "com.apple.voice.premium.en-US.Aaron",
            "com.apple.eloquence.en-US.Reed",
            "com.apple.eloquence.en-US.Rocko",
            "com.apple.voice.enhanced.en-US.Alex",
            "com.apple.voice.enhanced.en-US.Tom"
        ]
        
        var selectedVoice: AVSpeechSynthesisVoice? = nil
        for identifier in premiumVoiceIdentifiers {
            if let voice = voices.first(where: { $0.identifier == identifier }) {
                selectedVoice = voice
                break
            }
        }
        
        if selectedVoice == nil {
            selectedVoice = voices.first(where: {
                $0.language == "en-US" &&
                ($0.quality == .enhanced || $0.quality == .premium)
            })
        }
        
        if selectedVoice == nil {
            selectedVoice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        utterance.voice = selectedVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.95
        utterance.prefersAssistiveTechnologySettings = false
        
        isSpeaking = true
        synthesizer.speak(utterance)
    }
}

extension TextToSpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Only handle system TTS callbacks (EdgeTTS handles its own)
        guard !useEdgeTTS else { return }

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
        // Only handle system TTS callbacks (EdgeTTS handles its own)
        guard !useEdgeTTS else { return }

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
