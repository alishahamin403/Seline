//
//  IntelligentSearchService.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import Foundation

/// Unified search service that handles both general queries and intelligent email searches
@MainActor
class IntelligentSearchService: ObservableObject {
        static let shared = IntelligentSearchService(openAIService: OpenAIService.shared)
    
    private let openAIService: OpenAIService
    private let localEmailService = LocalEmailService.shared
    private let aiSearchService: AISearchService
    
    @Published var isSearching = false
    @Published var lastSearchResult: IntelligentSearchResult?
    @Published var searchError: String?
    
    private init(openAIService: OpenAIService) {
        self.openAIService = openAIService
        self.aiSearchService = AISearchService(openAIService: openAIService)
    }
    
    // MARK: - Main Search Interface
    
    /// Main search method that intelligently routes queries
    func performSearch(query: String) async -> IntelligentSearchResult {
        guard !query.isEmpty else {
            return IntelligentSearchResult(query: query, type: .general, response: "Please enter a search query.")
        }
        
        print("🔍 IntelligentSearchService: Starting search for query: \"\(query)\"")
        
        isSearching = true
        searchError = nil
        
        defer {
            isSearching = false
            print("🔍 IntelligentSearchService: Search completed for query: \"\(query)\"")
        }
        
        // First, determine if this is an email search or general search
        let searchType = await classifySearchIntent(query)

        let result: IntelligentSearchResult
        switch searchType {
        case .emailSearch:
            result = await performIntelligentEmailSearch(query: query)
        case .general:
            result = await performGeneralSearch(query: query)
        }

        lastSearchResult = result
        return result
    }
    
    // MARK: - Search Intent Classification
    
    private func classifySearchIntent(_ query: String) async -> SearchIntent {
        let emailKeywords = [
            "email", "emails", "inbox", "message", "messages", "mail",
            "from:", "to:", "subject:", "sender", "recipient", "attachment",
            "unread", "important", "today's emails", "recent emails",
            "find email", "search email", "email from", "emails about",
            "show me emails", "any emails", "check emails"
        ]
        
        let lowercaseQuery = query.lowercased()
        
        // Direct keyword detection
        for keyword in emailKeywords {
            if lowercaseQuery.contains(keyword) {
                return .emailSearch
            }
        }
        
        // Pattern detection for implicit email searches
        let emailPatterns = [
            ".*from.*",
            ".*sent.*today.*",
            ".*received.*",
            ".*any.*about.*",
            "show.*",
            "find.*"
        ]
        
        for pattern in emailPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: lowercaseQuery, range: NSRange(lowercaseQuery.startIndex..., in: lowercaseQuery)) != nil {
                // Use AI to double-check if this is about emails
                let isEmailQuery = await checkIfEmailQuery(query)
                if isEmailQuery {
                    return .emailSearch
                }
            }
        }
        
        return .general
    }
    
    private func checkIfEmailQuery(_ query: String) async -> Bool {
        let prompt = """
        Analyze this search query and determine if the user is asking about emails or email-related content:
        
        Query: "\(query)"
        
        Respond with only "YES" if this is about emails, messages, inbox, or email-related searches.
        Respond with only "NO" if this is a general question or search not related to emails.
        
        Examples:
        - "Show me emails from John" -> YES
        - "Any messages about the meeting?" -> YES
        - "What's the weather today?" -> NO
        - "Find anything about project updates" -> NO (unless specifically mentions emails)
        """
        
        do {
            let response = try await openAIService.performAISearch(prompt)
            return response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().contains("YES")
        } catch {
            // Fallback to keyword detection if AI fails
            return false
        }
    }
    
    // MARK: - General Search
    
    private func performGeneralSearch(query: String) async -> IntelligentSearchResult {
        print("🧠 IntelligentSearchService: Performing general search for: \"\(query)\"")
        
        // Use AISearchService for consistent search behavior
        let aiResult = await aiSearchService.performAISearch(query: query)
        
        return IntelligentSearchResult(
            query: aiResult.query,
            type: .general,
            response: aiResult.response,
            emails: aiResult.emails,
            metadata: aiResult.metadata
        )
    }
    
    // MARK: - Intelligent Email Search
    
    private func performIntelligentEmailSearch(query: String) async -> IntelligentSearchResult {
        print("📧 IntelligentSearchService: Performing email search for: \"\(query)\"")
        
        // Use AISearchService for consistent email search behavior
        let aiResult = await aiSearchService.performAISearch(query: query)
        
        return IntelligentSearchResult(
            query: aiResult.query,
            type: .emailSearch,
            response: aiResult.response,
            emails: aiResult.emails,
            metadata: aiResult.metadata
        )
    }
    
    // MARK: - Email Data Preparation
    
    
    
    private func prepareEmailDataForAI(_ emails: [Email]) -> String {
        let emailSummaries = emails.enumerated().map { index, email in
            let truncatedBody = String(email.body.prefix(300))
            let attachmentInfo = email.attachments.isEmpty ? "" : " [Has \(email.attachments.count) attachment(s)]"
            
            return """
            Email \(index + 1):
            From: \(email.sender.name ?? email.sender.email)
            To: me
            Subject: \(email.subject)
            Date: \(formatDate(email.date))
            Important: \(email.isImportant ? "Yes" : "No")
            Read: \(email.isRead ? "Yes" : "No")
            Content: \(truncatedBody)\(truncatedBody.count == 300 ? "..." : "")\(attachmentInfo)
            ---
            """
        }
        
        return emailSummaries.joined(separator: "\n")
    }
    
    private func createEmailSearchPrompt(query: String, emailData: String) -> String {
        return """
        You are an intelligent email search assistant. The user wants to search through their email inbox.
        
        USER QUERY: "\(query)"
        
        EMAIL DATA FROM INBOX:
        \(emailData)
        
        Please analyze the emails and provide a helpful response to the user's query. Your response should:
        1. Directly answer what the user is looking for
        2. Reference specific emails that match their query (use "Email X" format)
        3. Provide relevant details like sender, subject, dates
        4. Summarize key information from matching emails
        5. If no emails match, explain why and suggest alternatives
        
        Focus on being helpful and specific. Reference email numbers (Email 1, Email 2, etc.) when discussing specific messages.
        """
    }
    
    // MARK: - Email Extraction
    
    private func extractRelevantEmails(from emails: [Email], aiResponse: String, originalQuery: String) async -> [Email] {
        // Extract email references from AI response (Email 1, Email 2, etc.)
        let emailReferences = extractEmailReferences(from: aiResponse)
        
        var relevantEmails: [Email] = []
        
        // Add emails referenced by AI
        for reference in emailReferences {
            if reference > 0 && reference <= emails.count {
                relevantEmails.append(emails[reference - 1])
            }
        }
        
        // If no specific references, perform basic keyword matching as fallback
        if relevantEmails.isEmpty {
            relevantEmails = performBasicEmailMatching(emails: emails, query: originalQuery)
        }
        
        return Array(relevantEmails.prefix(10)) // Limit results
    }
    
    private func extractEmailReferences(from aiResponse: String) -> [Int] {
        let pattern = #"Email (\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        let matches = regex.matches(in: aiResponse, range: NSRange(aiResponse.startIndex..., in: aiResponse))
        
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: aiResponse) else { return nil }
            return Int(aiResponse[range])
        }
    }
    
    private func performBasicEmailMatching(emails: [Email], query: String) -> [Email] {
        let keywords = query.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && $0.count > 2 }
        
        guard !keywords.isEmpty else { return Array(emails.prefix(5)) }
        
        return emails.filter { email in
            let searchText = "\(email.subject) \(email.body) \(email.sender.name ?? email.sender.email)".lowercased()
            return keywords.contains { keyword in
                searchText.contains(keyword)
            }
        }
    }
    
    // MARK: - Follow-up Conversations
    
    func generateFollowUpResponse(query: String, context: String, conversationHistory: [ConversationEntry]) async throws -> String {
        let conversationContext = conversationHistory.map { entry in
            "\(entry.type == .user ? "User" : "Assistant"): \(entry.content)"
        }.joined(separator: "\n")
        
        let followUpPrompt = """
        Previous context: \(context)
        
        Conversation history:
        \(conversationContext)
        
        Follow-up question: \(query)
        
        Please provide a helpful response that builds on the previous conversation.
        """
        
        return try await openAIService.performAISearch(followUpPrompt)
    }

    
    
    // MARK: - Utilities
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Data Models

struct IntelligentSearchResult {
    let query: String
    let type: SearchIntent
    let response: String
    let emails: [Email]
    let metadata: [String: String]
    
    init(query: String, type: SearchIntent, response: String, emails: [Email] = [], metadata: [String: String] = [:]) {
        self.query = query
        self.type = type
        self.response = response
        self.emails = emails
        self.metadata = metadata
    }
}

enum SearchIntent {
    case general
    case emailSearch
    
    var displayName: String {
        switch self {
        case .general:
            return "General Search"
        case .emailSearch:
            return "Email Search"
        }
    }
    
    var icon: String {
        switch self {
        case .general:
            return "brain.head.profile"
        case .emailSearch:
            return "envelope.magnifyingglass"
        }
    }
}

// MARK: - Conversation History

struct ConversationEntry: Identifiable, Codable {
    let id: UUID
    let type: ConversationEntryType
    let content: String
    let timestamp: Date
    
    init(type: ConversationEntryType, content: String) {
        self.id = UUID()
        self.type = type
        self.content = content
        self.timestamp = Date()
    }
}

enum ConversationEntryType: String, Codable {
    case user = "user"
    case assistant = "assistant"
    case emailSummary = "email_summary"
}