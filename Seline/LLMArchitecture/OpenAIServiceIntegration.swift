import Foundation

/// ============================================================
/// REFERENCE FILE - DO NOT COMPILE
/// ============================================================
///
/// This file shows the code changes needed to integrate
/// the structured validation system into your existing
/// OpenAIService.swift and SearchService.swift files.
///
/// Copy the pseudocode below and adapt to your actual
/// property names and access levels.
///
/// See STRUCTURED_RESPONSE_INTEGRATION.md for full details
/// ============================================================

// ============================================================
// CHANGE 1: In OpenAIService.swift - Add this method
// ============================================================

/*
@MainActor
func answerQuestionWithStructuredValidation(
    query: String,
    taskManager: TaskManager,
    notesManager: NotesManager,
    emailService: EmailService,
    weatherService: WeatherService? = nil,
    locationsManager: LocationsManager? = nil,
    navigationService: NavigationService? = nil,
    conversationHistory: [ConversationMessage] = [],
    onValidationComplete: @escaping (ValidationResult) -> Void
) async throws {
    print("🎬 answerQuestionWithStructuredValidation started")

    // Rate limiting (adjust to match your private method)
    await self.enforceRateLimit()

    guard let url = URL(string: self.baseURL) else {
        throw SummaryError.invalidURL
    }

    // STEP 1: Extract intent from user query
    let intentContext = IntentExtractor.shared.extractIntent(from: query)
    print("🎯 Intent: \(intentContext.intent.rawValue)")

    // STEP 2: Get data from all managers
    // NOTE: Adjust these to match your actual API:
    // - TaskManager.tasks is [WeekDay: [TaskItem]], so flatten it
    // - EmailService may not have .emails property, adjust as needed
    // - WeatherService property names may differ

    let allTasks = taskManager.tasks.values.flatMap { $0 }  // Convert dict to array
    let emailsList: [Email] = []  // TODO: Get from emailService with your API
    let currentWeather: WeatherData? = nil  // TODO: Get from weatherService with your API

    // STEP 3: Filter data using smart filtering
    let filteredContext = DataFilter.shared.filterDataForQuery(
        intent: intentContext,
        notes: notesManager.notes,
        locations: locationsManager?.savedPlaces ?? [],
        tasks: allTasks,
        emails: emailsList,
        weather: currentWeather
    )

    // STEP 4: Build structured context
    let structuredContext = ContextBuilder.shared.buildStructuredContext(
        from: filteredContext,
        conversationHistory: Array(conversationHistory.dropLast(1))
    )
    let contextJSON = ContextBuilder.shared.serializeToJSON(structuredContext)

    // STEP 5: Use structured system prompt
    let systemPrompt = StructuredPrompt.buildSystemPrompt()

    // STEP 6: Build messages array
    var messages: [[String: String]] = [
        ["role": "system", "content": systemPrompt]
    ]

    // Add previous conversation messages
    for message in conversationHistory {
        messages.append([
            "role": message.isUser ? "user" : "assistant",
            "content": message.text
        ])
    }

    // Add context and current query
    messages.append([
        "role": "user",
        "content": "Context:\n\(contextJSON)\n\nQuery: \(query)"
    ])

    // STEP 7: Make request to OpenAI (use the existing makeOpenAIRequest method)
    let requestBody: [String: Any] = [
        "model": "gpt-4o-mini",
        "messages": messages,
        "temperature": 0.3,  // Lower for consistent JSON
        "max_tokens": 800
    ]

    let response = try await self.makeOpenAIRequest(url: url, requestBody: requestBody)

    // STEP 8: Parse JSON response
    let parsedResponse = try self.parseJSONResponse(response)
    print("✅ Parsed response: confidence=\(parsedResponse.confidence)")

    // STEP 9: Validate response against actual data
    let validationResult = ResponseValidator.shared.validateResponse(
        parsedResponse,
        against: filteredContext
    )
    print("🔍 Validation result: \(validationResult)")

    // STEP 10: Return validation result to caller
    DispatchQueue.main.async {
        onValidationComplete(validationResult)
    }
}

// Add these helper methods to OpenAIService:

private func parseJSONResponse(_ jsonString: String) throws -> LLMResponse {
    // Extract JSON from potentially messy response
    let cleanedJSON = self.extractJSONFromResponse(jsonString)

    guard let data = cleanedJSON.data(using: .utf8) else {
        throw SummaryError.decodingError
    }

    let decoder = JSONDecoder()
    return try decoder.decode(LLMResponse.self, from: data)
}

private func extractJSONFromResponse(_ text: String) -> String {
    // Find first { and last } to extract JSON
    guard let firstBrace = text.firstIndex(of: "{"),
          let lastBrace = text.lastIndex(of: "}") else {
        return text
    }
    return String(text[firstBrace...lastBrace])
}
*/

// ============================================================
// CHANGE 2: In SearchService.swift - Update this method
// ============================================================

/*
// In addConversationMessage, replace the OpenAI call:

// OLD CODE:
// let response = try await DeepSeekService.shared.answerQuestion(...)
// let assistantMsg = ConversationMessage(isUser: false, text: response, ...)
// conversationHistory.append(assistantMsg)

// NEW CODE:
try await DeepSeekService.shared.answerQuestionWithStructuredValidation(
    query: trimmed,
    taskManager: TaskManager.shared,
    notesManager: NotesManager.shared,
    emailService: EmailService.shared,
    weatherService: WeatherService.shared,
    locationsManager: LocationsManager.shared,
    navigationService: NavigationService.shared,
    conversationHistory: conversationHistory,
    onValidationComplete: { validationResult in
        // Handle the validation result
        self.handleValidationResult(validationResult)
    }
)

// Add this handler method to SearchService:

@MainActor
private func handleValidationResult(_ result: ValidationResult) {
    let messageText: String
    var shouldShowResponse = true

    switch result {
    case .valid(let response):
        messageText = response.response

    case .lowConfidence(let response):
        let question = response.clarifyingQuestions.first ?? "Could you be more specific?"
        messageText = "I'm not entirely certain. \(question)\n\nBased on what I found:\n\(response.response)"

    case .hallucination(let reason):
        messageText = "I apologize, but I made an error: \(reason). Could you rephrase your question?"
        shouldShowResponse = false

    case .partiallyValid(let response, let issues):
        messageText = "⚠️ Note: \(issues.first ?? "Some data may be incomplete")\n\n\(response.response)"

    case .needsClarification(let questions):
        messageText = "I need more information to help you: \(questions.joined(separator: " Or "))"
        shouldShowResponse = false
    }

    // Only show response if it passed validation
    if shouldShowResponse {
        let assistantMsg = ConversationMessage(
            id: UUID(),
            isUser: false,
            text: messageText,
            timestamp: Date(),
            intent: .general
        )

        conversationHistory.append(assistantMsg)
        self.saveConversationLocally()
    }

    isLoadingQuestionResponse = false
}
*/

// ============================================================
// IMPORTANT NOTES
// ============================================================

/*
1. PROPERTY NAMES TO ADJUST:
   - TaskManager.tasks is [WeekDay: [TaskItem]], not [TaskItem]
   - EmailService: Check if it has .emails property or if you need a different method
   - WeatherService: Check actual property names for current weather data
   - OpenAIService.baseURL and enforceRateLimit() are private - use self.

2. DATA GATHERING:
   Check these exact property names in your code:
   ```swift
   notesManager.notes              // [Note]
   locationsManager.savedPlaces    // [SavedPlace]
   taskManager.tasks               // [WeekDay: [TaskItem]] - flatten with .values.flatMap
   emailService.???                // Check the actual API
   weatherService.???              // Check the actual API
   ```

3. TESTING THE INTEGRATION:
   - Add debug prints to track the flow
   - Test with queries that should be valid
   - Test with queries that should need clarification
   - Test with queries that should fail validation

4. CONFIDENCE THRESHOLDS:
   You can adjust in ResponseValidator.swift:
   ```swift
   if llmResponse.confidence < 0.75 {  // Change 0.75 to 0.65 or 0.85
       return .lowConfidence(llmResponse)
   }
   ```

5. ERROR HANDLING:
   Ensure you have proper try/catch around the async call
   Handle parseJSONResponse errors gracefully

6. STREAMING vs NON-STREAMING:
   The code above uses non-streaming for cleaner JSON parsing
   If you want streaming, you'll need to buffer JSON chunks first
*/

// ============================================================
// DO NOT EDIT BELOW - FILE REFERENCE ONLY
// ============================================================
