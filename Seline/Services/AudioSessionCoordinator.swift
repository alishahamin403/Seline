//
//  AudioSessionCoordinator.swift
//  Seline
//
//  Created by Claude on 2026-01-21.
//  Centralized audio session coordinator to prevent conflicts between TTS and speech recognition
//

import Foundation
import AVFoundation

@MainActor
class AudioSessionCoordinator: ObservableObject {
    static let shared = AudioSessionCoordinator()

    enum AudioMode {
        case idle           // No audio activity
        case recording      // Speech recognition active
        case playback       // TTS playing
    }

    enum AudioSessionError: LocalizedError {
        case transitionInProgress
        case configurationFailed(Error)

        var errorDescription: String? {
            switch self {
            case .transitionInProgress:
                return "Audio session transition already in progress"
            case .configurationFailed(let error):
                return "Failed to configure audio session: \(error.localizedDescription)"
            }
        }
    }

    @Published private(set) var currentMode: AudioMode = .idle
    private var isTransitioning = false

    private init() {}

    /// Request mode change with proper sequencing
    func requestMode(_ mode: AudioMode) async throws {
        // Prevent concurrent transitions
        guard !isTransitioning else {
            throw AudioSessionError.transitionInProgress
        }

        guard currentMode != mode else { return }

        isTransitioning = true
        defer { isTransitioning = false }

        let audioSession = AVAudioSession.sharedInstance()

        do {
            // Deactivate current mode
            if currentMode != .idle {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                // Brief delay for clean deactivation
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }

            // Configure for new mode
            switch mode {
            case .idle:
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                print("🔇 Audio session: idle")

            case .recording:
                try audioSession.setCategory(.playAndRecord, mode: .spokenAudio,
                    options: [.defaultToSpeaker, .allowBluetooth])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                print("🎙️ Audio session: recording")

            case .playback:
                try audioSession.setCategory(.playAndRecord, mode: .spokenAudio,
                    options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                print("🔊 Audio session: playback")
            }

            currentMode = mode

        } catch {
            print("❌ Audio session configuration failed: \(error)")
            throw AudioSessionError.configurationFailed(error)
        }
    }
}
