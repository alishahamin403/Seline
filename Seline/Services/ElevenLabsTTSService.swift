import Foundation
import AVFoundation

/// ElevenLabs Text-to-Speech Service
/// Provides high-quality, human-like voices for TTS
@MainActor
class ElevenLabsTTSService: ObservableObject {
    static let shared = ElevenLabsTTSService()
    
    // ElevenLabs API configuration
    private let apiKey: String
    private let baseURL = "https://api.elevenlabs.io/v1"
    
    // Voice IDs - You can get these from ElevenLabs dashboard
    // Default voices (you'll need to replace with actual voice IDs from your ElevenLabs account)
    struct Voice {
        let id: String
        let name: String
        let gender: VoiceGender
    }
    
    enum VoiceGender: String, Codable {
        case male
        case female
    }
    
    // Default voice IDs - ElevenLabs premade voices (available to all accounts)
    // To get more voice IDs: https://elevenlabs.io/app/voice-library
    private let defaultMaleVoice = Voice(id: "pNInz6obpgDQGcFmaJgB", name: "Adam", gender: .male)
    private let defaultFemaleVoice = Voice(id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", gender: .female)
    
    @Published var isSpeaking = false
    @Published var isStreaming = false
    var onSpeechFinished: (() -> Void)?
    
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: AudioPlayerDelegate?
    private var currentTask: Task<Void, Never>?
    private var speechQueue: [String] = []
    private var isProcessingQueue = false
    
    private init() {
        // Get API key from Config
        self.apiKey = Config.elevenLabsAPIKey
        
        // Load saved voice preference
        loadVoicePreference()
    }
    
    // MARK: - Voice Selection
    
    @Published var selectedVoiceGender: VoiceGender = .male
    @Published var selectedVoiceId: String = ""
    
    private func loadVoicePreference() {
        if let savedGender = UserDefaults.standard.string(forKey: "elevenlabs_voice_gender"),
           let gender = VoiceGender(rawValue: savedGender) {
            selectedVoiceGender = gender
        }
        
        if let savedVoiceId = UserDefaults.standard.string(forKey: "elevenlabs_voice_id"),
           !savedVoiceId.isEmpty {
            // Migration: Reset if the old incorrect voice ID was saved
            let oldIncorrectMaleId = "pNInz6obpgueM0ndtTCm"
            if savedVoiceId == oldIncorrectMaleId {
                // Reset to correct default
                selectedVoiceId = selectedVoiceGender == .male ? defaultMaleVoice.id : defaultFemaleVoice.id
                UserDefaults.standard.set(selectedVoiceId, forKey: "elevenlabs_voice_id")
                print("🔧 Migrated from incorrect voice ID to: \(selectedVoiceId)")
            } else {
                selectedVoiceId = savedVoiceId
            }
        } else {
            // Use default based on gender
            selectedVoiceId = selectedVoiceGender == .male ? defaultMaleVoice.id : defaultFemaleVoice.id
        }
    }
    
    func setVoice(gender: VoiceGender, voiceId: String? = nil) {
        selectedVoiceGender = gender
        if let voiceId = voiceId {
            selectedVoiceId = voiceId
        } else {
            // Use default for gender
            selectedVoiceId = gender == .male ? defaultMaleVoice.id : defaultFemaleVoice.id
        }
        
        // Save preference
        UserDefaults.standard.set(gender.rawValue, forKey: "elevenlabs_voice_gender")
        UserDefaults.standard.set(selectedVoiceId, forKey: "elevenlabs_voice_id")
        
        print("🎙️ Voice changed to: \(gender.rawValue) (ID: \(selectedVoiceId))")
    }
    
    // MARK: - TTS Methods
    
    /// Check if ElevenLabs is configured and available
    var isAvailable: Bool {
        return !apiKey.isEmpty && apiKey != "YOUR_ELEVENLABS_API_KEY_HERE"
    }
    
    /// Speak text using ElevenLabs
    func speak(_ text: String, completion: (() -> Void)? = nil) {
        guard isAvailable else {
            print("⚠️ ElevenLabs not configured, falling back to system TTS")
            completion?()
            return
        }
        
        stopSpeaking()
        onSpeechFinished = completion
        
        currentTask = Task {
            await speakText(text)
        }
    }
    
    /// Speak text incrementally (for streaming)
    func speakIncremental(_ text: String) {
        guard isAvailable else { return }
        
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
            // Call completion when queue is empty and not speaking
            if !isSpeaking {
                onSpeechFinished?()
                onSpeechFinished = nil
                // Return to idle mode
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
        
        print("🔊 TTS Request: \"\(text.prefix(50))...\" (voice: \(selectedVoiceId), incremental: \(isIncremental))")
        
        isSpeaking = true
        isStreaming = true
        
        do {
            // Request playback mode from coordinator (always request, even if already in playback mode)
            // This ensures audio session is active for each new response
            try await AudioSessionCoordinator.shared.requestMode(.playback)

            // Build API request
            guard let url = URL(string: "\(baseURL)/text-to-speech/\(selectedVoiceId)/stream") else {
                print("❌ Invalid ElevenLabs API URL")
                isSpeaking = false
                isStreaming = false
                onSpeechFinished?()
                return
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            // Request body
            let requestBody: [String: Any] = [
                "text": text,
                "model_id": "eleven_turbo_v2_5", // Fast, high-quality model
                "voice_settings": [
                    "stability": 0.5,
                    "similarity_boost": 0.75,
                    "style": 0.0,
                    "use_speaker_boost": true
                ]
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Make request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                if let httpResponse = response as? HTTPURLResponse {
                    print("❌ ElevenLabs API error: HTTP \(httpResponse.statusCode)")
                    if let errorBody = String(data: data, encoding: .utf8) {
                        print("   Response: \(errorBody)")
                    }
                }
                isSpeaking = false
                isStreaming = false
                onSpeechFinished?()
                return
            }
            
            print("✅ TTS Response: \(data.count) bytes audio received")
            
            // Play audio and wait for it to finish
            try await playAudio(data: data)
            
            // Continue queue if incremental
            if isIncremental {
                await MainActor.run {
                    isSpeaking = false
                    isStreaming = false
                    // Continue processing queue if there's more
                    if !speechQueue.isEmpty {
                        processSpeechQueue()
                    } else {
                        // Queue is empty - reset flag so future calls work!
                        isProcessingQueue = false
                        onSpeechFinished?()
                        onSpeechFinished = nil
                        // Return to idle mode when completely done
                        Task {
                            try? await AudioSessionCoordinator.shared.requestMode(.idle)
                        }
                    }
                }
            } else {
                await MainActor.run {
                    isSpeaking = false
                    isStreaming = false
                    isProcessingQueue = false // Reset flag for non-incremental too
                    // Only call completion when queue is completely empty
                    if speechQueue.isEmpty {
                        onSpeechFinished?()
                        onSpeechFinished = nil
                        // Return to idle mode when completely done
                        Task {
                            try? await AudioSessionCoordinator.shared.requestMode(.idle)
                        }
                    }
                }
            }

            } catch {
                print("❌ ElevenLabs TTS error: \(error)")
                await MainActor.run {
                    isSpeaking = false
                    isStreaming = false
                    isProcessingQueue = false // Reset flag on error so future calls work!
                    speechQueue.removeAll() // Clear queue on error
                    onSpeechFinished?()
                    onSpeechFinished = nil
                    // Return to idle mode on error
                    Task {
                        try? await AudioSessionCoordinator.shared.requestMode(.idle)
                    }
                }
            }
        }
    
    private func playAudio(data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let player = try AVAudioPlayer(data: data)
                let delegate = AudioPlayerDelegate { [weak self] in
                    self?.isSpeaking = false
                    self?.isStreaming = false
                    continuation.resume()
                }
                player.delegate = delegate
                // Keep reference to delegate to prevent deallocation
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
    
    // MARK: - Voice List
    
    /// Fetch available voices from ElevenLabs
    func fetchAvailableVoices() async throws -> [Voice] {
        guard isAvailable else {
            throw NSError(domain: "ElevenLabsTTS", code: 1, userInfo: [NSLocalizedDescriptionKey: "ElevenLabs not configured"])
        }

        guard let url = URL(string: "\(baseURL)/voices") else {
            throw NSError(domain: "ElevenLabsTTS", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid voices API URL"])
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "ElevenLabsTTS", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch voices"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let voicesArray = json["voices"] as? [[String: Any]] else {
            throw NSError(domain: "ElevenLabsTTS", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
        }
        
        var voices: [Voice] = []
        for voiceDict in voicesArray {
            if let id = voiceDict["voice_id"] as? String,
               let name = voiceDict["name"] as? String,
               let labels = voiceDict["labels"] as? [String: String],
               let genderStr = labels["gender"]?.lowercased(),
               let gender = VoiceGender(rawValue: genderStr) {
                voices.append(Voice(id: id, name: name, gender: gender))
            }
        }
        
        return voices
    }
}

// Helper class for AVAudioPlayer delegate
private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    
    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}
