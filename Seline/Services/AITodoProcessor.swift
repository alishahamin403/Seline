//
//  AITodoProcessor.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import Foundation

@MainActor
class AITodoProcessor: ObservableObject {
    static let shared = AITodoProcessor()
    
    @Published var isProcessing = false
    @Published var errorMessage: String?
    
    private let openAIService = OpenAIService.shared
    
    private init() {}
    
    // MARK: - Main Processing Function
    
    func processSpeechToTodo(_ speechText: String) async throws -> ProcessedTodoData {
        isProcessing = true
        errorMessage = nil
        
        defer {
            isProcessing = false
        }
        
        do {
            let processedData = try await analyzeSpeechWithAI(speechText)
            return processedData
        } catch {
            errorMessage = "Failed to process speech: \(error.localizedDescription)"
            throw error
        }
    }
    
    // MARK: - AI Analysis
    
    private func analyzeSpeechWithAI(_ speechText: String) async throws -> ProcessedTodoData {
        let prompt = createAnalysisPrompt(for: speechText)
        
        // Use OpenAI to analyze the speech
        let response = try await openAIService.performAISearch(prompt)
        
        // Parse the structured response
        return try parseAIResponse(response, originalText: speechText)
    }
    
    private func createAnalysisPrompt(for speechText: String) -> String {
        let currentDate = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        
        return """
        Analyze this speech input and extract todo information. Current date and time: \(dateFormatter.string(from: currentDate))
        
        Speech: "\(speechText)"
        
        Please respond in this exact JSON format:
        {
            "title": "Brief, actionable title (max 50 characters)",
            "description": "Detailed description of what needs to be done",
            "dueDate": "YYYY-MM-DD HH:mm:ss", 
            "reminderDate": "YYYY-MM-DD HH:mm:ss or null",
            "priority": "low/medium/high",
            "confidence": 0.0-1.0
        }
        
        Rules:
        1. Extract the main task/action from the speech
        2. Create a concise, actionable title
        3. Provide a helpful description
        4. Parse any time references (today, tomorrow, in 2 hours, next week, etc.)
        5. If no specific time mentioned, set due date to end of today
        6. Set reminder date if user mentions "remind me" or timing
        7. Assess priority based on urgency words (urgent=high, important=medium, default=low)
        8. Return confidence score for the parsing accuracy
        
        Examples:
        - "Remind me to call mom in 2 hours" → due: 2 hours from now, reminder: 2 hours from now
        - "I need to buy groceries tomorrow" → due: tomorrow 6 PM, reminder: tomorrow 4 PM
        - "Meeting with John next Tuesday at 3" → due: next Tuesday 3 PM, reminder: 30 min before
        """
    }
    
    private func parseAIResponse(_ response: String, originalText: String) throws -> ProcessedTodoData {
        print("🤖 AITodoProcessor: Raw AI response: \(response)")
        
        // Try to extract JSON
        let jsonText = extractJSON(from: response)
        guard let data = jsonText.data(using: .utf8) else {
            return createFallbackTodo(from: originalText)
        }
        
        do {
            let ai = try JSONDecoder().decode(AITodoResponse.self, from: data)
            // Build dates
            let now = Date()
            let due = parseDate(ai.dueDate) ?? now
            let reminder = ai.reminderDate.flatMap { parseDate($0) }
            let priority: TodoItem.Priority = {
                switch ai.priority.lowercased() {
                case "high": return .high
                case "medium": return .medium
                default: return .low
                }
            }()
            return ProcessedTodoData(
                title: ai.title.isEmpty ? originalText : ai.title,
                description: ai.description,
                dueDate: due,
                reminderDate: reminder,
                priority: priority,
                confidence: ai.confidence,
                originalText: originalText
            )
        } catch {
            print("❌ AITodoProcessor: JSON parse failed, using fallback. Error: \(error)")
            return createFallbackTodo(from: originalText)
        }
    }
    
    private func extractJSON(from text: String) -> String {
        // Look for JSON content between braces
        if let startRange = text.range(of: "{"),
           let endRange = text.range(of: "}", options: .backwards) {
            // Ensure the end range comes after the start range
            if startRange.lowerBound < endRange.upperBound {
                return String(text[startRange.lowerBound...endRange.upperBound])
            }
        }
        
        // Fallback: try to find any JSON-like structure
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return trimmed
        }
        
        // Last fallback: return original text
        return text
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatters = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        
        return nil
    }
    
    private func createFallbackTodo(from speechText: String) -> ProcessedTodoData {
        print("🔧 AITodoProcessor: Creating fallback todo from speech")
        
        // Create a reasonable title from the speech
        var title = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common speech prefixes
        let prefixesToRemove = ["can you remind me to", "remind me to", "remind me", "i need to", "please remind me to", "create a task to", "add a task to"]
        for prefix in prefixesToRemove {
            if title.lowercased().hasPrefix(prefix) {
                title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        // Limit title length and capitalize first letter
        if title.count > 50 {
            title = String(title.prefix(50)) + "..."
        }
        
        if !title.isEmpty {
            title = title.prefix(1).capitalized + title.dropFirst()
        }
        
        if title.isEmpty {
            title = "Voice Todo"
        }
        
        // Parse simple natural language timing
        let calendar = Calendar.current
        let now = Date()
        var due = now
        var defaultHour = 18 // 6 PM default for tasks
        var reminderDate: Date?
        let lower = speechText.lowercased()
        
        if lower.contains("tomorrow") {
            due = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        } else if lower.contains("today") {
            due = now
        } else if lower.contains("next week") {
            due = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        }
        
        // Time hints
        if lower.contains("morning") { defaultHour = 9 }
        else if lower.contains("noon") { defaultHour = 12 }
        else if lower.contains("afternoon") { defaultHour = 15 }
        else if lower.contains("evening") { defaultHour = 19 }
        
        // Specific "at HH[:MM]" pattern
        if let atRange = lower.range(of: " at ") {
            let after = lower[atRange.upperBound...]
            if let token = after.split(separator: " ").first {
                let parts = token.split(separator: ":")
                if let h = Int(parts.first ?? ""), h >= 0 && h <= 23 {
                    defaultHour = h
                    let minute = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                    var comps = calendar.dateComponents([.year, .month, .day], from: due)
                    comps.hour = defaultHour; comps.minute = minute
                    due = calendar.date(from: comps) ?? due
                }
            }
        } else {
            // Set default hour on computed date
            var comps = calendar.dateComponents([.year, .month, .day], from: due)
            comps.hour = defaultHour; comps.minute = 0
            due = calendar.date(from: comps) ?? due
        }
        
        // Set a reminder 1 hour before if phrase includes "remind"
        if lower.contains("remind") {
            reminderDate = calendar.date(byAdding: .hour, value: -1, to: due)
        }
        
        print("✅ AITodoProcessor: Fallback todo created - Title: '\(title)'")
        
        return ProcessedTodoData(
            title: title,
            description: speechText,
            dueDate: due,
            reminderDate: reminderDate,
            priority: .medium,
            confidence: 0.8,
            originalText: speechText
        )
    }
}

// MARK: - Data Models

struct ProcessedTodoData {
    let title: String
    let description: String
    let dueDate: Date
    let reminderDate: Date?
    let priority: TodoItem.Priority
    let confidence: Double
    let originalText: String
    
    func toTodoItem() -> TodoItem {
        print("🔍 ProcessedTodoData: Creating TodoItem...")
        print("🔍 ProcessedTodoData: Title: '\(title)'")
        print("🔍 ProcessedTodoData: Description: '\(description)'")
        print("🔍 ProcessedTodoData: DueDate: \(dueDate)")
        print("🔍 ProcessedTodoData: ReminderDate: \(reminderDate?.description ?? "nil")")
        print("🔍 ProcessedTodoData: Priority: \(priority)")
        print("🔍 ProcessedTodoData: OriginalText: '\(originalText)'")
        
        let todoItem = TodoItem(
            title: title,
            description: description,
            dueDate: dueDate,
            originalSpeechText: originalText,
            reminderDate: reminderDate,
            priority: priority
        )
        print("✅ ProcessedTodoData: TodoItem created successfully")
        return todoItem
    }
}

private struct AITodoResponse: Codable {
    let title: String
    let description: String
    let dueDate: String
    let reminderDate: String?
    let priority: String
    let confidence: Double
}

// MARK: - Error Types

enum AIProcessingError: LocalizedError {
    case invalidResponse
    case networkError
    case parsingError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid AI response format"
        case .networkError:
            return "Network error occurred"
        case .parsingError:
            return "Failed to parse response"
        }
    }
}