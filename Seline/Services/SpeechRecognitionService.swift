import Foundation
import Speech
import AVFoundation

@MainActor
class SpeechRecognitionService: ObservableObject {
    static let shared = SpeechRecognitionService()

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    @Published var audioLevel: Float = -160.0 // Public audio power level for UI (VoiceOrbView)

    var onTranscriptionUpdate: ((String) -> Void)?
    var onAutoSend: (() -> Void)? // Callback when silence detected and should auto-send

    // Silence detection
    private var lastSpeechTime: Date?
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5 // 1.5 seconds of silence
    private var hasAutoSent = false

    // Audio level detection
    private var currentAudioPower: Float = -160.0
    private let speechPowerThreshold: Float = -70.0 // dB threshold for speech
    private var hasSpeechActivity = false

    enum SpeechRecognitionError: LocalizedError {
        case permissionDenied
        case permissionRestricted
        case recognizerUnavailable
        case audioSessionFailed(Error)
        case invalidAudioFormat(String)
        case audioEngineStartFailed
        case audioEnginePrepareFailed(Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission denied. Please enable in Settings."
            case .permissionRestricted:
                return "Microphone access is restricted."
            case .recognizerUnavailable:
                return "Speech recognition is not available."
            case .audioSessionFailed(let error):
                return "Audio session error: \(error.localizedDescription)"
            case .invalidAudioFormat(let reason):
                return "Invalid audio format: \(reason)"
            case .audioEngineStartFailed:
                return "Failed to start audio engine."
            case .audioEnginePrepareFailed(let error):
                return "Failed to prepare audio engine: \(error.localizedDescription)"
            }
        }
    }

    private init() {
        requestAuthorization()
    }

    func ensureAuthorization() async throws -> Bool {
        if authorizationStatus == .authorized {
            return true
        }

        if authorizationStatus == .denied || authorizationStatus == .restricted {
            throw SpeechRecognitionError.permissionDenied
        }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.authorizationStatus = status
            }
        }
    }

    /// Start recording with auto-silence detection
    func startRecording() async throws {
        // 1. Check recognizer availability
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available"
            throw SpeechRecognitionError.recognizerUnavailable
        }

        // 2. Ensure authorization
        guard try await ensureAuthorization() else {
            errorMessage = "Speech recognition authorization required"
            throw SpeechRecognitionError.permissionDenied
        }

        // 3. Clean up existing recording
        stopRecording()

        // 4. Request recording mode from coordinator
        do {
            try await AudioSessionCoordinator.shared.requestMode(.recording)
        } catch {
            throw SpeechRecognitionError.audioSessionFailed(error)
        }

        // 5. Reset state
        transcribedText = ""
        errorMessage = nil
        hasAutoSent = false
        hasSpeechActivity = false
        lastSpeechTime = Date()

        // 6. Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Unable to create recognition request"
            throw SpeechRecognitionError.audioEngineStartFailed
        }

        recognitionRequest.shouldReportPartialResults = true

        // 7. Create recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    print("🎙️ Recognition error: \(error.localizedDescription)")
                    self.errorMessage = error.localizedDescription
                    // Stop recording on error but don't auto-restart
                    self.stopRecording()
                }
                return
            }

            if let result = result {
                DispatchQueue.main.async {
                    let newText = result.bestTranscription.formattedString
                    if !newText.isEmpty {
                        self.transcribedText = newText
                        self.onTranscriptionUpdate?(self.transcribedText)
                        self.lastSpeechTime = Date()
                    }
                }
            }
        }

        // 8. Configure audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        do {
            audioEngine.prepare()
        } catch {
            throw SpeechRecognitionError.audioEnginePrepareFailed(error)
        }

        // 9. Validate audio format
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw SpeechRecognitionError.invalidAudioFormat("Sample rate: \(recordingFormat.sampleRate), channels: \(recordingFormat.channelCount)")
        }

        print("🎙️ Audio format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount)ch")

        // 10. Install tap with audio level detection
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Calculate audio power level
            let channelData = buffer.floatChannelData?[0]
            let frameLength = UInt(buffer.frameLength)

            if frameLength > 0, let data = channelData {
                var sum: Float = 0
                for i in 0..<Int(frameLength) {
                    sum += data[i] * data[i]
                }
                let rms = sqrt(sum / Float(frameLength))
                let power = 20 * log10(max(rms, 0.0000001))

                DispatchQueue.main.async {
                    self.currentAudioPower = power
                    self.audioLevel = power
                    if power > self.speechPowerThreshold {
                        self.hasSpeechActivity = true
                    }
                }
            }

            self.recognitionRequest?.append(buffer)
        }

        // 11. Start audio engine
        try audioEngine.start()

        guard audioEngine.isRunning else {
            throw SpeechRecognitionError.audioEngineStartFailed
        }

        isRecording = true
        print("🎙️ Recording started")

        // 12. Start silence detection
        startSilenceDetection()
    }

    private func startSilenceDetection() {
        // Check every 0.3 seconds for silence
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }

            guard let lastSpeech = self.lastSpeechTime else { return }
            let silenceDuration = Date().timeIntervalSince(lastSpeech)

            // Check if we have meaningful speech
            let trimmed = self.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count

            let isMeaningful = wordCount >= 2 &&
                               trimmed.rangeOfCharacter(from: .letters) != nil &&
                               self.hasSpeechActivity

            // Auto-send after silence threshold
            if silenceDuration >= self.silenceThreshold &&
                isMeaningful &&
                !self.hasAutoSent {
                print("🎙️ Auto-send triggered: \(wordCount) words after \(silenceDuration)s silence")
                self.hasAutoSent = true
                self.stopRecording()
                self.onAutoSend?()
            }
        }
    }

    /// Stop recording and finalize transcription
    func stopRecording() {
        guard isRecording else { return }

        print("🎙️ Recording stopped")

        // Stop silence detection
        silenceTimer?.invalidate()
        silenceTimer = nil

        // Stop audio engine first
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // Remove tap from input node
        audioEngine.inputNode.removeTap(onBus: 0)

        // End and clear recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Cancel and clear recognition task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Reset state
        isRecording = false
        hasSpeechActivity = false
    }

    func getTranscribedText() -> String {
        return transcribedText
    }

    func clearTranscription() {
        transcribedText = ""
        hasAutoSent = false
    }
}
