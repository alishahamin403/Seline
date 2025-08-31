//
//  VoiceRecordingService.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import Foundation
import Speech
import AVFoundation

@MainActor
class VoiceRecordingService: NSObject, ObservableObject {
    static let shared = VoiceRecordingService()
    
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var recordedText = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @Published var microphonePermissionGranted = false
    @Published var errorMessage: String?
    
    private let speechRecognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var oneShotCompletion: ((String?) -> Void)?
    private var oneShotMode: OneShotMode?
    private var userInitiatedStop: Bool = false
    private var hasTapInstalled: Bool = false
    
    private override init() {
        super.init()
        setupSpeechRecognition()
    }
    
    // MARK: - Setup
    
    private func setupSpeechRecognition() {
        speechRecognizer?.delegate = self
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }
    
    // MARK: - Permissions
    
    func requestPermissions() async {
        // Request speech recognition permission
        await requestSpeechPermission()
        
        // Request microphone permission
        await requestMicrophonePermission()
    }
    
    private func requestSpeechPermission() async {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    continuation.resume()
                }
            }
        }
    }
    
    private func requestMicrophonePermission() async {
        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        microphonePermissionGranted = granted
    }
    
    var canRecord: Bool {
        return authorizationStatus == .authorized && 
               microphonePermissionGranted && 
               speechRecognizer?.isAvailable == true
    }
    
    // MARK: - Recording Control
    
    func startRecording() async {
        guard canRecord else {
            errorMessage = "Recording permissions not granted"
            return
        }
        
        guard !isRecording else { return }
        
        do {
            try await setupAudioSession()
            try startSpeechRecognition()
            isRecording = true
            recordedText = ""
            errorMessage = nil
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            print("❌ VoiceRecordingService: Failed to start recording: \(error)")
        }
    }
    
    func stopRecording(userInitiated: Bool = false) {
        guard isRecording else { return }
        userInitiatedStop = userInitiated
        
        audioEngine.stop()
        if hasTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        recognitionRequest?.endAudio()
        if !userInitiated { // Only cancel the task when not initiated by user (true cancellations)
            recognitionTask?.cancel()
        }
        
        isRecording = false
        if userInitiated {
            // Return UI to idle state immediately without showing processing/error
            isProcessing = false
            errorMessage = nil
            recognitionRequest = nil
            recognitionTask = nil
            // Deactivate to allow clean restart
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } else {
            // Allow callback to finish naturally
            isProcessing = true
            // Safety timeout
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    if isProcessing { isProcessing = false }
                }
            }
        }
    }
    
    func cancelRecording() {
        stopRecording(userInitiated: true)
        recordedText = ""
        isProcessing = false
        errorMessage = nil
    }

    enum OneShotMode {
        case search
        case todo
    }
    
    /// Start a one-shot transcription flow with a completion handler (used for search voice input)
    func startOneShotTranscription(for mode: OneShotMode, completion: @escaping (String?) -> Void) {
        Task {
            await requestPermissions()
            if !canRecord {
                await MainActor.run {
                    errorMessage = "Voice recording permissions not granted. Please enable microphone and speech recognition in Settings."
                }
                completion(nil)
                return
            }
            oneShotMode = mode
            oneShotCompletion = completion
            await startRecording()
        }
    }
    
    // MARK: - Audio Setup
    
    private func setupAudioSession() async throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }
    
    private func startSpeechRecognition() throws {
        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceRecordingError.recognitionRequestFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Get audio input
        let inputNode = audioEngine.inputNode
        // Remove old tap if any
        if hasTapInstalled {
            inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        hasTapInstalled = true
        
        // Prepare and start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
    }
    
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            print("❌ VoiceRecordingService: Recognition error: \(error)")
            if userInitiatedStop {
                // Expected cancellation after user stops. Reset state quietly.
                userInitiatedStop = false
                errorMessage = nil
                isProcessing = false
                recognitionRequest = nil
                recognitionTask = nil
                return
            }
            errorMessage = "Speech recognition failed: \(error.localizedDescription)"
            stopRecording(userInitiated: false)
            return
        }
        
        if let result = result {
            recordedText = result.bestTranscription.formattedString
            
            if result.isFinal {
                print("🎯 VoiceRecordingService: Final transcription: \(recordedText)")
                isProcessing = false
                let finalText = recordedText
                // Finalize without triggering error path
                recognitionRequest = nil
                recognitionTask = nil
                audioEngine.stop()
                isRecording = false
                if let completion = oneShotCompletion {
                    oneShotCompletion = nil
                    oneShotMode = nil
                    completion(finalText)
                }
            }
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension VoiceRecordingService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        print("🎤 VoiceRecordingService: Speech recognizer availability changed: \(available)")
    }
}

// MARK: - Error Types

enum VoiceRecordingError: LocalizedError {
    case recognitionRequestFailed
    case audioEngineStartFailed
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .recognitionRequestFailed:
            return "Failed to create speech recognition request"
        case .audioEngineStartFailed:
            return "Failed to start audio engine"
        case .permissionDenied:
            return "Speech recognition or microphone permission denied"
        }
    }
}