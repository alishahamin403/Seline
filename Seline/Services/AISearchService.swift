//
//  AISearchService.swift
//  Seline
//
//  Created by Assistant on 2025-08-29.
//

import Foundation

/// Service for AI-powered search functionality
@MainActor
class AISearchService: ObservableObject {
        static let shared = AISearchService(openAIService: OpenAIService.shared)
    
    private let openAIService: OpenAIService
    private let localEmailService = LocalEmailService.shared
    
    @Published var isSearching = false
    @Published var lastSearchResult: AISearchResult?
    @Published var searchError: String?
    
    init(openAIService: OpenAIService) {
        self.openAIService = openAIService
    }
    
    // MARK: - Main Search Interface
    
    /// Perform AI-powered search across emails and general queries
    func performAISearch(query: String) async -> AISearchResult {
        guard !query.isEmpty else {
            return AISearchResult(
                query: query,
                response: "Please enter a search query.",
                emails: [],
                searchType: .general
            )
        }
        
        print("🔍 AISearchService: Starting AI search for query: \"\(query)\"")
        
        isSearching = true
        searchError = nil
        
        defer {
            isSearching = false
            print("🔍 AISearchService: AI search completed for query: \"\(query)\"")
        }
        
        // Determine search type and perform appropriate search
        let searchType = await determineSearchType(query)
        
        switch searchType {
        case .emailSearch:
            return await performEmailSearch(query: query)
        case .general:
            return await performGeneralSearch(query: query)
        }
    }
    
    // MARK: - Search Type Determination
    
    private func determineSearchType(_ query: String) async -> AISearchType {
        let emailKeywords = ["email", "message", "inbox", "from", "to", "subject", "mail", "sent", "received"]
        let queryLower = query.lowercased()
        
        // Quick keyword check first
        if emailKeywords.contains(where: { queryLower.contains($0) }) {
            return .emailSearch
        }
        
        // Use AI to determine if this is email-related
        do {
            let prompt = """
            Determine if this search query is asking about emails or general information:
            Query: "\(query)"
            
            Respond with only "EMAIL" if this is about emails, messages, or email content.
            Respond with only "GENERAL" if this is a general question not related to emails.
            """
            
            let response = try await openAIService.performAISearch(prompt)
            return response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().contains("EMAIL") ? .emailSearch : .general
        } catch {
            // Fallback to keyword detection
            return emailKeywords.contains(where: { queryLower.contains($0) }) ? .emailSearch : .general
        }
    }
    
    // MARK: - Email Search
    
    private func performEmailSearch(query: String) async -> AISearchResult {
        print("📧 AISearchService: Performing email search for: \"\(query)\"")
        
        do {
            // Get all available emails
            let emails = await getAllAvailableEmails()
            
            if emails.isEmpty {
                return AISearchResult(
                    query: query,
                    response: "No emails found in your inbox to search through.",
                    emails: [],
                    searchType: .emailSearch
                )
            }
            
            // Create search prompt with email data
            let emailData = prepareEmailDataForAI(emails)
            let searchPrompt = createEmailSearchPrompt(query: query, emailData: emailData)
            
            // Get AI response
            let aiResponse = try await openAIService.performAISearch(searchPrompt)
            
            // Extract relevant emails based on AI analysis
            let relevantEmails = await extractRelevantEmails(from: emails, aiResponse: aiResponse, originalQuery: query)
            
            return AISearchResult(
                query: query,
                response: aiResponse,
                emails: relevantEmails,
                searchType: .emailSearch,
                metadata: [
                    "total_emails_searched": "\(emails.count)",
                    "relevant_emails_found": "\(relevantEmails.count)"
                ]
            )
            
        } catch {
            print("❌ AISearchService: Email search error: \(error.localizedDescription)")
            return AISearchResult(
                query: query,
                response: "Failed to search through your emails: \(error.localizedDescription)",
                emails: [],
                searchType: .emailSearch
            )
        }
    }
    
    // MARK: - General Search
    
    private func performGeneralSearch(query: String) async -> AISearchResult {
        print("🧠 AISearchService: Performing general search for: \"\(query)\"")
        
        do {
            let prompt = """
            You are a helpful AI assistant. Answer the following question directly and factually.
            Keep your response concise (max 2 sentences) and specific.
            
            Question: \(query)
            
            Answer:
            """
            
            let response = try await openAIService.performAISearch(prompt)
            
            return AISearchResult(
                query: query,
                response: response,
                emails: [],
                searchType: .general,
                metadata: ["source": isOpenAIConfigured() ? "ChatGPT API" : "Mock Response"]
            )
            
        } catch {
            print("❌ AISearchService: General search error: \(error.localizedDescription)")
            return AISearchResult(
                query: query,
                response: "I'm unable to process your request right now: \(error.localizedDescription)",
                emails: [],
                searchType: .general
            )
        }
    }

    private func isOpenAIConfigured() -> Bool {
        // Accessing published property can be async in Swift 6; wrap via MainActor
        return openAIService.isConfigured
    }
    
    // MARK: - Helper Methods
    
    private func getAllAvailableEmails() async -> [Email] {
        let inboxEmails = await localEmailService.getAllEmails()
        let importantEmails = await localEmailService.loadEmailsBy(category: .important)
        
        
        // Combine and deduplicate
        var allEmails = inboxEmails
        let emailIds = Set(allEmails.map { $0.id })
        
        for email in (importantEmails) {
            if !emailIds.contains(email.id) {
                allEmails.append(email)
            }
        }
        
        // Sort by date (most recent first) and limit to reasonable number
        return Array(allEmails.sorted { $0.date > $1.date }.prefix(100))
    }
    
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
        You are helping search through email data. Based on the user's query and the email data provided, 
        provide a helpful response and identify relevant emails.
        
        User Query: "\(query)"
        
        Email Data:
        \(emailData)
        
        Instructions:
        1. Analyze the emails and provide a helpful response to the user's query
        2. Focus on the most relevant information from the emails
        3. If specific emails are relevant, mention them by their email number (e.g., "Email 1", "Email 5")
        4. Keep your response concise but informative
        5. If no emails match the query, say so clearly
        
        Response:
        """
    }
    
    private func extractRelevantEmails(from emails: [Email], aiResponse: String, originalQuery: String) async -> [Email] {
        // Extract email numbers mentioned in AI response
        let emailNumbers = extractEmailNumbers(from: aiResponse)
        
        // Get emails by their numbers (1-indexed in AI response)
        var relevantEmails: [Email] = []
        for number in emailNumbers {
            let index = number - 1 // Convert to 0-indexed
            if index >= 0 && index < emails.count {
                relevantEmails.append(emails[index])
            }
        }
        
        // If no specific emails were mentioned, try keyword matching
        if relevantEmails.isEmpty {
            relevantEmails = performKeywordMatching(emails: emails, query: originalQuery)
        }
        
        return relevantEmails
    }
    
    private func extractEmailNumbers(from response: String) -> [Int] {
        let pattern = #"Email (\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let matches = regex?.matches(in: response, options: [], range: NSRange(location: 0, length: response.utf16.count)) ?? []
        
        return matches.compactMap { match in
            let range = Range(match.range(at: 1), in: response)
            return range.flatMap { Int(String(response[$0])) }
        }
    }
    
    private func performKeywordMatching(emails: [Email], query: String) -> [Email] {
        let queryWords = query.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).filter { !$0.isEmpty }
        
        return emails.filter { email in
            let searchText = "\(email.subject) \(email.body) \(email.sender.name ?? "") \(email.sender.email)".lowercased()
            return queryWords.contains { word in
                searchText.contains(word)
            }
        }.prefix(10).map { $0 } // Limit to 10 most relevant
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Models

struct AISearchResult {
    let query: String
    let response: String
    let emails: [Email]
    let searchType: AISearchType
    let metadata: [String: String]
    
    init(query: String, response: String, emails: [Email], searchType: AISearchType, metadata: [String: String] = [:]) {
        self.query = query
        self.response = response
        self.emails = emails
        self.searchType = searchType
        self.metadata = metadata
    }
}

enum AISearchType {
    case emailSearch
    case general
    
    var displayName: String {
        switch self {
        case .emailSearch:
            return "Email Search"
        case .general:
            return "General Search"
        }
    }
}
