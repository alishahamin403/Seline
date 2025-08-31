//
//  VoiceRecordingView.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import SwiftUI

struct VoiceRecordingView: View {
    let todoManager: TodoManager
    
    @StateObject private var voiceRecordingService = VoiceRecordingService.shared
    @State private var hasRequestedPermissions = false
    @State private var showingSuccessMessage = false
    @State private var createdTodoTitle = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                DesignSystem.Colors.surface.ignoresSafeArea()
                
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Voice Todo")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    
                    // Recording Area
                    recordingSection
                    
                    // Transcription Display
                    if !voiceRecordingService.recordedText.isEmpty {
                        transcriptionSection
                    }
                    
                    // Success Message
                    if showingSuccessMessage {
                        successSection
                    }
                    
                    // Error Message
                    if let errorMessage = voiceRecordingService.errorMessage ?? todoManager.errorMessage {
                        errorSection(errorMessage)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        voiceRecordingService.cancelRecording()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
        .onAppear {
            requestPermissionsIfNeeded()
        }
    }
    
    // MARK: - Recording Section
    
    private var recordingSection: some View {
        VStack(spacing: 24) {
            // Recording Button
            Button(action: handleRecordingAction) {
                ZStack {
                    Circle()
                        .fill(voiceRecordingService.isRecording ? 
                              Color.red.gradient : 
                              (colorScheme == .dark ? DesignSystem.Colors.surfaceSecondary.gradient : Color.black.gradient))
                        .frame(width: 120, height: 120)
                        .scaleEffect(voiceRecordingService.isRecording ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: voiceRecordingService.isRecording)
                    
                    if voiceRecordingService.isRecording {
                        // Pulsing animation while recording
                        Circle()
                            .stroke(Color.red.opacity(0.3), lineWidth: 4)
                            .frame(width: 140, height: 140)
                            .scaleEffect(voiceRecordingService.isRecording ? 1.2 : 1.0)
                            .opacity(voiceRecordingService.isRecording ? 0 : 1)
                            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), 
                                     value: voiceRecordingService.isRecording)
                    }
                    
                    Image(systemName: voiceRecordingService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(voiceRecordingService.isRecording ? .white : (colorScheme == .dark ? .white : .white))
                }
            }
            .disabled(!voiceRecordingService.canRecord || todoManager.isLoading)
            
            // Status Text
            VStack(spacing: 4) {
                if voiceRecordingService.isRecording {
                    Text("Recording...")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                } else if voiceRecordingService.isProcessing {
                    Text("Processing...")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                } else if todoManager.isLoading {
                    Text("Creating Todo...")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                } else {
                    Text(voiceRecordingService.canRecord ? "Tap to Record" : "Permissions Required")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                if !voiceRecordingService.canRecord {
                    Button("Grant Permissions") {
                        requestPermissionsIfNeeded()
                    }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .padding(.top, 4)
                }
            }
        }
    }
    
    // MARK: - Transcription Section
    
    private var transcriptionSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
                
                Text("Transcription")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text(voiceRecordingService.recordedText)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    Button("Retry Recording") {
                        voiceRecordingService.cancelRecording()
                    }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Spacer()
                    
                    Button("Create Todo") {
                        createTodoFromTranscription()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.accent.gradient)
                    .cornerRadius(20)
                    .disabled(todoManager.isLoading)
                }
            }
            .padding(16)
            .background(DesignSystem.Colors.surfaceSecondary)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Success Section
    
    private var successSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundColor(.green)
            
            Text("Todo Created!")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text("\"\(createdTodoTitle)\"")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Button("Create Another") {
                resetView()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(DesignSystem.Colors.accent)
            .padding(.top, 8)
        }
        .padding(20)
        .background(DesignSystem.Colors.surfaceSecondary)
        .cornerRadius(16)
    }
    
    // MARK: - Error Section
    
    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.orange)
            
            Text("Error")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text(message)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again") {
                voiceRecordingService.cancelRecording()
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(DesignSystem.Colors.accent)
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
    
    
    // MARK: - Actions
    
    private func requestPermissionsIfNeeded() {
        guard !hasRequestedPermissions else { return }
        
        hasRequestedPermissions = true
        Task {
            await voiceRecordingService.requestPermissions()
        }
    }
    
    private func handleRecordingAction() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        if voiceRecordingService.isRecording {
            voiceRecordingService.stopRecording()
        } else {
            Task {
                await voiceRecordingService.startRecording()
            }
        }
    }
    
    private func createTodoFromTranscription() {
        guard !voiceRecordingService.recordedText.isEmpty else { return }
        
        // Clear any existing errors
        voiceRecordingService.errorMessage = nil
        
        Task {
            await todoManager.createTodoFromSpeech(voiceRecordingService.recordedText)
            
            if todoManager.errorMessage == nil {
                // Success - find the most recently created todo
                let sortedTodos = todoManager.todos.sorted { $0.createdDate > $1.createdDate }
                createdTodoTitle = sortedTodos.first?.title ?? "New Todo"
                showingSuccessMessage = true
                
                // Auto dismiss after success and navigate back to todo list
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }
    
    private func resetView() {
        voiceRecordingService.cancelRecording()
        showingSuccessMessage = false
        createdTodoTitle = ""
    }
}