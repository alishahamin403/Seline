import SwiftUI

/// State for voice/speak mode (kept for VoiceOrbView; speak mode UI removed from chat)
enum VoiceModeState {
    case idle, listening, processing, speaking
}

/// Animated central orb for voice/speak mode
struct VoiceOrbView: View {
    let state: VoiceModeState
    let audioLevel: Float // -160 (silence) to 0 (max)
    let onTap: () -> Void

    @Environment(\.colorScheme) var colorScheme

    // Animation states
    @State private var breatheScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var pulseOpacity: Double = 0.6
    @State private var ringScale: CGFloat = 1.0
    @State private var wavePhase: Double = 0

    private let orbSize: CGFloat = 110

    // Normalize audio level to 0...1 range
    private var normalizedAudioLevel: CGFloat {
        let clamped = max(min(audioLevel, 0), -80)
        return CGFloat((clamped + 80) / 80)
    }

    private var accent: Color { .claudeAccent }

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                idleOrb
            case .listening:
                listeningOrb
            case .processing:
                processingOrb
            case .speaking:
                speakingOrb
            }
        }
        .frame(width: orbSize + 40, height: orbSize + 40)
        .contentShape(Circle())
        .onTapGesture {
            onTap()
        }
    }

    // MARK: - Idle State

    private var idleOrb: some View {
        ZStack {
            // Subtle glow
            Circle()
                .fill(accent.opacity(0.08))
                .frame(width: orbSize + 20, height: orbSize + 20)
                .scaleEffect(breatheScale)

            // Main orb
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            accent.opacity(0.3),
                            accent.opacity(0.1)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: orbSize / 2
                    )
                )
                .frame(width: orbSize, height: orbSize)
                .overlay(
                    Circle()
                        .stroke(accent.opacity(0.25), lineWidth: 2)
                )
                .scaleEffect(breatheScale)

            // Mic icon
            Image(systemName: "mic")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(accent.opacity(0.7))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                breatheScale = 1.02
            }
        }
    }

    // MARK: - Listening State

    private var listeningOrb: some View {
        ZStack {
            // Outer reactive ring 3
            Circle()
                .stroke(accent.opacity(0.15 * Double(normalizedAudioLevel)), lineWidth: 1.5)
                .frame(width: orbSize + 36, height: orbSize + 36)
                .scaleEffect(1.0 + normalizedAudioLevel * 0.15)

            // Outer reactive ring 2
            Circle()
                .stroke(accent.opacity(0.25 * Double(normalizedAudioLevel)), lineWidth: 2)
                .frame(width: orbSize + 22, height: orbSize + 22)
                .scaleEffect(1.0 + normalizedAudioLevel * 0.1)

            // Inner reactive ring
            Circle()
                .stroke(accent.opacity(0.4), lineWidth: 2.5)
                .frame(width: orbSize + 8, height: orbSize + 8)
                .scaleEffect(1.0 + normalizedAudioLevel * 0.05)

            // Main orb - brighter when listening
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            accent.opacity(0.5),
                            accent.opacity(0.2)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: orbSize / 2
                    )
                )
                .frame(width: orbSize, height: orbSize)
                .overlay(
                    Circle()
                        .stroke(accent.opacity(0.5), lineWidth: 2.5)
                )

            // Mic icon - active
            Image(systemName: "mic.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(accent)
        }
        .animation(.easeOut(duration: 0.08), value: normalizedAudioLevel)
    }

    // MARK: - Processing State

    private var processingOrb: some View {
        ZStack {
            // Rotating gradient ring
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [accent, accent.opacity(0.1)]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: orbSize + 12, height: orbSize + 12)
                .rotationEffect(.degrees(rotationAngle))

            // Main orb - slightly smaller during processing
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            accent.opacity(0.25),
                            Color.orange.opacity(0.1)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: orbSize / 2
                    )
                )
                .frame(width: orbSize - 6, height: orbSize - 6)
                .overlay(
                    Circle()
                        .stroke(accent.opacity(0.3), lineWidth: 2)
                )

            // Hourglass icon
            Image(systemName: "hourglass")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.orange)
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }

    // MARK: - Speaking State

    private var speakingOrb: some View {
        ZStack {
            // Subtle ripple
            Circle()
                .stroke(accent.opacity(0.15), lineWidth: 1.5)
                .frame(width: orbSize + 24, height: orbSize + 24)
                .scaleEffect(ringScale)
                .opacity(2.0 - Double(ringScale))

            // Main orb - bright, confident
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            accent.opacity(0.55),
                            accent.opacity(0.25)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: orbSize / 2
                    )
                )
                .frame(width: orbSize, height: orbSize)
                .overlay(
                    Circle()
                        .stroke(accent.opacity(0.5), lineWidth: 2.5)
                )

            // Waveform bars
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 4, height: waveBarHeight(index: i))
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                ringScale = 1.15
            }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                wavePhase = 1.0
            }
        }
    }

    private func waveBarHeight(index: Int) -> CGFloat {
        let baseHeight: CGFloat = 12
        let maxExtra: CGFloat = 18
        let offset = Double(index) * 0.4
        let wave = sin((wavePhase * .pi * 2) + offset)
        return baseHeight + maxExtra * CGFloat((wave + 1) / 2)
    }
}
