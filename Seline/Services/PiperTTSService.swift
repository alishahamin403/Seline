import Foundation
import AVFoundation

@MainActor
class PiperTTSService: NSObject, ObservableObject {
    static let shared = PiperTTSService()

    @Published var isSpeaking = false
    var onSpeechFinished: (() -> Void)?

    private var audioPlayer: AVAudioPlayer?

    var isAvailable: Bool {
        !Config.piperTTSBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private override init() {
        super.init()
    }

    func speak(_ text: String, completion: (() -> Void)? = nil) {
        guard isAvailable else {
            completion?()
            return
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion?()
            return
        }

        onSpeechFinished = completion

        Task {
            do {
                try await AudioSessionCoordinator.shared.requestMode(.playback)
            } catch {
                print("❌ Failed to configure audio session for Piper: \(error)")
                onSpeechFinished?()
                onSpeechFinished = nil
                return
            }

            guard let url = URL(string: Config.piperTTSBaseURL) else {
                print("❌ Piper TTS base URL invalid")
                onSpeechFinished?()
                onSpeechFinished = nil
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": trimmed])

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                    print("❌ Piper TTS HTTP error: \(httpResponse.statusCode)")
                    onSpeechFinished?()
                    onSpeechFinished = nil
                    return
                }

                audioPlayer = try AVAudioPlayer(data: data)
                audioPlayer?.delegate = self
                audioPlayer?.prepareToPlay()
                isSpeaking = true
                audioPlayer?.play()
            } catch {
                print("❌ Piper TTS playback failed: \(error)")
                onSpeechFinished?()
                onSpeechFinished = nil
            }
        }
    }

    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
        onSpeechFinished = nil
    }
}

extension PiperTTSService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isSpeaking = false
        onSpeechFinished?()
        onSpeechFinished = nil

        Task {
            try? await AudioSessionCoordinator.shared.requestMode(.idle)
        }
    }
}
