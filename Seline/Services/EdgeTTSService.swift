import Foundation
import AVFoundation
import EdgeTTS

/// Edge-TTS Service - Free, high-quality neural TTS using Microsoft Edge voices
/// No API key required, 400+ voices, very human-like quality
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

    enum VoiceGender: String, Codable {
        case male
        case female
    }

    /// Always available - no API key needed
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

    /// Speak text using Edge-TTS
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        stopSpeaking()
        onSpeechFinished = completion

        currentTask = Task {
            await speakText(text)
        }
    }

    /// Speak text incrementally (for streaming)
    func speakIncremental(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

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
        let textToSpeak = speechQueue.removeFirst()

        currentTask = Task {
            await speakText(textToSpeak, isIncremental: true)
        }
    }

    private func speakText(_ text: String, isIncremental: Bool = false) async {
        guard !text.isEmpty else { return }

        print("🔊 Edge-TTS Request: \"\(text.prefix(50))...\" (voice: \(currentVoiceId))")

        isSpeaking = true
        isStreaming = true

        do {
            // Request playback mode
            try await AudioSessionCoordinator.shared.requestMode(.playback)

            // Create Edge-TTS instance with current voice
            let config = Configure(
                voice: currentVoiceId,
                rate: "+0%",
                pitch: "+0Hz",
                volume: "+0%"
            )
            let tts = EdgeTTS(config: config)

            // Generate audio to temp file
            let tempDir = FileManager.default.temporaryDirectory
            let audioFile = tempDir.appendingPathComponent("edgetts_\(UUID().uuidString).mp3")
            let audioPath = audioFile.path

            try await tts.ttsPromise(text: text, audioPath: audioPath)

            print("✅ Edge-TTS generated audio at: \(audioPath)")

            // Play the audio file
            let audioData = try Data(contentsOf: audioFile)
            try await playAudio(data: audioData)

            // Clean up temp file
            try? FileManager.default.removeItem(at: audioFile)

            // Continue queue if incremental
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
        } catch {
            print("❌ Edge-TTS error: \(error)")
            isSpeaking = false
            isStreaming = false
            isProcessingQueue = false
            speechQueue.removeAll()
            onSpeechFinished?()
            onSpeechFinished = nil
            Task {
                try? await AudioSessionCoordinator.shared.requestMode(.idle)
            }
        }
    }

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
        speechQueue.removeAll()
        isProcessingQueue = false
        isSpeaking = false
        isStreaming = false
    }
}

// Helper class for AVAudioPlayer delegate
private class EdgeAudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
