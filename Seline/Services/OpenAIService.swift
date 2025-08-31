//
//  OpenAIService.swift
//  Seline
//
//  Created by Claude on 2025-08-24.
//

import Foundation
import Combine
import SwiftUI

@MainActor
class OpenAIService: ObservableObject {
    static let shared = OpenAIService()
    
    // MARK: - Configuration
    
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let secureStorage = SecureStorage.shared
    private let networkManager = NetworkManager.shared
    
    /// Dynamic configuration that updates based on current API key status
    private var configuration: OpenAIConfiguration {
        return ConfigurationManager.shared.getOpenAIConfiguration()
    }
    
    // MARK: - Published Properties
    
    @Published var isConfigured: Bool = false
    @Published var lastError: OpenAIError?
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        self.isConfigured = secureStorage.hasOpenAIKey()
        
        setupConfigurationObserver()
    }
    
    // MARK: - Query Classification
    
    func classifyQuery(_ query: String) -> SearchType {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Email search indicators
        let emailKeywords = [
            "from:", "to:", "subject:", "has:attachment", "in:", "label:",
            "unread", "important", "attachment", "today", "yesterday",
            "this week", "last week", "sender", "recipient"
        ]
        
        // Check if query contains email-specific operators or keywords
        if emailKeywords.contains(where: { trimmedQuery.contains($0) }) {
            return .email
        }
        
        // Check for email-like patterns (looking for specific email addresses)
        if trimmedQuery.contains("@") && trimmedQuery.contains(".") {
            return .email
        }
        
        // General search indicators
        let generalKeywords = [
            "what", "how", "when", "where", "why", "who", "can you",
            "please", "explain", "define", "calculate", "weather",
            "news", "latest", "current", "recent", "help me"
        ]
        
        if generalKeywords.contains(where: { trimmedQuery.hasPrefix($0) || trimmedQuery.contains(" " + $0) }) {
            return .general
        }
        
        // Default to email search for short queries or ambiguous cases
        if trimmedQuery.count < 10 {
            return .general
        }
        
        // For longer queries that don't match email patterns, assume general search
        return .general
    }

    // MARK: - Natural Language Intent Detection
    /// Classify a spoken query into intents: todo, calendar, or ai (general search)
    func detectVoiceIntent(_ text: String) -> VoiceIntent {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Enhanced calendar detection patterns
        let calendarPatterns = [
            // Direct calendar actions
            "schedule", "create event", "add event", "book", "plan", "meeting", "calendar", "appointment", "call",
            // Time-based indicators
            "remind me at", "at ", "on ", "tomorrow", "today at", "next week", "next month", "this week", "this afternoon", "tonight", "morning",
            // Date/time patterns
            "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "pm", "am", "o'clock", "noon", "midnight",
            // Meeting-specific terms
            "zoom", "teams", "conference", "webinar", "presentation", "interview", "lunch", "dinner", "coffee"
        ]
        
        // Enhanced todo detection patterns  
        let todoPatterns = [
            // Direct todo actions
            "todo", "to-do", "task", "note", "remember", "remind me to", "don't forget", "make sure", "need to",
            // Action verbs commonly used for todos
            "buy", "get", "pick up", "call", "email", "send", "finish", "complete", "start", "begin", "work on",
            "read", "write", "review", "check", "follow up", "prepare", "organize", "clean", "fix", "update",
            // Todo-specific phrases
            "add to my list", "put on my todo", "create a task", "add a reminder", "jot down", "make a note"
        ]
        
        // Search/AI patterns (things that are questions or searches)
        let searchPatterns = [
            // Question words
            "what", "when", "where", "who", "why", "how", "which", "can you", "do you know", "tell me", "find",
            // Search terms
            "search for", "look up", "show me", "explain", "define", "calculate", "convert", "translate",
            // Email-related searches
            "email", "from", "subject", "sender", "message", "inbox", "unread", "important"
        ]
        
        // Score each intent category
        let calendarScore = calendarPatterns.filter { q.contains($0) }.count
        let todoScore = todoPatterns.filter { q.contains($0) }.count  
        let searchScore = searchPatterns.filter { q.contains($0) }.count
        
        // Determine intent based on highest score, with tie-breaking logic
        if calendarScore > todoScore && calendarScore > searchScore {
            return .calendar
        } else if todoScore > calendarScore && todoScore > searchScore {
            return .todo
        } else if searchScore > 0 {
            return .ai
        } else {
            // Fallback logic: check sentence structure
            if q.contains("?") || q.starts(with: "what") || q.starts(with: "how") || q.starts(with: "when") || q.starts(with: "where") {
                return .ai
            } else if q.contains("remind me") || q.contains("don't forget") || q.contains("need to") {
                return .todo  
            } else if q.contains(" at ") || q.contains(" on ") || q.contains("tomorrow") || q.contains("today") {
                return .calendar
            }
            
            // Default to AI search if unclear
            return .ai
        }
    }
    
    // MARK: - Configuration Management
    
    private func setupConfigurationObserver() {
        // Check immediately on setup
        checkConfiguration()
        
        // Monitor less aggressively to avoid state races; rely on explicit refreshes from Settings
        Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkConfiguration()
            }
            .store(in: &cancellables)
    }
    
    private func checkConfiguration() {
        let hasKey = secureStorage.hasOpenAIKey()
        isConfigured = hasKey
        print("🤖 OpenAI configuration updated: isConfigured = \(isConfigured)")
    }
    
    /// Force immediate configuration refresh (used by development setup)
    func refreshConfiguration() {
        checkConfiguration()
    }
    
    /// Configure OpenAI API key (typically called from settings)
    /// Stores the key immediately so it's persisted across launches, then validates in the background.
    func configureAPIKey(_ key: String) async throws {
        // Validate basic format first
        guard secureStorage.validateOpenAIKey(key) else {
            throw OpenAIError.invalidAPIKey
        }
        
        // Store immediately so configuration persists even if validation network call fails now
        guard secureStorage.storeOpenAIKey(key) else {
            throw OpenAIError.keychainError
        }
        
        // Mark configured so real API is used
        isConfigured = true
        
        // Kick off a non-blocking validation. If it fails, surface error but keep the key stored.
        Task { [weak self] in
            do {
                try await self?.testAPIKey(key)
            } catch {
                // Keep the stored key; just record the error for UI messaging if needed
                if let openAIError = error as? OpenAIError {
                    self?.lastError = openAIError
                } else {
                    self?.lastError = OpenAIError.networkError(error)
                }
            }
        }
    }
    
    /// Test API key validity
    private func testAPIKey(_ key: String) async throws {
        // Make a minimal test request to validate the key
        let testQuery = "Hello"
        let request = try createAPIRequest(query: testQuery, apiKey: key)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }
            
            guard httpResponse.statusCode != 401 else {
                throw OpenAIError.invalidAPIKey
            }
            
        } catch {
            if let openAIError = error as? OpenAIError {
                throw openAIError
            }
            throw OpenAIError.networkError(error)
        }
    }
    
    // MARK: - AI Search
    
    func performAISearch(_ query: String) async throws -> String {
        // Check if we should use real API or mock responses
        if configuration.useRealAPI && (isConfigured || secureStorage.hasOpenAIKey()) {
            print("🤖 OpenAI: Using real API for query: \"\(query)\"")
            print("🔑 OpenAI: API key configured: \(secureStorage.hasOpenAIKey())")
            return try await performRealAPISearch(query)
        } else {
            print("🤖 OpenAI: Using mock response for query: \"\(query)\" (useRealAPI: \(configuration.useRealAPI), isConfigured: \(isConfigured))")
            print("🔑 OpenAI: API key configured: \(secureStorage.hasOpenAIKey())")
            return generateMockResponse(for: query)
        }
    }
    
    /// Perform real OpenAI API search with retry logic
    private func performRealAPISearch(_ query: String) async throws -> String {
        guard let apiKey = secureStorage.getOpenAIKey() else {
            print("❌ OpenAI: No API key found in secure storage")
            throw OpenAIError.noAPIKey
        }
        
        print("🔑 OpenAI: API key found, length: \(apiKey.count)")
        
        return try await withRetry(maxRetries: configuration.maxRetries) {
            try await self.performSingleAPIRequest(query: query, apiKey: apiKey)
        }
    }

    // MARK: - Streaming Chat (text deltas)
    /// Stream chat completion deltas and invoke the callback as text arrives.
    /// This enables near-real-time TTS by speaking sentences as they complete.
    func streamChatResponse(
        systemPrompt: String? = nil,
        userPrompt: String,
        temperature: Double = 0.7,
        onDelta: @escaping (String) -> Void
    ) async throws {
        guard let apiKey = secureStorage.getOpenAIKey() else {
            throw OpenAIError.noAPIKey
        }
        guard let url = URL(string: baseURL) else { throw OpenAIError.invalidURL }
        
        // Build streaming request body
        struct StreamMessage: Codable { let role: String; let content: String }
        struct StreamBody: Codable {
            let model: String
            let messages: [StreamMessage]
            let temperature: Double
            let stream: Bool
        }
        var messages: [StreamMessage] = []
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            messages.append(StreamMessage(role: "system", content: systemPrompt))
        }
        messages.append(StreamMessage(role: "user", content: userPrompt))
        let body = StreamBody(model: "gpt-4o-mini", messages: messages, temperature: temperature, stream: true)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = configuration.timeoutInterval * 2
        request.httpBody = try JSONEncoder().encode(body)
        
        let session = networkManager.createURLSession()
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OpenAIError.invalidResponse
        }
        
        // Parse SSE stream lines: data: { json }\n\n
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }
                guard let data = payload.data(using: .utf8) else { continue }
                if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) {
                    if let delta = chunk.choices.first?.delta.content?.joined() {
                        onDelta(delta)
                    } else if let deltaStr = chunk.choices.first?.delta.contentString {
                        onDelta(deltaStr)
                    }
                }
            }
        }
    }

    // MARK: - Stream Models
    private struct StreamChunk: Codable {
        struct Choice: Codable {
            struct Delta: Codable {
                // OpenAI may send content as array of strings or a single string depending on model
                let content: [String]?
                let contentString: String?
                enum CodingKeys: String, CodingKey { case content }
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    if let arr = try? c.decode([String].self, forKey: .content) {
                        content = arr; contentString = nil
                    } else if let str = try? c.decode(String.self, forKey: .content) {
                        content = nil; contentString = str
                    } else {
                        content = nil; contentString = nil
                    }
                }
            }
            let delta: Delta
        }
        let choices: [Choice]
    }
    
    /// Single API request with proper error handling
    private func performSingleAPIRequest(query: String, apiKey: String) async throws -> String {
        let request = try createAPIRequest(query: query, apiKey: apiKey)
        
        print("🌐 OpenAI: Making HTTP request to: \(request.url?.absoluteString ?? "unknown URL")")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ OpenAI: Invalid HTTP response type")
                throw OpenAIError.invalidResponse
            }
            
            print("🌐 OpenAI: HTTP Response Status: \(httpResponse.statusCode)")
            
            try validateHTTPResponse(httpResponse)
            
            let openAIResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            
            guard let firstChoice = openAIResponse.choices.first else {
                print("❌ OpenAI: No choices in API response")
                throw OpenAIError.noResponse
            }
            
            print("✅ OpenAI: Successfully received response from API")
            return firstChoice.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch let error as OpenAIError {
            lastError = error
            throw error
        } catch let error as DecodingError {
            let openAIError = OpenAIError.decodingError(error)
            lastError = openAIError
            throw openAIError
        } catch {
            let openAIError = OpenAIError.networkError(error)
            lastError = openAIError
            throw openAIError
        }
    }
    
    /// Create properly configured API request
    private func createAPIRequest(query: String, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: baseURL) else {
            throw OpenAIError.invalidURL
        }
        
        let requestBody = OpenAIRequest(
            model: "gpt-4o",
            messages: [
                OpenAIMessage(
                    role: "system",
                    content: """
                    You are a helpful assistant that provides concise, accurate answers to user questions. 
                    Keep responses to 2 sentences maximum. Be direct and informative.
                    Do not mention that you cannot browse the internet - just provide the best answer you can with your knowledge.
                    If the question is about current events or requires real-time data, provide general information and note that details may have changed.
                    """
                ),
                OpenAIMessage(
                    role: "user",
                    content: query
                )
            ],
            max_tokens: configuration.maxTokens,
            temperature: configuration.temperature
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Seline/\(ConfigurationManager.shared.getAppVersion())", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = configuration.timeoutInterval
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            throw OpenAIError.encodingError
        }
        
        return request
    }
    
    /// Validate HTTP response and throw appropriate errors
    private func validateHTTPResponse(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return // Success
        case 401:
            throw OpenAIError.invalidAPIKey
        case 429:
            throw OpenAIError.rateLimitExceeded
        case 500...599:
            throw OpenAIError.serverError(response.statusCode)
        default:
            throw OpenAIError.httpError(response.statusCode)
        }
    }
    
    /// Retry logic with exponential backoff
    private func withRetry<T>(maxRetries: Int, operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch let error as OpenAIError {
                lastError = error
                
                // Don't retry on certain errors
                switch error {
                case .invalidAPIKey, .encodingError, .decodingError:
                    throw error
                default:
                    if attempt == maxRetries - 1 {
                        throw error
                    }
                }
                
                // Exponential backoff
                let delay = pow(2.0, Double(attempt)) * 0.5
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        throw lastError ?? OpenAIError.unknownError
    }
    
    // MARK: - Mock Response Generator
    
    private func generateMockResponse(for query: String) -> String {
        let lowercaseQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Distance/geography queries
        if (lowercaseQuery.contains("far") && lowercaseQuery.contains("canada") && lowercaseQuery.contains("pakistan")) ||
           (lowercaseQuery.contains("distance") && (lowercaseQuery.contains("canada") || lowercaseQuery.contains("pakistan"))) {
            return "The distance between Canada and Pakistan is approximately 11,000-12,000 kilometers (6,800-7,500 miles) depending on the specific cities. For example, the distance from Toronto to Karachi is about 11,500 km (7,150 miles)."
        }
        
        // Specific distance queries
        if lowercaseQuery.contains("distance") || (lowercaseQuery.contains("far") && lowercaseQuery.contains("from")) {
            return "I can help with distance calculations! Please specify the two locations you'd like to know the distance between, and I'll provide the approximate distance."
        }
        
        // Weather queries
        if lowercaseQuery.contains("weather") {
            let currentTemp = Int.random(in: 60...80)
            let conditions = ["sunny", "partly cloudy", "clear", "overcast"]
            let condition = conditions.randomElement() ?? "pleasant"
            return "Current weather is \(condition) with temperatures around \(currentTemp)°F. Please check a weather app for real-time local conditions."
        }
        
        // Time/date queries
        if lowercaseQuery.contains("time") || lowercaseQuery.contains("date") {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            formatter.timeStyle = .short
            return "Today is \(formatter.string(from: Date())). Have a productive day!"
        }
        
        // Math/calculation queries
        if lowercaseQuery.contains("calculate") || lowercaseQuery.contains("what is") && (lowercaseQuery.contains("+") || lowercaseQuery.contains("-") || lowercaseQuery.contains("*") || lowercaseQuery.contains("x") || lowercaseQuery.contains("/")) {
            return "I can help with basic calculations. For complex math, please use a dedicated calculator app for accurate results."
        }
        
        // Technology queries
        if lowercaseQuery.contains("apple") || lowercaseQuery.contains("iphone") || lowercaseQuery.contains("ios") {
            return "Apple continues to innovate with their latest iPhone and iOS updates, focusing on performance, privacy, and user experience across their ecosystem."
        }
        
        // General knowledge - be more specific and helpful
        if lowercaseQuery.hasPrefix("what") || lowercaseQuery.hasPrefix("how") || lowercaseQuery.hasPrefix("why") || lowercaseQuery.hasPrefix("when") || lowercaseQuery.hasPrefix("where") {
            return "I'd be happy to help answer that question! For the most accurate and up-to-date information, I recommend consulting reliable sources or specific subject matter experts."
        }
        
        // Default helpful response
        return "I understand you're looking for information about that topic. For detailed and accurate answers, I recommend consulting authoritative sources or subject experts. Is there a specific aspect you'd like help with?"
    }
}

// MARK: - Data Models

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let max_tokens: Int
    let temperature: Double
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

// MARK: - Error Types

enum OpenAIError: LocalizedError {
    case noAPIKey
    case invalidURL
    case encodingError
    case invalidResponse
    case invalidAPIKey
    case rateLimitExceeded
    case httpError(Int)
    case serverError(Int)
    case noResponse
    case networkError(Error)
    case decodingError(DecodingError)
    case keychainError
    case unknownError
    case quotaExceeded
    case serviceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not configured. Please add your API key in Settings."
        case .invalidURL:
            return "Invalid API URL configuration."
        case .encodingError:
            return "Failed to encode request data."
        case .invalidResponse:
            return "Received invalid response from OpenAI API."
        case .invalidAPIKey:
            return "Invalid OpenAI API key. Please check your key in Settings."
        case .rateLimitExceeded:
            return "OpenAI API rate limit exceeded. Please try again in a few moments."
        case .httpError(let code):
            return "HTTP error \(code). Please try again later."
        case .serverError(let code):
            return "OpenAI server error \(code). The service may be temporarily unavailable."
        case .noResponse:
            return "No response received from OpenAI API."
        case .networkError(let error):
            return "Network connection error: \(error.localizedDescription)"
        case .decodingError:
            return "Failed to process API response. Please try again."
        case .keychainError:
            return "Failed to securely store API key. Please try again."
        case .unknownError:
            return "An unexpected error occurred. Please try again."
        case .quotaExceeded:
            return "Your OpenAI API quota has been exceeded. Please check your account."
        case .serviceUnavailable:
            return "OpenAI service is temporarily unavailable. Please try again later."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .noAPIKey, .invalidAPIKey:
            return "Go to Settings to configure your OpenAI API key."
        case .rateLimitExceeded:
            return "Wait a few minutes before trying again."
        case .networkError:
            return "Check your internet connection and try again."
        case .quotaExceeded:
            return "Visit your OpenAI account to check usage and billing."
        case .serverError, .serviceUnavailable:
            return "This is a temporary issue. Please try again in a few minutes."
        default:
            return "Please try again. If the problem persists, contact support."
        }
    }
    
    /// Whether this error should trigger a retry
    var isRetryable: Bool {
        switch self {
        case .rateLimitExceeded, .serverError, .networkError, .serviceUnavailable:
            return true
        case .noAPIKey, .invalidAPIKey, .encodingError, .decodingError, .quotaExceeded:
            return false
        default:
            return false
        }
    }
}

// MARK: - Search Type (moved from SearchResultsView)

enum SearchType: String, CaseIterable {
    case email = "email"
    case general = "general"
    
    var icon: String {
        switch self {
        case .email:
            return "envelope.fill"
        case .general:
            return "sparkles"
        }
    }
    
    var displayName: String {
        switch self {
        case .email:
            return "Email Search"
        case .general:
            return "AI Search"
        }
    }
    
    var color: Color {
        switch self {
        case .email:
            return .blue
        case .general:
            return DesignSystem.Colors.accent
        }
    }
}

enum VoiceIntent {
    case todo
    case calendar
    case ai
}