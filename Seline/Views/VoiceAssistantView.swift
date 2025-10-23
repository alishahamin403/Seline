import SwiftUI
import AVFoundation

struct VoiceAssistantView: View {
    @StateObject private var voiceService = VoiceAssistantService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedNote: Note? = nil
    @State private var selectedEvent: TaskItem? = nil
    @State private var showingEditTask = false
    @State private var isListening = false
    @State private var currentTranscription = ""
    @State private var showVoiceSettings = false
    @AppStorage("selectedVoice") private var selectedVoice = "nova"

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Full screen background (adaptive for light/dark mode)
            (colorScheme == .dark ?
                LinearGradient(
                    colors: [
                        Color(red: 0.035, green: 0.086, blue: 0.106), // darkest blue
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ) :
                LinearGradient(
                    colors: [Color.white, Color.white], // Pure white for light mode
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea()

            // Main content area with safe scrolling
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollViewReader { scrollProxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                    // Large animated orb
                                    AnimatedOrbView(state: voiceService.currentState)
                                        .frame(width: 240, height: 240)
                                        .padding(.top, 40)
                                        .padding(.bottom, 30)

                                    // Conversation history (back and forth messages)
                                    if !voiceService.conversationHistory.isEmpty {
                                        VStack(spacing: 24) {
                                            ForEach(voiceService.conversationHistory) { message in
                                                VStack(spacing: 12) {
                                                    // Message bubble
                                                    HStack {
                                                        if message.isUser {
                                                            Spacer(minLength: 40)
                                                        }

                                                        VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                                                            FormattedMessageText(
                                                                text: message.text,
                                                                isUser: message.isUser,
                                                                colorScheme: colorScheme
                                                            )
                                                            .padding(.horizontal, 16)
                                                            .padding(.vertical, 12)
                                                            .background(
                                                                RoundedRectangle(cornerRadius: 18)
                                                                    .fill(message.isUser ?
                                                                        LinearGradient(
                                                                            colors: [
                                                                                Color(red: 0.40, green: 0.65, blue: 0.80),
                                                                                Color(red: 0.30, green: 0.50, blue: 0.60)
                                                                            ],
                                                                            startPoint: .topLeading,
                                                                            endPoint: .bottomTrailing
                                                                        ) :
                                                                        LinearGradient(
                                                                            colors: [(colorScheme == .dark ? Color.white : Color.black).opacity(0.08)],
                                                                            startPoint: .top,
                                                                            endPoint: .bottom
                                                                        )
                                                                    )
                                                            )

                                                            // Related data items (for assistant messages only)
                                                            if let relatedData = message.relatedData, !relatedData.isEmpty, !message.isUser {
                                                                VStack(spacing: 10) {
                                                                    ForEach(relatedData) { item in
                                                                        ModernDataCard(
                                                                            item: item,
                                                                            onTap: {
                                                                                handleDataItemTap(item)
                                                                            }
                                                                        )
                                                                    }
                                                                }
                                                            }
                                                        }

                                                        if !message.isUser {
                                                            Spacer(minLength: 40)
                                                        }
                                                    }
                                                    .padding(.horizontal, 20)
                                                }
                                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                                            }
                                        }
                                        .padding(.bottom, 20)
                                    }

                                    // Show "Start talking" indicator when listening and ready (even with conversation history)
                                    if isListening && currentTranscription.isEmpty && voiceService.currentState == .listening {
                                        VStack(spacing: 12) {
                                            Text("Start talking")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                                                .padding(.horizontal, 20)
                                                .padding(.vertical, 12)
                                                .background(
                                                    Capsule()
                                                        .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.1))
                                                )
                                        }
                                        .transition(.scale.combined(with: .opacity))
                                        .padding(.bottom, 40)
                                    }
                                    // Show live transcription while user is speaking
                                    else if isListening && !currentTranscription.isEmpty {
                                        VStack(spacing: 12) {
                                            Text(currentTranscription)
                                                .font(.system(size: 16, weight: .regular))
                                                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(0.7))
                                                .multilineTextAlignment(.center)
                                                .padding(.horizontal, 28)
                                                .lineSpacing(3)
                                                .italic()
                                        }
                                        .transition(.opacity)
                                        .padding(.bottom, 40)
                                    } else if voiceService.conversationHistory.isEmpty {
                                        // Idle/Listening state (only show when no conversation)
                                        VStack(spacing: 10) {
                                            Text(isListening ? "Listening..." : "Muted")
                                                .font(.system(size: 18, weight: .regular))
                                                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(0.9))

                                            Text(isListening ? "Tap to mute" : "Tap to unmute")
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundColor((colorScheme == .dark ? Color.white : Color.black).opacity(0.4))
                                        }
                                        .transition(.opacity)
                                        .padding(.bottom, 40)
                                    }

                                    // Extra padding at bottom for scroll
                                    Color.clear.frame(height: 200)
                                        .id("bottomOfScrollView")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .onChange(of: voiceService.conversationHistory.count) { _ in
                                // Auto-scroll to bottom when new messages arrive
                                withAnimation(.easeOut(duration: 0.3)) {
                                    scrollProxy.scrollTo("bottomOfScrollView", anchor: .bottom)
                                }
                            }
                        }

                    // Bottom controls (fixed at bottom with white/dark background)
                    HStack(spacing: 20) {
                        // Stop button (only shown when AI is speaking)
                        if voiceService.currentState == .speaking {
                            StopSpeakingButton(
                                colorScheme: colorScheme,
                                onTap: {
                                    HapticManager.shared.medium()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        isListening = true
                                        currentTranscription = ""
                                    }
                                    voiceService.startListeningWithSilenceDetection()
                                }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        // Tap-to-mute button
                        TapToMuteButton(
                            isListening: $isListening,
                            colorScheme: colorScheme,
                            onTap: {
                                HapticManager.shared.medium()

                                guard !voiceService.isProcessing else {
                                    return
                                }

                                if voiceService.currentState == .speaking {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        isListening = true
                                        currentTranscription = ""
                                    }
                                    voiceService.startListeningWithSilenceDetection()
                                } else if voiceService.currentState == .listening {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        isListening = false
                                        currentTranscription = ""
                                    }
                                    voiceService.stopListening()
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        isListening = true
                                        currentTranscription = ""
                                    }
                                    voiceService.startListeningWithSilenceDetection()
                                }
                            }
                        )
                        .disabled(voiceService.isProcessing)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 20)
                    .background(colorScheme == .dark ? Color.black : Color.white)
                }

                // Header overlay (transparent, floats above scroll content)
                VStack {
                    HStack {
                        // Settings button
                        Button(action: {
                            showVoiceSettings = true
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        }

                        Spacer()

                        // Close button
                        Button(action: {
                            voiceService.stopListening()
                            voiceService.stopSpeaking()
                            voiceService.clearConversation()
                            dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    Spacer()
                }
                .background(Color.clear)
            }  // closes GeometryReader
        }
        .onReceive(voiceService.$currentTranscription) { transcription in
            currentTranscription = transcription
        }
        .onReceive(voiceService.$currentState) { state in
            // Update UI state based on voice service state
            if state == .listening && !isListening {
                // Auto-restarted listening, update UI
                withAnimation {
                    isListening = true
                }
            } else if state == .processing || state == .speaking {
                // Don't change isListening state during processing/speaking
                // This allows conversation to continue
            } else if state == .idle && !isListening {
                // Keep UI in muted state
            }
        }
        .onAppear {
            // Clear conversation history for fresh start
            voiceService.clearConversation()

            // Set the selected voice from saved settings
            print("🎤 Loading voice setting: \(selectedVoice)")
            voiceService.selectedVoice = selectedVoice

            // Auto-start listening when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !isListening && voiceService.currentState == .idle {
                    withAnimation {
                        isListening = true
                    }
                    voiceService.startListeningWithSilenceDetection()
                }
            }
        }
        .onDisappear {
            // Clean up when view disappears
            voiceService.stopListening()
            voiceService.stopSpeaking()
        }
        .sheet(isPresented: $showVoiceSettings) {
            VoiceSettingsView(selectedVoice: $selectedVoice)
                .onDisappear {
                    voiceService.selectedVoice = selectedVoice
                }
        }
        .sheet(item: $selectedNote) { note in
            NoteEditView(note: note, isPresented: Binding<Bool>(
                get: { selectedNote != nil },
                set: { if !$0 { selectedNote = nil } }
            ))
        }
        .sheet(item: $selectedEvent) { event in
            if showingEditTask {
                NavigationView {
                    EditTaskView(
                        task: event,
                        onSave: { updatedTask in
                            TaskManager.shared.editTask(updatedTask)
                            selectedEvent = nil
                            showingEditTask = false
                        },
                        onCancel: {
                            selectedEvent = nil
                            showingEditTask = false
                        },
                        onDelete: { taskToDelete in
                            TaskManager.shared.deleteTask(taskToDelete)
                            selectedEvent = nil
                            showingEditTask = false
                        },
                        onDeleteRecurringSeries: { taskToDelete in
                            TaskManager.shared.deleteRecurringTask(taskToDelete)
                            selectedEvent = nil
                            showingEditTask = false
                        }
                    )
                }
            } else {
                NavigationView {
                    ViewEventView(
                        task: event,
                        onEdit: {
                            showingEditTask = true
                        },
                        onDelete: { taskToDelete in
                            TaskManager.shared.deleteTask(taskToDelete)
                            selectedEvent = nil
                        },
                        onDeleteRecurringSeries: { taskToDelete in
                            TaskManager.shared.deleteRecurringTask(taskToDelete)
                            selectedEvent = nil
                        }
                    )
                }
            }
        }
        .onChange(of: selectedEvent) { newValue in
            if newValue != nil {
                showingEditTask = false
            }
        }
        .fullScreenCover(isPresented: $voiceService.showEventConfirmation) {
            EventConfirmationView(
                eventData: voiceService.pendingEventCreation,
                onConfirm: {
                    voiceService.confirmEventCreation()
                },
                onCancel: {
                    voiceService.cancelEventCreation()
                }
            )
            .background(Color.clear)
        }
        .fullScreenCover(isPresented: $voiceService.showNoteConfirmation) {
            NoteConfirmationView(
                noteData: voiceService.pendingNoteCreation,
                onConfirm: {
                    voiceService.confirmNoteCreation()
                },
                onCancel: {
                    voiceService.cancelNoteCreation()
                }
            )
            .background(Color.clear)
        }
        .fullScreenCover(isPresented: $voiceService.showNoteUpdateConfirmation) {
            NoteUpdateConfirmationView(
                updateData: voiceService.pendingNoteUpdate,
                onConfirm: {
                    voiceService.confirmNoteUpdate()
                },
                onCancel: {
                    voiceService.cancelNoteUpdate()
                }
            )
            .background(Color.clear)
        }
        .fullScreenCover(isPresented: $voiceService.showDeletionConfirmation) {
            DeletionConfirmationView(
                deletionData: voiceService.pendingDeletion,
                onConfirm: {
                    voiceService.confirmDeletion()
                },
                onCancel: {
                    voiceService.cancelDeletion()
                }
            )
            .background(Color.clear)
        }
        .fullScreenCover(isPresented: $voiceService.showEventUpdateConfirmation) {
            EventUpdateConfirmationView(
                updateData: voiceService.pendingEventUpdate,
                onConfirm: {
                    voiceService.confirmEventUpdate()
                },
                onCancel: {
                    voiceService.cancelEventUpdate()
                }
            )
            .background(Color.clear)
        }
    }

    private func handleDataItemTap(_ item: RelatedDataItem) {
        HapticManager.shared.selection()

        switch item.type {
        case .note:
            // Find and open the note
            if let note = NotesManager.shared.notes.first(where: { $0.title == item.title }) {
                selectedNote = note
            }
        case .event:
            // Find and open the event
            let allTasks = TaskManager.shared.tasks.values.flatMap { $0 }
            if let event = allTasks.first(where: { $0.title == item.title }) {
                selectedEvent = event
            }
        case .location:
            // Open in Google Maps
            if let location = LocationsManager.shared.savedPlaces.first(where: { $0.displayName == item.title }) {
                GoogleMapsService.shared.openInGoogleMaps(place: location)
            }
        }
    }
}

// MARK: - Animated Orb (ChatGPT style)
struct AnimatedOrbView: View {
    let state: VoiceAssistantState
    @State private var isAnimating = false
    @State private var pulseAnimation = false
    @State private var rotation: Double = 0
    @State private var breathScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Outer glow rings (multiple layers for depth)
            ForEach(0..<4) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [orbColor.opacity(0.4), orbColor.opacity(0.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .scaleEffect(pulseAnimation ? 1.4 + (CGFloat(index) * 0.15) : 1.0)
                    .opacity(pulseAnimation ? 0.0 : 0.5)
                    .blur(radius: 2)
                    .animation(
                        .easeOut(duration: 2.0)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.3),
                        value: pulseAnimation
                    )
            }

            // Rotating gradient ring (listening state)
            if state == .listening || state == .processing {
                Circle()
                    .trim(from: 0, to: 0.6)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                orbColor.opacity(0.8),
                                orbColor.opacity(0.3),
                                orbColor.opacity(0.0)
                            ]),
                            center: .center,
                            angle: .degrees(rotation)
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(rotation))
                    .animation(
                        .linear(duration: 3.0).repeatForever(autoreverses: false),
                        value: rotation
                    )
            }

            // Main orb with enhanced gradient
            ZStack {
                // Outer glow layer
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                orbColor.opacity(0.6),
                                orbColor.opacity(0.3),
                                orbColor.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 60,
                            endRadius: 130
                        )
                    )
                    .frame(width: 220, height: 220)
                    .blur(radius: 20)

                // Main orb body
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                orbColor.opacity(0.9),
                                orbColor.opacity(0.7),
                                orbColor.opacity(0.5)
                            ],
                            center: UnitPoint(x: 0.4, y: 0.4),
                            startRadius: 10,
                            endRadius: 110
                        )
                    )
                    .frame(width: 200, height: 200)
                    .overlay(
                        // Shimmer effect
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 200)
                            .offset(x: isAnimating ? 10 : -10, y: isAnimating ? 10 : -10)
                    )
                    .shadow(color: orbColor.opacity(0.7), radius: 40, x: 0, y: 10)

                // Icon in center (no icon, just breathing orb)
                if state == .speaking {
                    // Sound wave visualization for speaking
                    ForEach(0..<3) { index in
                        Capsule()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: 4, height: breathScale * CGFloat(20 + index * 15))
                            .offset(x: CGFloat((index - 1) * 15))
                            .animation(
                                .easeInOut(duration: 0.5 + Double(index) * 0.1)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.1),
                                value: breathScale
                            )
                    }
                }
            }
            .scaleEffect(breathScale)
        }
        .onAppear {
            isAnimating = true
            pulseAnimation = true
            rotation = 360

            // Breathing animation
            withAnimation(
                .easeInOut(duration: 2.0)
                    .repeatForever(autoreverses: true)
            ) {
                breathScale = 1.08
            }
        }
        .onChange(of: state) { _ in
            // Pulse on state change
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                breathScale = 1.15
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                breathScale = 1.0
            }
        }
    }

    private var orbColor: Color {
        switch state {
        case .idle:
            return Color(red: 0.20, green: 0.34, blue: 0.40) // App's primary blue
        case .listening:
            return Color(red: 0.40, green: 0.65, blue: 0.80) // App's light blue
        case .processing:
            return Color(red: 0.20, green: 0.34, blue: 0.40).opacity(0.8)
        case .speaking:
            return Color(red: 0.40, green: 0.65, blue: 0.80)
        case .error:
            return Color(red: 1.0, green: 0.3, blue: 0.3)
        }
    }
}

// MARK: - Modern Data Card (ChatGPT inspired)
struct ModernDataCard: View {
    let item: RelatedDataItem
    let onTap: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                onTap()
            }
        }) {
            HStack(spacing: 14) {
                // Gradient icon background
                ZStack {
                    // Gradient background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColorsForType(item.type),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: gradientColorsForType(item.type)[0].opacity(0.3), radius: 8, x: 0, y: 4)

                    // Icon
                    Image(systemName: iconForType(item.type))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Content
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }

                    if let date = item.date {
                        Text(formatDate(date))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                Spacer()

                // Tap indicator
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .rotationEffect(.degrees(isPressed ? 45 : 0))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(isPressed ? 0.18 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .shadow(color: Color.black.opacity(0.2), radius: isPressed ? 5 : 10, x: 0, y: isPressed ? 3 : 8)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
        )
    }

    private func iconForType(_ type: RelatedDataItem.DataType) -> String {
        switch type {
        case .event:
            return "calendar"
        case .note:
            return "doc.text.fill"
        case .location:
            return "mappin.circle.fill"
        }
    }

    private func gradientColorsForType(_ type: RelatedDataItem.DataType) -> [Color] {
        switch type {
        case .event:
            return [
                Color(red: 0.40, green: 0.65, blue: 0.80),
                Color(red: 0.20, green: 0.34, blue: 0.40)
            ]
        case .note:
            return [
                Color(red: 0.40, green: 0.65, blue: 0.80),
                Color(red: 0.20, green: 0.34, blue: 0.40)
            ]
        case .location:
            return [
                Color(red: 0.40, green: 0.65, blue: 0.80),
                Color(red: 0.20, green: 0.34, blue: 0.40)
            ]
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.timeStyle = .short
            return "Today at \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.timeStyle = .short
            return "Yesterday at \(formatter.string(from: date))"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }
}

// MARK: - Stop Speaking Button
struct StopSpeakingButton: View {
    let colorScheme: ColorScheme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Main button
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.9, green: 0.3, blue: 0.3),
                                Color(red: 0.8, green: 0.2, blue: 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 55, height: 55)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    )
                    .shadow(color: Color(red: 0.9, green: 0.3, blue: 0.3).opacity(0.3), radius: 8, x: 0, y: 4)

                // Stop icon (hand.raised or stop.fill)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Tap to Mute Button
struct TapToMuteButton: View {
    @Binding var isListening: Bool
    let colorScheme: ColorScheme
    let onTap: () -> Void

    var buttonColor: Color {
        // Blue when unmuted/listening, Red when muted
        if isListening {
            return colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40)
        } else {
            return Color(red: 0.9, green: 0.3, blue: 0.3) // Red when muted
        }
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Main button - smaller and cleaner design
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                buttonColor,
                                buttonColor.opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 55, height: 55)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                    )
                    .shadow(color: buttonColor.opacity(0.3), radius: 8, x: 0, y: 4)

                // Microphone icon - smaller and cleaner
                Image(systemName: isListening ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .scaleEffect(isListening ? 1.05 : 1.0)
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isListening)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Voice Settings View
struct VoiceSettingsView: View {
    @Binding var selectedVoice: String
    @Environment(\.dismiss) private var dismiss

    let voices: [(id: String, name: String, description: String)] = [
        ("alloy", "Alloy", "Neutral and balanced"),
        ("echo", "Echo", "Clear male voice"),
        ("fable", "Fable", "Expressive and warm"),
        ("onyx", "Onyx", "Deep male voice"),
        ("nova", "Nova", "Friendly female voice"),
        ("shimmer", "Shimmer", "Soft female voice")
    ]

    var body: some View {
        NavigationView {
            List {
                ForEach(voices, id: \.id) { voice in
                    Button(action: {
                        selectedVoice = voice.id
                        HapticManager.shared.selection()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(voice.name)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.primary)

                                Text(voice.description)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if selectedVoice == voice.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color(red: 0.27, green: 0.27, blue: 0.27))
                                    .font(.system(size: 20))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Voice Selection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Formatted Message Text
struct FormattedMessageText: View {
    let text: String
    let isUser: Bool
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseFormattedText(text), id: \.id) { element in
                switch element.type {
                case .text:
                    Text(element.content)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(isUser ? .white : (colorScheme == .dark ? .white : .black))
                        .frame(maxWidth: .infinity, alignment: .leading)

                case .bulletPoint:
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isUser ? .white.opacity(0.8) : (colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40)))

                        Text(element.content)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(isUser ? .white : (colorScheme == .dark ? .white : .black))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                case .numberedItem:
                    HStack(alignment: .top, spacing: 8) {
                        Text(element.number ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isUser ? .white.opacity(0.8) : (colorScheme == .dark ? Color(red: 0.40, green: 0.65, blue: 0.80) : Color(red: 0.20, green: 0.34, blue: 0.40)))

                        Text(element.content)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(isUser ? .white : (colorScheme == .dark ? .white : .black))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parseFormattedText(_ text: String) -> [FormattedTextElement] {
        var elements: [FormattedTextElement] = []
        let lines = text.components(separatedBy: .newlines)

        var currentParagraph = ""

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                // Empty line - add current paragraph if exists
                if !currentParagraph.isEmpty {
                    elements.append(FormattedTextElement(type: .text, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                continue
            }

            // Check for bullet points (•, -, *)
            if trimmedLine.hasPrefix("• ") || trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                // Add current paragraph first if exists
                if !currentParagraph.isEmpty {
                    elements.append(FormattedTextElement(type: .text, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }

                let content = String(trimmedLine.dropFirst(2))
                elements.append(FormattedTextElement(type: .bulletPoint, content: content))
                continue
            }

            // Check for numbered items (1., 2., etc.)
            if let range = trimmedLine.range(of: "^(\\d+)\\.\\s+", options: .regularExpression) {
                // Add current paragraph first if exists
                if !currentParagraph.isEmpty {
                    elements.append(FormattedTextElement(type: .text, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }

                let number = String(trimmedLine[range]).trimmingCharacters(in: .whitespaces)
                let content = String(trimmedLine[range.upperBound...])
                elements.append(FormattedTextElement(type: .numberedItem, content: content, number: number))
                continue
            }

            // Regular text - add to current paragraph
            if !currentParagraph.isEmpty {
                currentParagraph += " "
            }
            currentParagraph += trimmedLine
        }

        // Add any remaining paragraph
        if !currentParagraph.isEmpty {
            elements.append(FormattedTextElement(type: .text, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
        }

        // If no elements, add the raw text
        if elements.isEmpty {
            elements.append(FormattedTextElement(type: .text, content: text))
        }

        return elements
    }
}

struct FormattedTextElement: Identifiable {
    let id = UUID()
    let type: ElementType
    let content: String
    let number: String?

    enum ElementType {
        case text
        case bulletPoint
        case numberedItem
    }

    init(type: ElementType, content: String, number: String? = nil) {
        self.type = type
        self.content = content
        self.number = number
    }
}

// MARK: - Event Confirmation View

struct EventConfirmationView: View {
    let eventData: EventCreationData?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Centered confirmation card
            VStack(spacing: 0) {
                if let event = eventData {
                    let _ = print("📅 Event Confirmation View - Title: \(event.title), Date: '\(event.date)', Time: \(event.time ?? "nil"), IsAllDay: \(event.isAllDay)")

                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.34, blue: 0.40))
                            .frame(width: 56, height: 56)

                        Image(systemName: "calendar")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                    // Title
                    Text("Confirm Event")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.bottom, 6)

                    // Event details
                    VStack(alignment: .leading, spacing: 14) {
                        // Event Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Title")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(event.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }

                        Divider()

                        // Date
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Date")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(formatDate(event.date))
                                .font(.system(size: 15))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                        }

                        // Time
                        if let time = event.time, !event.isAllDay {
                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Time")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(time)
                                    .font(.system(size: 15))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                            }
                        } else if event.isAllDay {
                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Time")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("All Day")
                                    .font(.system(size: 15))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                            }
                        }

                        // Recurrence
                        if let recurrence = event.recurrenceFrequency {
                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Repeats")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(recurrence)
                                    .font(.system(size: 15))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                            }
                        }

                        // Description
                        if let description = event.description, !description.isEmpty {
                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Description")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(description)
                                    .font(.system(size: 14))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : .black.opacity(0.75))
                                    .lineLimit(3)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                    // Buttons
                    HStack(spacing: 10) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
                                )
                        }

                        Button(action: onConfirm) {
                            Text("Confirm")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.27, green: 0.27, blue: 0.27))
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 30, x: 0, y: 10)
            )
        }
    }

    private func formatDate(_ dateString: String) -> String {
        print("🗓️ Formatting date string: '\(dateString)'")

        // CRITICAL FIX: Parse the date string in LOCAL timezone, not UTC
        // ISO8601DateFormatter defaults to UTC which causes timezone offset issues

        // Use standard DateFormatter with local timezone
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        inputFormatter.timeZone = TimeZone.current // Use local timezone
        inputFormatter.locale = Locale.current

        if let date = inputFormatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "EEEE, MMMM d, yyyy"
            displayFormatter.timeZone = TimeZone.current // Display in local timezone
            displayFormatter.locale = Locale.current
            let formattedString = displayFormatter.string(from: date)
            print("✅ Successfully formatted date: \(formattedString)")
            print("✅ Timezone used: \(TimeZone.current.identifier)")
            return formattedString
        }

        print("⚠️ Could not parse date string, returning as-is")
        return dateString
    }
}

// MARK: - Note Confirmation View

struct NoteConfirmationView: View {
    let noteData: NoteCreationData?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Centered confirmation card
            VStack(spacing: 0) {
                if let note = noteData {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 56, height: 56)

                        Image(systemName: "note.text")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                    // Title
                    Text("Confirm Note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.bottom, 6)

                    // Note details
                    VStack(alignment: .leading, spacing: 14) {
                        // Note Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Title")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(note.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }

                        Divider()

                        // Content Preview
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Content")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            ScrollView {
                                Text(note.formattedContent)
                                    .font(.system(size: 14))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                    // Buttons
                    HStack(spacing: 10) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
                                )
                        }

                        Button(action: onConfirm) {
                            Text("Confirm")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.green)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 30, x: 0, y: 10)
            )
        }
    }
}

// MARK: - Note Update Confirmation View

struct NoteUpdateConfirmationView: View {
    let updateData: NoteUpdateData?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Centered confirmation card
            VStack(spacing: 0) {
                if let update = updateData {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 56, height: 56)

                        Image(systemName: "pencil")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                    // Title
                    Text("Update Note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.bottom, 6)

                    // Update details
                    VStack(alignment: .leading, spacing: 14) {
                        // Note Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Note")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(update.noteTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }

                        Divider()

                        // Content to Add Preview
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adding")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            ScrollView {
                                Text(update.formattedContentToAdd)
                                    .font(.system(size: 14))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.75))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 160)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                    // Buttons
                    HStack(spacing: 10) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
                                )
                        }

                        Button(action: onConfirm) {
                            Text("Update")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.orange)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 30, x: 0, y: 10)
            )
        }
    }
}

// MARK: - Event Update Confirmation View

struct EventUpdateConfirmationView: View {
    let updateData: EventUpdateData?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Centered confirmation card
            VStack(spacing: 0) {
                if let update = updateData {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.20, green: 0.34, blue: 0.40))
                            .frame(width: 56, height: 56)

                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                    // Title
                    Text("Confirm Event Update")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.bottom, 6)

                    // Details
                    VStack(alignment: .leading, spacing: 14) {
                        // Event Title
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Event")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(update.eventTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                        }

                        Divider()

                        // New Date
                        VStack(alignment: .leading, spacing: 4) {
                            Text("New Date")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(formattedDate(update.newDate))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }

                        // New Time (if provided)
                        if let newTime = update.newTime, !newTime.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("New Time")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text(newTime)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                    // Buttons
                    HStack(spacing: 10) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
                                )
                        }

                        Button(action: onConfirm) {
                            Text("Update")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 0.27, green: 0.27, blue: 0.27))
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 30, x: 0, y: 10)
            )
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        // Parse the ISO8601 date string (YYYY-MM-DD format)
        let components = dateString.split(separator: "-").compactMap { Int($0) }
        if components.count == 3 {
            let calendar = Calendar.current
            var dateComponents = DateComponents()
            dateComponents.year = components[0]
            dateComponents.month = components[1]
            dateComponents.day = components[2]

            if let date = calendar.date(from: dateComponents) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateStyle = .full
                displayFormatter.timeZone = TimeZone.current
                return displayFormatter.string(from: date)
            }
        }

        // Fallback to ISO8601DateFormatter if the above doesn't work
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .full
            displayFormatter.timeZone = TimeZone.current
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

// MARK: - Deletion Confirmation View

struct DeletionConfirmationView: View {
    let deletionData: DeletionData?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Centered confirmation card
            VStack(spacing: 0) {
                if let deletion = deletionData {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 56, height: 56)

                        Image(systemName: "trash")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                    // Title
                    Text("Confirm Deletion")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.bottom, 6)

                    // Description
                    VStack(alignment: .center, spacing: 14) {
                        Text("Are you sure you want to delete this \(deletion.itemType)?")
                            .font(.system(size: 16))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.75))
                            .multilineTextAlignment(.center)

                        Divider()

                        // Item details
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Item")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(deletion.itemTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Show deletion info for recurring events
                        if deletion.itemType == "event" && deletion.deleteAllOccurrences == true {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Scope")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                                Text("All occurrences")
                                    .font(.system(size: 14))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                    // Buttons
                    HStack(spacing: 10) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill((colorScheme == .dark ? Color.white : Color.black).opacity(0.08))
                                )
                        }

                        Button(action: onConfirm) {
                            Text("Delete")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.red)
                                )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(colorScheme == .dark ? Color(UIColor.systemGray6) : Color.white)
                    .shadow(color: Color.black.opacity(0.15), radius: 30, x: 0, y: 10)
            )
        }
    }
}

// MARK: - Preview
struct VoiceAssistantView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceAssistantView()
            .preferredColorScheme(.dark)
    }
}
