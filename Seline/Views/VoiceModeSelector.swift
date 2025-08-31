//
//  VoiceModeSelector.swift
//  Seline
//
//  Created by Claude on 2025-08-31.
//

import SwiftUI

struct VoiceModeSelector: View {
    @Environment(\.colorScheme) private var colorScheme
    let onModeSelected: (VoiceMode) -> Void
    let onCancel: () -> Void
    @Binding var selectedVoiceMode: VoiceMode?
    @Binding var showingVoiceModeSelector: Bool
    @Binding var showingVoiceRecording: Bool
    let startVoiceRecording: (VoiceMode) -> Void
    
    @State private var selectedMode: VoiceMode?
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            // Main selector card
            VStack(spacing: 0) {
                // Header
                header
                
                // Mode selection cards
                modeCards
                
                // Footer with cancel
                footer
            }
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(DesignSystem.Colors.surface)
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // MARK: - UI Components
    
    private var header: some View {
        VStack(spacing: 12) {
            // Microphone icon
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            
            // Title and subtitle
            VStack(spacing: 4) {
                Text("Choose Voice Mode")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Select what you'd like to create with your voice")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 32)
        .padding(.horizontal, 24)
    }
    
    private var modeCards: some View {
        VStack(spacing: 16) {
            ForEach(VoiceMode.allCases) { mode in
                ModeCard(
                    mode: mode,
                    isSelected: selectedMode == mode,
                    onTap: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        
                        selectedMode = mode
                        
                        // Delay slightly for visual feedback
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            selectedVoiceMode = mode
                            showingVoiceModeSelector = false
                            showingVoiceRecording = true
                            
                            // Start recording immediately for selected mode
                            startVoiceRecording(mode)
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }
    
    private var footer: some View {
        HStack {
            Button(action: onCancel) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark")
                    Text("Cancel")
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.surfaceSecondary)
                )
            }
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Mode Card Component

struct ModeCard: View {
    let mode: VoiceMode
    let isSelected: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Mode icon with background
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(mode.gradient)
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: mode.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
                
                // Mode info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(mode.emoji)
                            .font(.system(size: 18))
                        
                        Text(mode.title)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    
                    Text(mode.subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(mode.color)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? mode.color.opacity(0.1) : DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? mode.color.opacity(0.4) : Color.clear, lineWidth: 1.5)
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct VoiceModeSelector_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.ignoresSafeArea()
            
            VoiceModeSelector(
                onModeSelected: { mode in
                    print("Selected: \(mode.title)")
                },
                onCancel: {
                    print("Cancelled")
                },
                selectedVoiceMode: .constant(nil),
                showingVoiceModeSelector: .constant(true),
                showingVoiceRecording: .constant(false),
                startVoiceRecording: { mode in
                    print("Start recording for: \(mode.title)")
                }
            )
        }
    }
}