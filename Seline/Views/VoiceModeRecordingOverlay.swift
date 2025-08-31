//
//  VoiceModeRecordingOverlay.swift
//  Seline
//
//  Created by Claude on 2025-08-31.
//

import SwiftUI

struct VoiceModeRecordingOverlay: View {
    @StateObject private var voiceService = VoiceRecordingService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingPermissionAlert = false
    @State private var pulseAnimation = false
    
    let mode: VoiceMode
    let onCancel: () -> Void
    let onModeChange: () -> Void
    
    var body: some View {
        ZStack {
            // Beautiful gradient background
            backgroundOverlay
            
            // Main recording card
            VStack(spacing: 0) {
                // Permission error or recording interface
                if !voiceService.canRecord && voiceService.errorMessage != nil {
                    permissionErrorView
                } else {
                    recordingInterface
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(DesignSystem.Colors.surface)
                    .shadow(
                        color: DesignSystem.Colors.shadow,
                        radius: 24,
                        x: 0,
                        y: 12
                    )
            )
            .padding(.horizontal, 24)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.8)).combined(with: ),
            removal: .opacity.combined(with: .scale(scale: 0.9))
        ))
        .alert("Open Settings", isPresented: $showingPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
        } message: {
            Text("To use voice features, please enable Microphone and Speech Recognition permissions in Settings > Seline.")
        }
        .onAppear {
            pulseAnimation = true
        }
    }
    
    // MARK: - Background
    
    private var backgroundOverlay: some View {
        ZStack {
            // Dark backdrop
            Color.black
                .opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Subtle gradient overlay
            LinearGradient(
                colors: [
                    Color.black.opacity(0.4),
                    Color.black.opacity(0.2),
                    Color.black.opacity(0.4)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
    
    // MARK: - Main Interface
    
    private var recordingInterface: some View {
        VStack(spacing: 32) {
            // Header with mode indicator
            modeHeader
            
            // Recording visualization
            recordingVisualization
            
            // Status text
            statusText
            
            // Control buttons
            controlButtons
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 36)
    }
    
    private var modeHeader: some View {
        HStack {
            // Back/Mode change button
            Button(action: onModeChange) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Change")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                .foregroundColor(DesignSystem.Colors.accent)
            }
            
            Spacer()
            
            // Current mode indicator with gradient
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(mode.gradient)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: mode.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(
                            Color(UIColor { traitCollection in
                                traitCollection.userInterfaceStyle == .dark ? 
                                UIColor.black : UIColor.white
                            })
                        )
                }
                
                Text(mode.title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            )
            
            Spacer()
            
            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(DesignSystem.Colors.surfaceSecondary)
                    )
            }
        }
    }
    
    private var recordingVisualization: some View {
        ZStack {
            // Outer pulsing rings
            ForEach(0..<3) { index in
                pulsingRing(for: index)
            }
            
            // Main recording circle
            ZStack {
                // Background circle with gradient
                Circle()
                    .fill(
                        voiceService.isRecording ? 
                        LinearGradient(
                            colors: [Color.red, Color.red.opacity(0.8)], 
                            startPoint: .topLeading, 
                            endPoint: .bottomTrailing
                        ) : 
                        mode.gradient
                    )
                    .frame(width: 100, height: 100)
                    .scaleEffect(voiceService.isRecording ? (pulseAnimation ? 1.1 : 1.0) : 1.0)
                    .animation(
                        voiceService.isRecording ? 
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : 
                        .easeInOut(duration: 0.3),
                        value: pulseAnimation
                    )
                
                // Icon or loading indicator
                if voiceService.isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.4)
                } else {
                    Image(systemName: voiceService.isRecording ? "mic.fill" : "mic")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white)
                        .scaleEffect(voiceService.isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: voiceService.isRecording)
                }
            }
            .onTapGesture {
                if !voiceService.isRecording && !voiceService.isProcessing {
                    Task { await voiceService.startRecording() }
                } else if voiceService.isRecording {
                    voiceService.stopRecording(userInitiated: true)
                }
            }
        }
    }
    
    private var statusText: some View {
        VStack(spacing: 12) {
            Text(statusTitle)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text(statusSubtitle)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .lineSpacing(2)
            
            if !voiceService.isRecording && !voiceService.isProcessing {
                VStack(spacing: 8) {
                    Text("Example:")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                    
                    Text(mode.recordingExample)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .multilineTextAlignment(.center)
                        .italic()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(DesignSystem.Colors.accent.opacity(0.1))
                        )
                }
                .padding(.top, 8)
            }
        }
    }
    
    private var statusTitle: String {
        if voiceService.isProcessing {
            return "Processing..."
        } else if voiceService.isRecording {
            return "Listening..."
        } else {
            return mode.recordingPrompt
        }
    }
    
    private var statusSubtitle: String {
        if voiceService.isProcessing {
            return "Converting your speech to text and understanding your request"
        } else if voiceService.isRecording {
            switch mode {
            case .calendar:
                return "Describe your meeting or event details"
            case .todo:
                return "Tell me what you need to remember"
            case .search:
                return "Describe what you're looking for"
            }
        } else {
            return "Tap the microphone to start recording"
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 16) {
            // Stop recording button (only show when recording)
            if voiceService.isRecording {
                Button(action: {
                    voiceService.stopRecording(userInitiated: true)
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Stop")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    colors: [Color.red, Color.red.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
            }
        }
    }
    
    // MARK: - Permission Error View
    
    private var permissionErrorView: some View {
        VStack(spacing: 28) {
            // Error icon with gradient
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.danger.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Circle()
                    .stroke(DesignSystem.Colors.danger.opacity(0.3), lineWidth: 2)
                    .frame(width: 100, height: 100)
                
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.danger)
            }
            
            // Error text
            VStack(spacing: 12) {
                Text("Permission Required")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(voiceService.errorMessage ?? "Microphone and Speech Recognition permissions are needed for voice features.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            
            // Permission buttons
            VStack(spacing: 12) {
                Button(action: {
                    showingPermissionAlert = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gear")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Open Settings")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(DesignSystem.Colors.accent)
                    )
                }
                
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(DesignSystem.Colors.surfaceSecondary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                                )
                        )
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 40)
    }
    
    // MARK: - Helper Views
    
    private func pulsingRing(for index: Int) -> some View {
        let baseSize: CGFloat = 140
        let ringSize = baseSize + CGFloat(index) * 40
        let maxScale: CGFloat = 1.4
        let animationDelay = Double(index) * 0.2
        
        return Circle()
            .stroke(
                DesignSystem.Colors.accent.opacity(0.2 - Double(index) * 0.05),
                lineWidth: 2
            )
            .frame(width: ringSize, height: ringSize)
            .scaleEffect(voiceService.isRecording ? maxScale : 1.0)
            .opacity(voiceService.isRecording ? (0.8 - Double(index) * 0.2) : 0.1)
            .animation(
                .easeInOut(duration: 2.0 + Double(index) * 0.3)
                .repeatForever(autoreverses: true)
                .delay(animationDelay),
                value: voiceService.isRecording
            )
    }
}

// MARK: - Preview

struct VoiceModeRecordingOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.ignoresSafeArea()
            
            VoiceModeRecordingOverlay(
                mode: .calendar,
                onCancel: { },
                onModeChange: { }
            )
        }
    }
}
