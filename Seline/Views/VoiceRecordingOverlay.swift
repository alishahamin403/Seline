//
//  VoiceRecordingOverlay.swift
//  Seline
//
//  Created by Claude on 2025-08-31.
//

import SwiftUI

struct VoiceRecordingOverlay: View {
    @StateObject private var voiceService = VoiceRecordingService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingPermissionAlert = false
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Main recording card
            VStack(spacing: 24) {
                // Permission error or recording visualization
                if !voiceService.canRecord && voiceService.errorMessage != nil {
                    permissionErrorView
                } else {
                    // Recording visualization
                    recordingVisualization
                    
                    // Status text
                    statusText
                    
                    // Recording controls
                    controlButtons
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(DesignSystem.Colors.surface)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 40)
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
    }
    
    private var recordingVisualization: some View {
        ZStack {
            // Outer pulsing circles
            ForEach(0..<3) { index in
                Circle()
                    .stroke(voiceService.isRecording ? Color.red.opacity(0.3) : DesignSystem.Colors.accent.opacity(0.3), lineWidth: 2)
                    .frame(width: 120 + CGFloat(index) * 30, height: 120 + CGFloat(index) * 30)
                    .scaleEffect(voiceService.isRecording ? 1.2 : 1.0)
                    .opacity(voiceService.isRecording ? 0.6 - Double(index) * 0.2 : 0.3)
                    .animation(
                        .easeInOut(duration: 1.5 + Double(index) * 0.2)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.1),
                        value: voiceService.isRecording
                    )
            }
            
            // Main microphone circle
            ZStack {
                Circle()
                    .fill(voiceService.isRecording ? Color.red.gradient : DesignSystem.Colors.accent.gradient)
                    .frame(width: 80, height: 80)
                    .scaleEffect(voiceService.isRecording ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: voiceService.isRecording)
                
                if voiceService.isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                } else {
                    Image(systemName: voiceService.isRecording ? "mic.fill" : "mic.slash.fill")
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
            
            Text(statusSubtitle)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var statusTitle: String {
        if voiceService.isProcessing {
            return "Processing..."
        } else if voiceService.isRecording {
            return "Listening..."
        } else {
            return "Tap to Start"
        }
    }
    
    private var statusSubtitle: String {
        if voiceService.isProcessing {
            return "Converting your speech to text"
        } else if voiceService.isRecording {
            return "Speak now - I'll automatically detect if it's a todo, calendar event, or search"
        } else {
            return "Ready to record your voice"
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 24) {
            // Cancel button
            Button(action: onCancel) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark")
                    Text("Cancel")
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.surfaceSecondary)
                )
            }
            .disabled(voiceService.isProcessing)
            
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
}

// MARK: - Preview

struct VoiceRecordingOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.ignoresSafeArea()
            
            VoiceRecordingOverlay(onCancel: {})
        }
    }
}