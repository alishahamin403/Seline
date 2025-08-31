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
    
    let mode: VoiceMode
    let onCancel: () -> Void
    let onModeChange: () -> Void
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Main recording card
            VStack(spacing: 0) {
                // Permission error or recording interface
                if !voiceService.canRecord && voiceService.errorMessage != nil {
                    permissionErrorView
                } else {
                    // Recording interface
                    recordingInterface
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(DesignSystem.Colors.surface)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
    }
    
    // MARK: - UI Components
    
    private var recordingInterface: some View {
        VStack(spacing: 24) {
            // Header with mode indicator
            modeHeader
            
            // Recording visualization
            recordingVisualization
            
            // Status text
            statusText
            
            // Control buttons
            controlButtons
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
    
    private var modeHeader: some View {
        HStack {
            // Back/Mode change button
            Button(action: onModeChange) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                    Text("Change")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .foregroundColor(mode.color)
            }
            
            Spacer()
            
            // Current mode indicator
            HStack(spacing: 8) {
                Text(mode.emoji)
                    .font(.system(size: 16))
                
                Text(mode.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(mode.color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(mode.color.opacity(0.3), lineWidth: 1)
                    )
            )
            
            Spacer()
            
            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }
    
    private var recordingVisualization: some View {
        ZStack {
            // Outer pulsing circles with mode color
            ForEach(0..<3) { index in
                pulsingCircle(for: index)
            }
            
            // Main recording circle with mode-specific styling
            ZStack {
                Circle()
                    .fill(voiceService.isRecording ? 
                          LinearGradient(colors: [Color.red, Color.red.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing) : 
                          mode.gradient)
                    .frame(width: 80, height: 80)
                    .scaleEffect(voiceService.isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: voiceService.isRecording)
                
                if voiceService.isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    Image(systemName: voiceService.isRecording ? "mic.fill" : mode.recordingIcon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    private var statusText: some View {
        VStack(spacing: 8) {
            Text(statusTitle)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.center)
            
            Text(statusSubtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            
            if !voiceService.isRecording && !voiceService.isProcessing {
                Text("Example: \(mode.recordingExample)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(mode.color)
                    .padding(.top, 4)
                    .multilineTextAlignment(.center)
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
            return "Converting your speech to text"
        } else if voiceService.isRecording {
            switch mode {
            case .calendar:
                return "Describe your meeting or event details"
            case .todo:
                return "Tell me what you need to remember"
            case .search:
                return "Describe the emails you're looking for"
            }
        } else {
            return "Tap the microphone to start recording"
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 20) {
            // Change mode button
            if !voiceService.isRecording && !voiceService.isProcessing {
                Button(action: onModeChange) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Change Mode")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(mode.color)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(mode.color.opacity(0.1))
                    )
                }
            }
            
            // Stop recording button (only show when recording)
            if voiceService.isRecording {
                Button(action: {
                    voiceService.stopRecording(userInitiated: true)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("Stop")
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Permission Error View
    
    private var permissionErrorView: some View {
        VStack(spacing: 20) {
            // Error icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.red)
            }
            
            // Error text
            VStack(spacing: 8) {
                Text("Permission Required")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(voiceService.errorMessage ?? "Microphone and Speech Recognition permissions are needed for voice features.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Permission buttons
            HStack(spacing: 16) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(DesignSystem.Colors.surfaceSecondary)
                        )
                }
                
                Button(action: {
                    showingPermissionAlert = true
                }) {
                    Text("Open Settings")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(DesignSystem.Colors.accent)
                        )
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
    
    // MARK: - Helper Views
    
    private func pulsingCircle(for index: Int) -> some View {
        let strokeOpacity = voiceService.isRecording ? mode.color.opacity(0.3) : mode.color.opacity(0.1)
        let circleSize = 120 + CGFloat(index) * 30
        let scaleEffect = voiceService.isRecording ? 1.3 : 1.0
        let opacity = voiceService.isRecording ? 0.6 - Double(index) * 0.15 : 0.2
        
        return Circle()
            .stroke(strokeOpacity, lineWidth: 2)
            .frame(width: circleSize, height: circleSize)
            .scaleEffect(scaleEffect)
            .opacity(opacity)
            .animation(
                .easeInOut(duration: 1.5 + Double(index) * 0.2)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.1),
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