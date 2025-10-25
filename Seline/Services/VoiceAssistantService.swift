import Foundation
import Speech
import AVFoundation
import CoreLocation

class VoiceAssistantService: NSObject, ObservableObject {
    static let shared = VoiceAssistantService()

    // MARK: - Published Properties
    @Published var conversationHistory: [ConversationMessage] = []
    @Published var currentState: VoiceAssistantState = .idle
    @Published var isProcessing = false
    @Published var currentTranscription = ""

    // Event and Note Creation
    @Published var pendingEventCreation: EventCreationData?
    @Published var pendingEventUpdate: EventUpdateData?
    @Published var pendingDeletion: DeletionData?
    @Published var pendingNoteCreation: NoteCreationData?
    @Published var pendingNoteUpdate: NoteUpdateData?
    @Published var showEventConfirmation = false
    @Published var showEventUpdateConfirmation = false
    @Published var showDeletionConfirmation = false
    @Published var showNoteConfirmation = false
    @Published var showNoteUpdateConfirmation = false

    // Voice selection
    var selectedVoice: String = "nova"

    // MARK: - Speech Recognition
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var hasTapInstalled = false

    // MARK: - Text-to-Speech
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Managers
    private let taskManager = TaskManager.shared
    private let notesManager = NotesManager.shared
    private let locationsManager = LocationsManager.shared
    private let emailService = EmailService.shared
    private let openAIService = OpenAIService.shared
    private let weatherService = WeatherService.shared
    private let newsService = NewsService.shared

    private override init() {
        super.init()
        speechSynthesizer.delegate = self
        requestSpeechAuthorization()
    }

    // MARK: - Authorization

    func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                switch authStatus {
                case .authorized:
                    print("✅ Speech recognition authorized")
                case .denied:
                    print("❌ Speech recognition denied")
                    self?.currentState = .error("Speech recognition permission denied")
                case .restricted:
                    print("❌ Speech recognition restricted")
                    self?.currentState = .error("Speech recognition restricted")
                case .notDetermined:
                    print("⚠️ Speech recognition not determined")
                @unknown default:
                    print("❌ Unknown authorization status")
                }
            }
        }
    }

    // MARK: - Speech Recognition

    func startListening() {
        // Stop any ongoing recognition
        if recognitionTask != nil {
            stopListening()
        }

        // Reset audio engine completely
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        audioEngine.reset()

        // Configure audio session with better settings
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])
            // Don't force sample rate - let the system use its native rate
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            // Balanced wait time - fast but reliable
            Thread.sleep(forTimeInterval: 0.15)
            print("🎤 Audio session sample rate: \(audioSession.sampleRate) Hz")
        } catch {
            print("❌ Audio session error: \(error)")
            currentState = .error("Failed to configure audio session")
            return
        }

        // Create recognition request with enhanced settings
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            currentState = .error("Failed to create recognition request")
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        // Enable better recognition
        if #available(iOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false
        }

        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true
            recognitionRequest.contextualStrings = ["notes", "events", "calendar", "location", "restaurant", "coffee", "password"]
        }

        // Get audio input node
        let inputNode = audioEngine.inputNode

        // Get the output format from the input node
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Validate the format before installing tap
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("❌ Invalid recording format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")
            currentState = .error("Invalid audio format")
            return
        }

        print("🎤 Recording format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")

        // Install tap on audio input using the node's native output format
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        hasTapInstalled = true
        print("✅ Audio tap installed successfully")

        // Start audio engine with retry logic
        audioEngine.prepare()

        var engineStartAttempts = 0
        let maxEngineAttempts = 3
        var engineStarted = false

        while engineStartAttempts < maxEngineAttempts && !engineStarted {
            do {
                try audioEngine.start()
                engineStarted = true
                print("✅ Audio engine started successfully")
            } catch {
                engineStartAttempts += 1
                print("⚠️ Audio engine start attempt \(engineStartAttempts) failed: \(error)")

                if engineStartAttempts < maxEngineAttempts {
                    Thread.sleep(forTimeInterval: 0.2)
                    audioEngine.prepare()
                } else {
                    print("❌ Audio engine failed to start after \(maxEngineAttempts) attempts")
                    currentState = .error("Failed to start audio engine")
                    hasTapInstalled = false
                    return
                }
            }
        }

        // Start recognition
        currentState = .listening

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ Recognition error: \(error)")
                DispatchQueue.main.async {
                    self.currentTranscription = ""
                }
                self.stopListening()
                return
            }

            if let result = result {
                let transcription = result.bestTranscription.formattedString

                // Update current transcription for live feedback
                DispatchQueue.main.async {
                    self.currentTranscription = transcription
                }

                // Only auto-process if it's a final result (for compatibility)
                if result.isFinal {
                    print("✅ Final transcription: \(transcription)")
                    self.stopListening()
                    self.processUserQuery(transcription)
                }
            }
        }
    }

    func startListeningWithSilenceDetection() {
        // Stop speaking if AI is currently speaking (user is interrupting)
        let wasInterrupted = currentState == .speaking
        if wasInterrupted {
            print("🎤 User interrupted AI, stopping playback...")
            stopSpeaking()
            // CRITICAL: Give extra time for audio session to fully clean up after interruption
            Thread.sleep(forTimeInterval: 0.3)
        }

        // Stop any ongoing recognition and ensure audio engine is fully stopped
        if recognitionTask != nil || audioEngine.isRunning {
            stopListening()
        }

        // Ensure audio engine is completely stopped and reset before reconfiguring
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // Remove any existing tap to fully reset the audio engine
        if hasTapInstalled {
            let inputNode = audioEngine.inputNode
            inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }

        // Reset the audio engine to pick up new configuration
        audioEngine.reset()
        print("✅ Audio engine reset and ready for new configuration")

        // Configure audio session with better settings for voice recognition
        let audioSession = AVAudioSession.sharedInstance()

        // Retry mechanism for audio session configuration
        var configurationAttempts = 0
        let maxAttempts = 3

        while configurationAttempts < maxAttempts {
            do {
                // First ensure previous session is completely deactivated
                try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)

                // Longer delay for interruption case, shorter for normal case
                let delay = wasInterrupted ? 0.25 : 0.1
                Thread.sleep(forTimeInterval: delay)

                // Use .measurement mode for reliable speech recognition with high priority
                try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetoothHFP])

                // Don't force a specific sample rate - let the system use its native rate
                // This prevents format mismatch errors
                // The audio engine will automatically handle sample rate conversion

                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

                // Longer wait time after interruption to ensure proper transition
                let activationWait = wasInterrupted ? 0.25 : 0.15
                Thread.sleep(forTimeInterval: activationWait)

                print("✅ Audio session configured for recording (attempt \(configurationAttempts + 1))")
                print("🎤 Audio session sample rate: \(audioSession.sampleRate) Hz")
                break // Success, exit retry loop
            } catch {
                configurationAttempts += 1
                print("⚠️ Audio session error (attempt \(configurationAttempts)): \(error)")

                if configurationAttempts >= maxAttempts {
                    print("❌ Failed to configure audio session after \(maxAttempts) attempts")
                    currentState = .error("Failed to configure audio session")
                    return
                }

                // Longer wait before retrying, especially after interruption
                let retryWait = wasInterrupted ? 0.4 : 0.3
                Thread.sleep(forTimeInterval: retryWait)
            }
        }

        // Create recognition request with better settings
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            currentState = .error("Failed to create recognition request")
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        // Enable on-device recognition if available for better accuracy and privacy
        if #available(iOS 13.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = false // Use server for best accuracy
        }

        // Add context strings to improve recognition of common words
        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true
            // Add context for better recognition
            let contextualStrings = ["notes", "events", "calendar", "location", "restaurant", "coffee", "password"]
            recognitionRequest.contextualStrings = contextualStrings
        }

        // Get audio input node with fresh configuration
        let inputNode = audioEngine.inputNode

        // CRITICAL: Get the output format from the input node
        // This is the format that the mic provides to the audio engine
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Validate the format before installing tap
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            print("❌ Invalid recording format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")
            currentState = .error("Invalid audio format")
            return
        }

        print("🎤 Recording format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) channels")
        print("🎤 Hardware input format: \(inputNode.inputFormat(forBus: 0).sampleRate) Hz")

        // Install tap on audio input using the node's native output format
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        hasTapInstalled = true
        print("✅ Tap installed successfully")

        // Start audio engine with retry logic
        audioEngine.prepare()

        var engineStartAttempts = 0
        let maxEngineAttempts = 3
        var engineStarted = false

        while engineStartAttempts < maxEngineAttempts && !engineStarted {
            do {
                try audioEngine.start()
                engineStarted = true
                print("✅ Audio engine started successfully")
            } catch {
                engineStartAttempts += 1
                print("⚠️ Audio engine start attempt \(engineStartAttempts) failed: \(error)")

                if engineStartAttempts < maxEngineAttempts {
                    // Progressive delay: longer wait for each retry attempt
                    let retryDelay = wasInterrupted ? 0.4 : 0.2 + (Double(engineStartAttempts) * 0.1)
                    print("⏳ Waiting \(retryDelay)s before retry...")
                    Thread.sleep(forTimeInterval: retryDelay)

                    // Re-prepare the engine
                    audioEngine.prepare()
                } else {
                    print("❌ Audio engine failed to start after \(maxEngineAttempts) attempts")
                    currentState = .error("Failed to start audio engine")
                    hasTapInstalled = false
                    return
                }
            }
        }

        // Start recognition
        currentState = .listening

        // Track silence detection with longer timing to allow full sentences
        var lastSpeechTime = Date()
        let silenceThreshold: TimeInterval = 3.0 // 3 seconds to allow user to finish speaking
        var hasProcessed = false // Prevent duplicate processing

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                let nsError = error as NSError
                // Ignore cancellation errors as they're expected
                if nsError.domain != "kLSRErrorDomain" || nsError.code != 301 {
                    print("❌ Recognition error: \(error)")
                }
                DispatchQueue.main.async {
                    self.currentTranscription = ""
                }
                return
            }

            if let result = result {
                let transcription = result.bestTranscription.formattedString
                lastSpeechTime = Date()
                hasProcessed = false

                // Update current transcription for live feedback
                DispatchQueue.main.async {
                    self.currentTranscription = transcription
                }

                // Check for silence after each update
                DispatchQueue.main.asyncAfter(deadline: .now() + silenceThreshold) {
                    let timeSinceLastSpeech = Date().timeIntervalSince(lastSpeechTime)
                    if timeSinceLastSpeech >= silenceThreshold &&
                       self.currentState == .listening &&
                       !transcription.isEmpty &&
                       !hasProcessed {
                        hasProcessed = true
                        print("✅ Detected silence, processing: \(transcription)")
                        self.processUserQuery(transcription)
                        DispatchQueue.main.async {
                            self.currentTranscription = ""
                        }
                    }
                }
            }
        }
    }

    func stopListeningAndProcess() {
        let transcription = currentTranscription
        stopListening()

        if !transcription.isEmpty {
            processUserQuery(transcription)
        }

        // Reset transcription
        DispatchQueue.main.async {
            self.currentTranscription = ""
        }
    }

    func stopListening() {
        // Safely stop the audio engine if it's running
        if audioEngine.isRunning {
            // Stop the engine first
            audioEngine.stop()

            // Only remove tap if we know one was installed
            if hasTapInstalled {
                let inputNode = audioEngine.inputNode
                inputNode.removeTap(onBus: 0)
                hasTapInstalled = false
                print("✅ Audio engine tap removed successfully")
            }

            print("✅ Audio engine stopped successfully")
        }

        // End the recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        // Deactivate the recording audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("✅ Audio session deactivated successfully")
        } catch {
            print("⚠️ Error deactivating recording audio session: \(error)")
        }

        if currentState == .listening {
            currentState = .idle
        }
    }

    // MARK: - Query Processing

    private func processUserQuery(_ query: String) {
        // Stop listening completely before processing to avoid audio conflicts
        stopListening()

        currentState = .processing
        isProcessing = true

        // Add user message to conversation
        let userMessage = ConversationMessage(isUser: true, text: query)
        conversationHistory.append(userMessage)

        Task {
            do {
                let startTime = Date()

                // OPTIMIZATION 2: Fetch all data in parallel instead of sequentially
                async let currentLocationAsync = MainActor.run {
                    LocationService.shared.currentLocation
                }
                async let eventsAsync = MainActor.run {
                    taskManager.tasks.values.flatMap { $0 }.filter { !$0.isDeleted }
                }
                async let notesAsync = MainActor.run {
                    notesManager.notes
                }
                async let locationsAsync = MainActor.run {
                    locationsManager.savedPlaces
                }
                async let inboxEmailsAsync = MainActor.run {
                    emailService.inboxEmails
                }
                async let sentEmailsAsync = MainActor.run {
                    emailService.sentEmails
                }
                async let weatherDataAsync = MainActor.run {
                    weatherService.weatherData
                }
                async let newsAsync = MainActor.run {
                    newsService.getAllNews()
                }

                // Await all data fetches concurrently
                let currentLocation = await currentLocationAsync
                let events = await eventsAsync
                let notes = await notesAsync
                let locations = await locationsAsync
                let inboxEmails = await inboxEmailsAsync
                let sentEmails = await sentEmailsAsync
                let weatherData = await weatherDataAsync
                let allNewsByCategory = await newsAsync

                // Build conversation context for OpenAI
                let conversationContext = conversationHistory.map { message in
                    ["role": message.isUser ? "user" : "assistant", "content": message.text]
                }

                let totalNewsCount = allNewsByCategory.reduce(0) { $0 + $1.articles.count }
                let dataFetchTime = Date().timeIntervalSince(startTime)
                print("📊 Parallel data fetch completed in \(String(format: "%.2f", dataFetchTime))s")
                print("📊 Sending to AI: \(notes.count) notes, \(events.count) events (ALL - past/present/future), \(locations.count) locations, \(inboxEmails.count) inbox emails, \(sentEmails.count) sent emails, weather: \(weatherData != nil ? "yes" : "no"), news: \(totalNewsCount) articles across \(allNewsByCategory.count) categories")

                let response = try await openAIService.processVoiceQuery(
                    query: query,
                    events: events,
                    notes: notes,
                    locations: locations,
                    currentLocation: currentLocation,
                    weatherData: weatherData,
                    allNewsByCategory: allNewsByCategory,
                    inboxEmails: inboxEmails,
                    sentEmails: sentEmails,
                    conversationHistory: conversationContext
                )

                // Check for action requests (event/note creation)
                let action = response.getAction()

                if action == .createEvent, let eventData = response.eventData {
                    // Handle event creation
                    await MainActor.run {
                        pendingEventCreation = eventData

                        if eventData.requiresFollowUp, let _ = response.followUpQuestion {
                            // Ask for clarification
                            let clarificationMessage = ConversationMessage(
                                isUser: false,
                                text: response.response,
                                intent: response.getIntent()
                            )
                            conversationHistory.append(clarificationMessage)
                            isProcessing = false
                            speakResponse(response.response)
                        } else {
                            // Show confirmation dialog
                            showEventConfirmation = true
                            let confirmMessage = ConversationMessage(
                                isUser: false,
                                text: response.response,
                                intent: response.getIntent()
                            )
                            conversationHistory.append(confirmMessage)
                            isProcessing = false
                            speakResponse(response.response)
                        }
                    }
                } else if action == .createNote, let noteData = response.noteData {
                    // Handle note creation
                    await MainActor.run {
                        pendingNoteCreation = noteData
                        showNoteConfirmation = true

                        let confirmMessage = ConversationMessage(
                            isUser: false,
                            text: response.response,
                            intent: response.getIntent()
                        )
                        conversationHistory.append(confirmMessage)
                        isProcessing = false
                        speakResponse(response.response)
                    }
                } else if action == .updateNote, let noteUpdateData = response.noteUpdateData {
                    // Handle note update
                    await MainActor.run {
                        pendingNoteUpdate = noteUpdateData
                        showNoteUpdateConfirmation = true

                        let confirmMessage = ConversationMessage(
                            isUser: false,
                            text: response.response,
                            intent: response.getIntent()
                        )
                        conversationHistory.append(confirmMessage)
                        isProcessing = false
                        speakResponse(response.response)
                    }
                } else if action == .updateEvent, let eventUpdateData = response.eventUpdateData {
                    // Handle event update (reschedule) - show popup for confirmation
                    await MainActor.run {
                        pendingEventUpdate = eventUpdateData
                        showEventUpdateConfirmation = true

                        let confirmMessage = ConversationMessage(
                            isUser: false,
                            text: response.response,
                            intent: response.getIntent()
                        )
                        conversationHistory.append(confirmMessage)
                        isProcessing = false
                        // Don't speak yet - wait for user to confirm in the popup
                    }
                } else if action == .deleteEvent, let deletionData = response.deletionData, deletionData.itemType == "event" {
                    // Handle event deletion
                    await MainActor.run {
                        pendingDeletion = deletionData
                        showDeletionConfirmation = true

                        let confirmMessage = ConversationMessage(
                            isUser: false,
                            text: response.response,
                            intent: response.getIntent()
                        )
                        conversationHistory.append(confirmMessage)
                        isProcessing = false
                        speakResponse(response.response)
                    }
                } else if action == .deleteNote, let deletionData = response.deletionData, deletionData.itemType == "note" {
                    // Handle note deletion
                    await MainActor.run {
                        pendingDeletion = deletionData
                        showDeletionConfirmation = true

                        let confirmMessage = ConversationMessage(
                            isUser: false,
                            text: response.response,
                            intent: response.getIntent()
                        )
                        conversationHistory.append(confirmMessage)
                        isProcessing = false
                        speakResponse(response.response)
                    }
                } else {
                    // Regular query processing (no action)
                    // Create assistant message with related data
                    var relatedData: [RelatedDataItem] = []

                    // Fetch related data based on intent
                    switch response.getIntent() {
                    case .calendar:
                        relatedData = await fetchCalendarData(searchQuery: response.searchQuery, dateRange: response.dateRange)
                    case .notes:
                        relatedData = fetchNotesData(searchQuery: response.searchQuery)
                    case .locations:
                        relatedData = fetchLocationsData(category: response.category, searchQuery: response.searchQuery)
                    case .general:
                        break
                    }

                    let assistantMessage = ConversationMessage(
                        isUser: false,
                        text: response.response,
                        intent: response.getIntent(),
                        relatedData: relatedData.isEmpty ? nil : relatedData
                    )

                    await MainActor.run {
                        conversationHistory.append(assistantMessage)
                        isProcessing = false
                        // Speak the response
                        speakResponse(response.response)
                    }
                }

            } catch {
                print("❌ Error processing query: \(error)")
                await MainActor.run {
                    let errorMessage = ConversationMessage(
                        isUser: false,
                        text: "I'm sorry, I encountered an error processing your request. Please try again."
                    )
                    conversationHistory.append(errorMessage)
                    isProcessing = false
                    currentState = .idle // Changed from .error to .idle to allow recovery
                }
            }
        }
    }

    // MARK: - Data Fetching

    private func fetchCalendarData(searchQuery: String?, dateRange: VoiceQueryResponse.DateRangeQuery?) async -> [RelatedDataItem] {
        var events: [TaskItem] = []

        // Determine the date range for fetching tasks
        var fetchStartDate = Date()
        var fetchEndDate = Date().addingTimeInterval(7 * 24 * 60 * 60) // Default to 7 days ahead

        // If dateRange is provided, use it for fetching
        let formatter = ISO8601DateFormatter()
        if let dateRange = dateRange {
            if let startDateStr = dateRange.startDate, let startDate = formatter.date(from: startDateStr) {
                fetchStartDate = startDate
            }
            if let endDateStr = dateRange.endDate, let endDate = formatter.date(from: endDateStr) {
                fetchEndDate = endDate
            }
        }

        // Fetch all tasks for the date range
        await MainActor.run {
            var allTasks: [TaskItem] = []
            let calendar = Calendar.current
            let components = calendar.dateComponents([.day], from: fetchStartDate, to: fetchEndDate)
            let daysInRange = (components.day ?? 0) + 1

            // Fetch tasks for each day in the range
            for dayOffset in 0..<daysInRange {
                if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: fetchStartDate) {
                    let dayTasks = taskManager.getAllTasks(for: dayDate)
                    allTasks.append(contentsOf: dayTasks)
                }
            }

            events = allTasks
        }

        // Filter by search query if provided
        if let searchQuery = searchQuery, !searchQuery.isEmpty {
            events = events.filter { event in
                event.title.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // Filter by date range to ensure we only include events within the requested range
        if let dateRange = dateRange {
            if let startDateStr = dateRange.startDate, let startDate = formatter.date(from: startDateStr) {
                events = events.filter { event in
                    let eventDate = event.targetDate ?? event.scheduledTime
                    if let eventDate = eventDate {
                        return eventDate >= startDate
                    }
                    return false
                }
            }
            if let endDateStr = dateRange.endDate, let endDate = formatter.date(from: endDateStr) {
                // Adjust end date to include the entire day (add 1 second before end of day)
                let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                events = events.filter { event in
                    let eventDate = event.targetDate ?? event.scheduledTime
                    if let eventDate = eventDate {
                        return eventDate <= endOfDay
                    }
                    return false
                }
            }
        }

        // Sort by date (earliest first)
        events = events.sorted { event1, event2 in
            let date1 = event1.targetDate ?? event1.scheduledTime ?? event1.createdAt
            let date2 = event2.targetDate ?? event2.scheduledTime ?? event2.createdAt
            return date1 < date2
        }

        // Convert to RelatedDataItem (limit to 10 to show more events)
        return events.prefix(10).map { event in
            RelatedDataItem(
                type: .event,
                title: event.title,
                subtitle: event.formattedTimeRange.isEmpty ? event.weekday.displayName : event.formattedTimeRange,
                date: event.scheduledTime ?? event.createdAt
            )
        }
    }

    private func fetchNotesData(searchQuery: String?) -> [RelatedDataItem] {
        var notes: [Note] = []

        // Filter by search query if provided
        if let searchQuery = searchQuery, !searchQuery.isEmpty {
            notes = notesManager.searchNotes(query: searchQuery)
        } else {
            // Return recent notes
            notes = notesManager.recentNotes
        }

        // Convert to RelatedDataItem (limit to 5)
        return notes.prefix(5).map { note in
            RelatedDataItem(
                type: .note,
                title: note.title,
                subtitle: note.preview,
                date: note.dateModified
            )
        }
    }

    private func fetchLocationsData(category: String?, searchQuery: String?) -> [RelatedDataItem] {
        var places: [SavedPlace] = []

        // Filter by search query if provided
        if let searchQuery = searchQuery, !searchQuery.isEmpty {
            places = locationsManager.searchPlaces(query: searchQuery)
        } else if let category = category, !category.isEmpty {
            // Filter by category
            places = locationsManager.savedPlaces.filter { $0.category.localizedCaseInsensitiveContains(category) }
        } else {
            places = locationsManager.savedPlaces
        }

        // Sort by most recent
        places = places.sorted { $0.dateModified > $1.dateModified }

        // Convert to RelatedDataItem (limit to 5)
        return places.prefix(5).map { place in
            RelatedDataItem(
                type: .location,
                title: place.displayName,
                subtitle: place.formattedAddress,
                date: place.dateModified
            )
        }
    }

    // MARK: - Text-to-Speech

    private func speakResponse(_ text: String) {
        currentState = .speaking

        Task {
            do {
                // Use OpenAI TTS for natural voice - speak immediately
                print("🎤 Using voice: \(selectedVoice)")
                try await speakWithOpenAI(text)
            } catch {
                print("❌ OpenAI TTS failed, falling back to system voice: \(error)")
                // Fallback to system voice
                await MainActor.run {
                    speakWithSystemVoice(text)
                }
            }
        }
    }

    private func speakWithOpenAI(_ text: String) async throws {
        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20.0 // 20 second timeout for TTS

        let requestBody: [String: Any] = [
            "model": "tts-1", // Faster model for real-time use
            "input": text,
            "voice": selectedVoice, // User-selected voice
            "speed": 1.1 // Slightly faster for more responsive feel
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("🎤 Requesting OpenAI TTS...")
        let startTime = Date()

        // Use custom URLSession with timeout configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20.0
        config.timeoutIntervalForResource = 30.0
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)

        let elapsedTime = Date().timeIntervalSince(startTime)
        print("✅ TTS response received in \(String(format: "%.2f", elapsedTime))s")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenAITTS", code: -1, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }

        print("🎤 TTS Response status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ TTS Error: \(errorMessage)")
            throw NSError(domain: "OpenAITTS", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "TTS request failed: \(errorMessage)"])
        }

        print("✅ TTS audio data received: \(data.count) bytes")

        // Configure audio session for playback with minimal delay
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // First, make sure recording is completely stopped
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            // Minimal wait for cleanup (reduced from 0.2s to 0.1s for faster response)
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            // Now set up for playback (without .defaultToSpeaker which is only for playAndRecord)
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
            print("✅ Audio session configured for playback")
        } catch {
            print("❌ Failed to configure audio session for playback: \(error)")
            throw error
        }

        // Play the audio immediately
        await MainActor.run {
            do {
                self.audioPlayer = try AVAudioPlayer(data: data)
                self.audioPlayer?.volume = 1.0
                // Prepare the audio player (pre-loads the buffer for immediate playback)
                self.audioPlayer?.prepareToPlay()

                guard let duration = self.audioPlayer?.duration else {
                    print("❌ Could not get audio duration")
                    self.currentState = .idle
                    return
                }

                print("🔊 Starting audio playback (duration: \(String(format: "%.2f", duration))s)")
                // Start playback immediately - no delay
                let didPlay = self.audioPlayer?.play() ?? false
                print("🔊 Audio playing: \(didPlay)")

                if !didPlay {
                    print("❌ Failed to start audio playback")
                    self.currentState = .idle
                }

                // Set a timer to detect when playback finishes
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.5) {
                    print("🔊 Audio playback finished")
                    if self.currentState == .speaking {
                        // Deactivate playback audio session and ensure proper cleanup
                        Task {
                            do {
                                let audioSession = AVAudioSession.sharedInstance()
                                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                                // Balanced delay - enough for cleanup but faster than before
                                try await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
                            } catch {
                                print("❌ Error deactivating audio session: \(error)")
                            }

                            await MainActor.run {
                                self.currentState = .idle
                                // Auto-restart listening with minimal delay for faster response
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    print("🎤 Auto-restarting listening for follow-up...")
                                    if self.currentState == .idle {
                                        self.startListeningWithSilenceDetection()
                                    }
                                }
                            }
                        }
                    }
                }
            } catch {
                print("❌ Audio player error: \(error)")
                self.currentState = .idle
            }
        }
    }

    private func speakWithSystemVoice(_ text: String) {
        print("⚠️ Using system voice fallback")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Make sure we wait a bit before switching audio session
            Thread.sleep(forTimeInterval: 0.3)
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            // Use .playback category without .defaultToSpeaker option
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("❌ Audio session error for system voice: \(error)")
        }

        speechSynthesizer.speak(utterance)
    }

    func stopSpeaking() {
        // Stop OpenAI audio
        audioPlayer?.stop()
        audioPlayer = nil

        // Stop system voice
        speechSynthesizer.stopSpeaking(at: .immediate)

        // Immediately deactivate the playback audio session for faster transition
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            print("✅ Audio session deactivated immediately for interruption")
        } catch {
            print("⚠️ Could not immediately deactivate audio session: \(error)")
        }

        currentState = .idle
    }

    // MARK: - Conversation Management

    func clearConversation() {
        conversationHistory.removeAll()
        currentState = .idle
    }

    func startNewConversation() {
        stopListening()
        stopSpeaking()
        clearConversation()
    }

    // MARK: - Event & Note Creation Confirmation

    func confirmEventCreation() {
        guard let eventData = pendingEventCreation else {
            print("❌ No pending event to create")
            return
        }

        Task {
            await MainActor.run {
                // Parse the date and time
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]

                guard let eventDate = dateFormatter.date(from: eventData.date) else {
                    print("❌ Failed to parse event date: \(eventData.date)")
                    speakResponse("Sorry, I couldn't parse the event date.")
                    return
                }

                // Parse time if available
                var scheduledTime: Date?
                var endTime: Date?

                if let timeString = eventData.time, !eventData.isAllDay {
                    let timeComponents = timeString.split(separator: ":").compactMap { Int($0) }
                    if timeComponents.count == 2 {
                        let calendar = Calendar.current
                        scheduledTime = calendar.date(bySettingHour: timeComponents[0], minute: timeComponents[1], second: 0, of: eventDate)
                    }
                }

                if let endTimeString = eventData.endTime {
                    let timeComponents = endTimeString.split(separator: ":").compactMap { Int($0) }
                    if timeComponents.count == 2 {
                        let calendar = Calendar.current
                        endTime = calendar.date(bySettingHour: timeComponents[0], minute: timeComponents[1], second: 0, of: eventDate)
                    }
                }

                // Determine weekday from the target date
                let calendar = Calendar.current
                let weekdayComponent = calendar.component(.weekday, from: eventDate)
                let weekday: WeekDay
                switch weekdayComponent {
                case 1: weekday = .sunday
                case 2: weekday = .monday
                case 3: weekday = .tuesday
                case 4: weekday = .wednesday
                case 5: weekday = .thursday
                case 6: weekday = .friday
                case 7: weekday = .saturday
                default: weekday = .monday
                }

                // Map recurrence frequency
                var recurrenceFrequency: RecurrenceFrequency?
                if let frequencyString = eventData.recurrenceFrequency {
                    recurrenceFrequency = RecurrenceFrequency(rawValue: frequencyString)
                }

                // Create the event
                taskManager.addTask(
                    title: eventData.title,
                    to: weekday,
                    description: eventData.description,
                    scheduledTime: scheduledTime,
                    endTime: endTime,
                    targetDate: eventDate,
                    reminderTime: nil,
                    isRecurring: recurrenceFrequency != nil,
                    recurrenceFrequency: recurrenceFrequency
                )

                print("✅ Event created: \(eventData.title) on \(eventDate)")

                // Speak confirmation
                let confirmationText = "Event created: \(eventData.title)"
                speakResponse(confirmationText)

                // Add confirmation message to conversation
                let confirmMessage = ConversationMessage(
                    isUser: false,
                    text: confirmationText,
                    intent: .calendar
                )
                conversationHistory.append(confirmMessage)

                // Clear pending data and hide dialog
                pendingEventCreation = nil
                showEventConfirmation = false
            }
        }
    }

    func confirmNoteCreation() {
        guard let noteData = pendingNoteCreation else {
            print("❌ No pending note to create")
            return
        }

        Task {
            await MainActor.run {
                // Create the note with formatted content
                let note = Note(
                    title: noteData.title,
                    content: noteData.formattedContent
                )
                notesManager.addNote(note)

                print("✅ Note created: \(noteData.title)")

                // Speak confirmation
                let confirmationText = "Note created: \(noteData.title)"
                speakResponse(confirmationText)

                // Add confirmation message to conversation
                let confirmMessage = ConversationMessage(
                    isUser: false,
                    text: confirmationText,
                    intent: .notes
                )
                conversationHistory.append(confirmMessage)

                // Clear pending data and hide dialog
                pendingNoteCreation = nil
                showNoteConfirmation = false
            }
        }
    }

    func cancelEventCreation() {
        Task {
            await MainActor.run {
                pendingEventCreation = nil
                showEventConfirmation = false
            }

            // Don't speak on cancel to avoid audio session conflicts
            // Just silently dismiss
            print("ℹ️ Event creation cancelled by user")
        }
    }

    func cancelNoteCreation() {
        Task {
            await MainActor.run {
                pendingNoteCreation = nil
                showNoteConfirmation = false
            }

            // Don't speak on cancel to avoid audio session conflicts
            // Just silently dismiss
            print("ℹ️ Note creation cancelled by user")
        }
    }

    func confirmNoteUpdate() {
        guard let updateData = pendingNoteUpdate else {
            print("❌ No pending note update")
            return
        }

        Task {
            await MainActor.run {
                // Find the note by title (case-insensitive search)
                if let existingNote = notesManager.notes.first(where: {
                    $0.title.localizedCaseInsensitiveContains(updateData.noteTitle)
                }) {
                    // Append the new content to the existing content
                    let updatedContent = existingNote.content + "\n\n" + updateData.formattedContentToAdd

                    // Create updated note by copying existing note and updating content
                    var updatedNote = existingNote
                    updatedNote.content = updatedContent
                    updatedNote.dateModified = Date()

                    // Update the note
                    notesManager.updateNote(updatedNote)

                    print("✅ Note updated: \(existingNote.title)")

                    // Speak confirmation
                    let confirmationText = "Updated note: \(existingNote.title)"
                    speakResponse(confirmationText)

                    // Add confirmation message to conversation
                    let confirmMessage = ConversationMessage(
                        isUser: false,
                        text: confirmationText,
                        intent: .notes
                    )
                    conversationHistory.append(confirmMessage)
                } else {
                    print("❌ Note not found: \(updateData.noteTitle)")
                    speakResponse("I couldn't find a note with that title.")
                }

                // Clear pending data and hide dialog
                pendingNoteUpdate = nil
                showNoteUpdateConfirmation = false
            }
        }
    }

    func cancelNoteUpdate() {
        Task {
            await MainActor.run {
                pendingNoteUpdate = nil
                showNoteUpdateConfirmation = false
            }

            // Don't speak on cancel to avoid audio session conflicts
            // Just silently dismiss
            print("ℹ️ Note update cancelled by user")
        }
    }

    func confirmEventUpdate() {
        guard let updateData = pendingEventUpdate else {
            print("❌ No pending event update")
            return
        }

        Task {
            await MainActor.run {
                // Find the event by title (case-insensitive search)
                // Search through all tasks to find matching event
                if let existingEvent = taskManager.tasks.values.flatMap({ $0 }).first(where: {
                    $0.title.localizedCaseInsensitiveContains(updateData.eventTitle)
                }) {
                    // Parse the new date directly from YYYY-MM-DD format
                    let dateComponents = updateData.newDate.split(separator: "-").compactMap { Int($0) }
                    guard dateComponents.count == 3 else {
                        print("❌ Failed to parse new event date: \(updateData.newDate)")
                        speakResponse("Sorry, I couldn't parse the new event date.")
                        return
                    }

                    let calendar = Calendar.current
                    var newDateComponents = DateComponents()
                    newDateComponents.year = dateComponents[0]
                    newDateComponents.month = dateComponents[1]
                    newDateComponents.day = dateComponents[2]

                    guard let newEventDate = calendar.date(from: newDateComponents) else {
                        print("❌ Failed to create date from components: \(updateData.newDate)")
                        speakResponse("Sorry, I couldn't parse the new event date.")
                        return
                    }

                    print("📅 DEBUG confirmEventUpdate - Parsed Date: \(newEventDate)")
                    print("📅 DEBUG - Date String Input: \(updateData.newDate)")

                    // Parse new time if provided
                    var newScheduledTime: Date?
                    if let timeString = updateData.newTime {
                        let timeComponents = timeString.split(separator: ":").compactMap { Int($0) }
                        if timeComponents.count == 2 {
                            newScheduledTime = calendar.date(bySettingHour: timeComponents[0], minute: timeComponents[1], second: 0, of: newEventDate)
                        }
                    }

                    // Parse new end time if provided
                    var newEndTime: Date?
                    if let endTimeString = updateData.newEndTime {
                        let timeComponents = endTimeString.split(separator: ":").compactMap { Int($0) }
                        if timeComponents.count == 2 {
                            newEndTime = calendar.date(bySettingHour: timeComponents[0], minute: timeComponents[1], second: 0, of: newEventDate)
                        }
                    }

                    // Determine weekday from the new target date
                    let weekdayComponent = calendar.component(.weekday, from: newEventDate)
                    let weekday: WeekDay
                    switch weekdayComponent {
                    case 1: weekday = .sunday
                    case 2: weekday = .monday
                    case 3: weekday = .tuesday
                    case 4: weekday = .wednesday
                    case 5: weekday = .thursday
                    case 6: weekday = .friday
                    case 7: weekday = .saturday
                    default: weekday = .monday
                    }

                    // Create updated event with new date/time
                    // Note: We need to delete the old event and create a new one since TaskItem properties are immutable
                    let updatedEvent = TaskItem(
                        title: existingEvent.title,
                        weekday: weekday,
                        description: existingEvent.description,
                        scheduledTime: newScheduledTime,
                        endTime: newEndTime,
                        targetDate: newEventDate,
                        reminderTime: existingEvent.reminderTime,
                        isRecurring: existingEvent.isRecurring,
                        recurrenceFrequency: existingEvent.recurrenceFrequency,
                        parentRecurringTaskId: existingEvent.parentRecurringTaskId
                    )

                    // Delete the old event and add the new one
                    taskManager.deleteTask(existingEvent)
                    taskManager.addTask(
                        title: updatedEvent.title,
                        to: updatedEvent.weekday,
                        description: updatedEvent.description,
                        scheduledTime: updatedEvent.scheduledTime,
                        endTime: updatedEvent.endTime,
                        targetDate: updatedEvent.targetDate,
                        reminderTime: updatedEvent.reminderTime,
                        isRecurring: updatedEvent.isRecurring,
                        recurrenceFrequency: updatedEvent.recurrenceFrequency
                    )

                    print("✅ Event moved: \(existingEvent.title) to \(newEventDate)")

                    // Speak confirmation
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .full
                    let formattedDate = dateFormatter.string(from: newEventDate)
                    let confirmationText = "Event rescheduled: \(existingEvent.title) moved to \(formattedDate)"
                    speakResponse(confirmationText)

                    // Add confirmation message to conversation
                    let confirmMessage = ConversationMessage(
                        isUser: false,
                        text: confirmationText,
                        intent: .calendar
                    )
                    conversationHistory.append(confirmMessage)
                } else {
                    print("❌ Event not found: \(updateData.eventTitle)")
                    speakResponse("I couldn't find an event with that title to reschedule.")
                }

                // Clear pending data and hide dialog
                pendingEventUpdate = nil
                showEventUpdateConfirmation = false
            }
        }
    }

    func cancelEventUpdate() {
        Task {
            await MainActor.run {
                pendingEventUpdate = nil
                showEventUpdateConfirmation = false
            }

            // Don't speak on cancel to avoid audio session conflicts
            // Just silently dismiss
            print("ℹ️ Event update cancelled by user")
        }
    }

    func confirmDeletion() {
        guard let deletionData = pendingDeletion else {
            print("❌ No pending deletion")
            return
        }

        Task {
            await MainActor.run {
                if deletionData.itemType == "event" {
                    // Find and delete the event
                    if let eventToDelete = taskManager.tasks.values.flatMap({ $0 }).first(where: {
                        $0.title.localizedCaseInsensitiveContains(deletionData.itemTitle)
                    }) {
                        // Check if it's a recurring event and user wants to delete all occurrences
                        if eventToDelete.isRecurring && deletionData.deleteAllOccurrences == true {
                            print("🗑️ Deleting recurring event and all occurrences: \(eventToDelete.title)")
                            taskManager.deleteRecurringTask(eventToDelete)
                        } else {
                            print("🗑️ Deleting event: \(eventToDelete.title)")
                            taskManager.deleteTask(eventToDelete)
                        }

                        // Speak confirmation
                        let confirmationText = "\(eventToDelete.title) has been deleted."
                        speakResponse(confirmationText)

                        // Add confirmation message to conversation
                        let confirmMessage = ConversationMessage(
                            isUser: false,
                            text: confirmationText,
                            intent: .calendar
                        )
                        conversationHistory.append(confirmMessage)
                    } else {
                        print("❌ Event not found: \(deletionData.itemTitle)")
                        speakResponse("I couldn't find that event to delete.")
                    }
                } else if deletionData.itemType == "note" {
                    // Find and delete the note
                    if let noteToDelete = notesManager.notes.first(where: {
                        $0.title.localizedCaseInsensitiveContains(deletionData.itemTitle)
                    }) {
                        print("🗑️ Deleting note: \(noteToDelete.title)")
                        notesManager.deleteNote(noteToDelete)

                        // Speak confirmation
                        let confirmationText = "\(noteToDelete.title) has been deleted."
                        speakResponse(confirmationText)

                        // Add confirmation message to conversation
                        let confirmMessage = ConversationMessage(
                            isUser: false,
                            text: confirmationText,
                            intent: .notes
                        )
                        conversationHistory.append(confirmMessage)
                    } else {
                        print("❌ Note not found: \(deletionData.itemTitle)")
                        speakResponse("I couldn't find that note to delete.")
                    }
                }

                // Clear pending data and hide dialog
                pendingDeletion = nil
                showDeletionConfirmation = false
            }
        }
    }

    func cancelDeletion() {
        Task {
            await MainActor.run {
                pendingDeletion = nil
                showDeletionConfirmation = false
            }

            // Don't speak on cancel to avoid audio session conflicts
            // Just silently dismiss
            print("ℹ️ Deletion cancelled by user")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceAssistantService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            print("🔊 System voice finished speaking (fallback)")

            // Deactivate playback audio session with balanced delay
            Task {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                    // Balanced delay - enough for cleanup but faster than before
                    try await Task.sleep(nanoseconds: 250_000_000) // 0.25 seconds
                } catch {
                    print("❌ Error deactivating audio session: \(error)")
                }

                await MainActor.run {
                    self.currentState = .idle
                    // Auto-restart listening with minimal delay for faster response
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        print("🎤 Auto-restarting listening for follow-up (from system voice)...")
                        if self.currentState == .idle {
                            self.startListeningWithSilenceDetection()
                        }
                    }
                }
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.currentState = .idle
        }
    }
}
