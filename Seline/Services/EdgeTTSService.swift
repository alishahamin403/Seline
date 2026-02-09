import Foundation
import AVFoundation
import EdgeTTS

/// Edge-TTS Service - Free, high-quality neural TTS using Microsoft Edge voices
/// No API key required, 400+ voices, very human-like quality
/// Falls back to Apple AVSpeech if Edge-TTS fails
@MainActor
class EdgeTTSService: ObservableObject {
    static let shared = EdgeTTSService()

    // Voice configuration
    private let maleVoice = "en-US-GuyNeural"
    private let femaleVoice = "en-US-JennyNeural"

    @Published var isSpeaking = false
    @Published var isStreaming = false
    @Published var selectedVoiceGender: VoiceGender = .male
    var onSpeechFinished: (() -> Void)?

    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: EdgeAudioPlayerDelegate?
    private var currentTask: Task<Void, Never>?
    private var speechQueue: [String] = []
    private var isProcessingQueue = false

    // Fallback: Apple AVSpeech synthesizer
    private let fallbackSynthesizer = AVSpeechSynthesizer()
    private var fallbackDelegate: FallbackSpeechDelegate?

    // Track if Edge-TTS has been working
    private var edgeTTSHasFailed = false
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 2

    enum VoiceGender: String, Codable {
        case male
        case female
    }

    /// Always available - uses Apple TTS as fallback
    var isAvailable: Bool { true }

    private init() {
        loadVoicePreference()
    }

    // MARK: - Voice Selection

    private var currentVoiceId: String {
        selectedVoiceGender == .male ? maleVoice : femaleVoice
    }

    private func loadVoicePreference() {
        if let savedGender = UserDefaults.standard.string(forKey: "edgetts_voice_gender"),
           let gender = VoiceGender(rawValue: savedGender) {
            selectedVoiceGender = gender
        }
    }

    func setVoice(gender: VoiceGender) {
        selectedVoiceGender = gender
        UserDefaults.standard.set(gender.rawValue, forKey: "edgetts_voice_gender")
        print("🎙️ Edge-TTS voice changed to: \(gender.rawValue) (\(currentVoiceId))")
    }

    // MARK: - TTS Methods

    /// Speak text using Edge-TTS (falls back to Apple TTS on failure)
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        stopSpeaking()
        // Only overwrite onSpeechFinished if a new completion is provided
        if let completion = completion {
            onSpeechFinished = completion
        }

        currentTask = Task {
            await speakText(text)
        }
    }

    /// Speak text incrementally (for streaming)
    func speakIncremental(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSpeaking = true  // Signal immediately so voice mode sees TTS is active
        speechQueue.append(trimmed)

        if !isProcessingQueue {
            processSpeechQueue()
        }
    }

    private func processSpeechQueue() {
        guard !speechQueue.isEmpty else {
            isProcessingQueue = false
            if !isSpeaking {
                onSpeechFinished?()
                onSpeechFinished = nil
                Task {
                    try? await AudioSessionCoordinator.shared.requestMode(.idle)
                }
            }
            return
        }

        isProcessingQueue = true
        isSpeaking = true  // Set immediately so callers know speech is pending
        let textToSpeak = speechQueue.removeFirst()

        currentTask = Task {
            await speakText(textToSpeak, isIncremental: true)
        }
    }

    private func speakText(_ text: String, isIncremental: Bool = false) async {
        guard !text.isEmpty else { return }

        isSpeaking = true
        isStreaming = true

        do {
            try await AudioSessionCoordinator.shared.requestMode(.playback)
        } catch {
            print("❌ Failed to configure audio for TTS: \(error)")
        }

        // Try Edge-TTS first (unless it's been failing consistently)
        if !edgeTTSHasFailed || consecutiveFailures < maxConsecutiveFailures {
            do {
                try await speakWithEdgeTTS(text)
                consecutiveFailures = 0 // Reset on success
                edgeTTSHasFailed = false
                handleSpeakCompletion(isIncremental: isIncremental)
                return
            } catch {
                print("⚠️ Edge-TTS failed, falling back to Apple TTS: \(error)")
                consecutiveFailures += 1
                if consecutiveFailures >= maxConsecutiveFailures {
                    edgeTTSHasFailed = true
                    print("⚠️ Edge-TTS disabled after \(maxConsecutiveFailures) consecutive failures")
                }
            }
        }

        // Fallback: Apple AVSpeech
        print("🔊 Using Apple TTS fallback")
        await speakWithAppleTTS(text)
        handleSpeakCompletion(isIncremental: isIncremental)
    }

    private func handleSpeakCompletion(isIncremental: Bool) {
        if isIncremental {
            isSpeaking = false
            isStreaming = false
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
        } else {
            isSpeaking = false
            isStreaming = false
            isProcessingQueue = false
            if speechQueue.isEmpty {
                onSpeechFinished?()
                onSpeechFinished = nil
                Task {
                    try? await AudioSessionCoordinator.shared.requestMode(.idle)
                }
            }
        }
    }

    // MARK: - Edge-TTS Implementation

    private func speakWithEdgeTTS(_ text: String) async throws {
        print("🔊 Edge-TTS: \"\(text.prefix(50))...\" (voice: \(currentVoiceId))")

        let config = Configure(
            voice: currentVoiceId,
            rate: "+0%",
            pitch: "+0Hz",
            volume: "+0%"
        )
        let tts = EdgeTTS(config: config)

        let tempDir = FileManager.default.temporaryDirectory
        let audioFile = tempDir.appendingPathComponent("edgetts_\(UUID().uuidString).mp3")

        // Add timeout - Edge-TTS should respond within 3 seconds (fast fallback to Apple TTS)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await tts.ttsPromise(text: text, audioPath: audioFile.path)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3s timeout
                throw EdgeTTSError.timeout
            }

            // Wait for first completion (success or timeout)
            try await group.next()
            group.cancelAll()
        }

        print("✅ Edge-TTS generated audio")

        let audioData = try Data(contentsOf: audioFile)
        guard !audioData.isEmpty else {
            throw EdgeTTSError.emptyAudio
        }

        try await playAudio(data: audioData)
        try? FileManager.default.removeItem(at: audioFile)
    }

    enum EdgeTTSError: Error {
        case timeout
        case emptyAudio
    }

    // MARK: - Apple TTS Fallback

    private func speakWithAppleTTS(_ text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let utterance = AVSpeechUtterance(string: text)

            // Select best available voice
            let voices = AVSpeechSynthesisVoice.speechVoices()
            let premiumIds = [
                "com.apple.voice.premium.en-US.Reed",
                "com.apple.voice.premium.en-US.Aaron",
                "com.apple.voice.enhanced.en-US.Alex",
                "com.apple.voice.enhanced.en-US.Tom"
            ]

            var selectedVoice: AVSpeechSynthesisVoice? = nil
            for id in premiumIds {
                if let voice = voices.first(where: { $0.identifier == id }) {
                    selectedVoice = voice
                    break
                }
            }
            if selectedVoice == nil {
                selectedVoice = voices.first(where: { $0.language == "en-US" && $0.quality == .enhanced })
            }
            if selectedVoice == nil {
                selectedVoice = AVSpeechSynthesisVoice(language: "en-US")
            }

            utterance.voice = selectedVoice
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
            utterance.pitchMultiplier = 1.0
            utterance.volume = 0.95

            let delegate = FallbackSpeechDelegate {
                continuation.resume()
            }
            self.fallbackDelegate = delegate
            self.fallbackSynthesizer.delegate = delegate
            self.fallbackSynthesizer.speak(utterance)
        }
    }

    // MARK: - Audio Playback

    private func playAudio(data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let player = try AVAudioPlayer(data: data)
                let delegate = EdgeAudioPlayerDelegate {
                    continuation.resume()
                }
                player.delegate = delegate
                self.audioPlayerDelegate = delegate
                self.audioPlayer = player
                player.play()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func stopSpeaking() {
        currentTask?.cancel()
        currentTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        audioPlayerDelegate = nil
        fallbackSynthesizer.stopSpeaking(at: .immediate)
        fallbackDelegate = nil
        speechQueue.removeAll()
        isProcessingQueue = false
        isSpeaking = false
        isStreaming = false
    }
}

// MARK: - Delegates

private class EdgeAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

private class FallbackSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish()
    }
}
