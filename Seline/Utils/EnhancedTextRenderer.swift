//
//  EnhancedTextRenderer.swift
//  Seline
//
//  Created by Alishah Amin on 2025-01-27.
//

import SwiftUI
import Foundation

struct EnhancedTextRenderer {
    
    // MARK: - Rich Text Formatting
    
    static func formatEmailBody(_ body: String) -> AttributedString {
        // First, clean the HTML/CSS and extract meaningful text
        let cleanedBody = cleanHTMLContent(body)
        
        var attributedString = AttributedString(cleanedBody)
        
        // Apply base styling
        attributedString.font = DesignSystem.Typography.body
        attributedString.foregroundColor = DesignSystem.Colors.textPrimary
        
        // Format bold text (simple markdown-like)
        formatBoldText(in: &attributedString)
        
        // Format italic text
        formatItalicText(in: &attributedString)
        
        return attributedString
    }
    
    private static func formatURLs(in attributedString: inout AttributedString) {
        let urlPattern = #"https?://[^\s<>"{}|\\^`[\]]+"#
        
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
            let string = String(attributedString.characters)
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            
            for match in matches.reversed() {
                // Safety check for match range
                guard match.range.location != NSNotFound, 
                      match.range.location >= 0,
                      match.range.location + match.range.length <= string.count,
                      let range = Range(match.range, in: string) else {
                    print("⚠️ Warning: Invalid range in formatURLs, skipping")
                    continue
                }
                
                let urlString = String(string[range])
                
                // Find the range in the attributed string safely
                if let attributedRange = attributedString.range(of: urlString) {
                    attributedString[attributedRange].foregroundColor = DesignSystem.Colors.accent
                    attributedString[attributedRange].underlineStyle = .single
                    if let url = URL(string: urlString) {
                        attributedString[attributedRange].link = url
                    }
                }
            }
        }
    }
    
    private static func formatEmailAddresses(in attributedString: inout AttributedString) {
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        
        if let regex = try? NSRegularExpression(pattern: emailPattern) {
            let string = String(attributedString.characters)
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            
            for match in matches.reversed() {
                // Safety check for match range
                guard match.range.location != NSNotFound, 
                      match.range.location >= 0,
                      match.range.location + match.range.length <= string.count,
                      let range = Range(match.range, in: string) else {
                    print("⚠️ Warning: Invalid range in formatEmailAddresses, skipping")
                    continue
                }
                
                let emailString = String(string[range])
                if let attributedRange = attributedString.range(of: emailString) {
                    attributedString[attributedRange].foregroundColor = DesignSystem.Colors.accent
                    if let url = URL(string: "mailto:\(emailString)") {
                        attributedString[attributedRange].link = url
                    }
                }
            }
        }
    }
    
    private static func formatPhoneNumbers(in attributedString: inout AttributedString) {
        let phonePattern = #"\b(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}\b"#
        
        if let regex = try? NSRegularExpression(pattern: phonePattern) {
            let string = String(attributedString.characters)
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: string) {
                    let phoneString = String(string[range])
                    if let attributedRange = attributedString.range(of: phoneString) {
                        attributedString[attributedRange].foregroundColor = DesignSystem.Colors.accent
                        let cleanPhone = phoneString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        if let url = URL(string: "tel:\(cleanPhone)") {
                            attributedString[attributedRange].link = url
                        }
                    }
                }
            }
        }
    }
    
    private static func formatBoldText(in attributedString: inout AttributedString) {
        let boldPattern = #"\*\*(.*?)\*\*"#
        
        if let regex = try? NSRegularExpression(pattern: boldPattern) {
            let string = String(attributedString.characters)
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: string),
                   let textRange = Range(match.range(at: 1), in: string) {
                    let fullMatch = String(string[range])
                    let textContent = String(string[textRange])
                    
                    if let attributedRange = attributedString.range(of: fullMatch) {
                        attributedString.replaceSubrange(attributedRange, with: AttributedString(textContent))
                        if let newRange = attributedString.range(of: textContent) {
                            attributedString[newRange].font = DesignSystem.Typography.bodyMedium
                        }
                    }
                }
            }
        }
    }
    
    private static func formatItalicText(in attributedString: inout AttributedString) {
        let italicPattern = #"\*(.*?)\*"#
        
        if let regex = try? NSRegularExpression(pattern: italicPattern) {
            let string = String(attributedString.characters)
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: string),
                   let textRange = Range(match.range(at: 1), in: string) {
                    let fullMatch = String(string[range])
                    let textContent = String(string[textRange])
                    
                    if let attributedRange = attributedString.range(of: fullMatch) {
                        attributedString.replaceSubrange(attributedRange, with: AttributedString(textContent))
                        if let newRange = attributedString.range(of: textContent) {
                            var container = AttributeContainer()
                            container.font = Font.system(size: 17, design: .default).italic()
                            attributedString[newRange].mergeAttributes(container)
                        }
                    }
                }
            }
        }
    }
    
    private static func formatMeetingLinks(in attributedString: inout AttributedString) {
        let meetingKeywords = ["zoom.us", "teams.microsoft.com", "meet.google.com", "webex.com"]
        
        for keyword in meetingKeywords {
            if let range = attributedString.range(of: keyword, options: .caseInsensitive) {
                attributedString[range].foregroundColor = .blue
                attributedString[range].backgroundColor = Color.blue.opacity(0.1)
                attributedString[range].font = DesignSystem.Typography.bodyMedium
            }
        }
    }
    
    // MARK: - Content Structure Detection
    
    static func extractContentStructure(from body: String) -> EmailContentStructure {
        var structure = EmailContentStructure()
        
        // Extract meeting details
        structure.meetingInfo = extractMeetingInfo(from: body)
        
        // Extract action items
        let actionItemStrings = extractActionItems(from: body)
        structure.actionItems = actionItemStrings.map { ActionItem(text: $0) }
        
        // Extract important dates
        let dateStrings = extractDates(from: body)
        structure.dates = dateStrings.compactMap { dateString in
            // Simple date parsing - in a real implementation you'd want more robust parsing
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            if let date = formatter.date(from: dateString) {
                return ImportantDate(date: date, description: dateString)
            }
            return nil
        }
        
        // Extract contact information
        structure.contacts = extractContacts(from: body)
        
        return structure
    }
    
    private static func extractMeetingInfo(from body: String) -> MeetingInfo? {
        let meetingKeywords = ["meeting", "call", "zoom", "teams", "webex"]
        let timePattern = #"\b(?:1[0-2]|[1-9]):[0-5][0-9]\s?(?:AM|PM|am|pm)\b"#
        
        for keyword in meetingKeywords {
            if body.lowercased().contains(keyword) {
                var meetingInfo = MeetingInfo()
                meetingInfo.title = extractMeetingTitle(from: body)
                meetingInfo.time = extractTime(from: body, pattern: timePattern)
                meetingInfo.joinUrl = extractMeetingUrl(from: body)
                return meetingInfo
            }
        }
        
        return nil
    }
    
    private static func extractMeetingTitle(from body: String) -> String? {
        // Simple extraction - look for lines that might be meeting titles
        let lines = body.components(separatedBy: .newlines)
        for line in lines {
            if line.lowercased().contains("meeting") && line.count < 100 {
                return line.trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private static func extractTime(from body: String, pattern: String) -> String? {
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: body, range: NSRange(location: 0, length: body.count))
            if let match = matches.first,
               let range = Range(match.range, in: body) {
                return String(body[range])
            }
        }
        return nil
    }
    
    private static func extractMeetingUrl(from body: String) -> String? {
        let urlPattern = #"https?://[^\s<>"{}|\\^`[\]]+"#
        let meetingDomains = ["zoom.us", "teams.microsoft.com", "meet.google.com", "webex.com"]
        
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let matches = regex.matches(in: body, range: NSRange(location: 0, length: body.count))
            
            for match in matches {
                if let range = Range(match.range, in: body) {
                    let url = String(body[range])
                    for domain in meetingDomains {
                        if url.contains(domain) {
                            return url
                        }
                    }
                }
            }
        }
        return nil
    }
    
    private static func extractActionItems(from body: String) -> [String] {
        let actionKeywords = ["todo", "action", "task", "please", "need to", "should", "must"]
        let lines = body.components(separatedBy: .newlines)
        var actionItems: [String] = []
        
        for line in lines {
            let lowercaseLine = line.lowercased()
            for keyword in actionKeywords {
                if lowercaseLine.contains(keyword) && line.count > 10 && line.count < 200 {
                    actionItems.append(line.trimmingCharacters(in: .whitespaces))
                    break
                }
            }
        }
        
        return Array(actionItems.prefix(3)) // Limit to 3 action items
    }
    
    private static func extractDates(from body: String) -> [String] {
        let datePattern = #"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2}(?:,\s+\d{4})?\b"#
        
        if let regex = try? NSRegularExpression(pattern: datePattern) {
            let matches = regex.matches(in: body, range: NSRange(location: 0, length: body.count))
            return matches.compactMap { match in
                if let range = Range(match.range, in: body) {
                    return String(body[range])
                }
                return nil
            }
        }
        
        return []
    }
    
    private static func extractContacts(from body: String) -> [String] {
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        
        if let regex = try? NSRegularExpression(pattern: emailPattern) {
            let matches = regex.matches(in: body, range: NSRange(location: 0, length: body.count))
            return matches.compactMap { match in
                if let range = Range(match.range, in: body) {
                    return String(body[range])
                }
                return nil
            }
        }
        
        return []
    }
    
    // MARK: - HTML Content Cleaning
    
    static func cleanHTMLContent(_ htmlString: String) -> String {
        var cleanedString = htmlString
        
        // Remove HTML comments, script tags, and style blocks using NSRegularExpression
        let patterns = [
            "<!--.*?-->",  // HTML comments
            "<script[^>]*>.*?</script>",  // Script tags
            "<style[^>]*>.*?</style>"     // Style tags
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: cleanedString.utf16.count)
                cleanedString = regex.stringByReplacingMatches(in: cleanedString, options: [], range: range, withTemplate: "")
            }
        }
        
        // Remove HTML tags but preserve some structure
        cleanedString = cleanedString.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        cleanedString = cleanedString.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        cleanedString = cleanedString.replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
        cleanedString = cleanedString.replacingOccurrences(of: "</h[1-6]>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        
        // Remove all remaining HTML tags
        cleanedString = cleanedString.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // Remove inline CSS and HTML attributes
        cleanedString = cleanedString.replacingOccurrences(of: "style\\s*=\\s*[\"'][^\"']*[\"']", with: "", options: .regularExpression)
        
        // Remove common CSS properties and selectors that might appear as plain text
        let cssPatterns = [
            "\\{[^}]*\\}",  // Remove CSS rule blocks
            "body\\s*\\{[^}]*\\}",
            "font-family:\\s*[^;]+;?",
            "padding:\\s*[^;]+;?",
            "margin:\\s*[^;]+;?",
            "color:\\s*[^;]+;?",
            "background[^:]*:\\s*[^;]+;?",
            "border[^:]*:\\s*[^;]+;?",
            "text-align:\\s*[^;]+;?",
            "font-size:\\s*[^;]+;?",
            "line-height:\\s*[^;]+;?",
            "width:\\s*[^;]+;?",
            "height:\\s*[^;]+;?",
            "display:\\s*[^;]+;?",
            "max-width:\\s*[^;]+;?",
            "\\.\\w+\\s*\\{[^}]*\\}",  // CSS class selectors
            "#\\w+\\s*\\{[^}]*\\}",   // CSS ID selectors
            "@media[^{]*\\{[^}]*\\}", // Media queries
        ]
        
        for pattern in cssPatterns {
            cleanedString = cleanedString.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        
        // Decode HTML entities
        let htmlEntities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#39;": "'",
            "&hellip;": "...",
        ]
        
        for (entity, replacement) in htmlEntities {
            cleanedString = cleanedString.replacingOccurrences(of: entity, with: replacement)
        }
        
        // Remove URLs and links as requested
        let urlPattern = #"https?://[^\s<>"{}|\\^`[\]]+"#
        cleanedString = cleanedString.replacingOccurrences(of: urlPattern, with: "", options: .regularExpression)
        
        // Remove email addresses to simplify content
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        cleanedString = cleanedString.replacingOccurrences(of: emailPattern, with: "", options: .regularExpression)
        
        // Clean up whitespace and formatting
        // Replace multiple whitespace with single space
        cleanedString = cleanedString.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        // Remove excessive line breaks (more than 2 consecutive)
        cleanedString = cleanedString.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        
        // Trim whitespace
        cleanedString = cleanedString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If the result is still mostly CSS/HTML gibberish, try to extract meaningful content
        if cleanedString.contains("{") || cleanedString.contains("}") || cleanedString.count < 10 {
            // Try to find meaningful sentences or phrases
            let sentences = cleanedString.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            let meaningfulSentences = sentences.filter { sentence in
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.count > 15 && 
                       !trimmed.contains("{") && 
                       !trimmed.contains("}") && 
                       !trimmed.contains("px") &&
                       !trimmed.lowercased().contains("font-family") &&
                       !trimmed.lowercased().contains("background")
            }
            
            if !meaningfulSentences.isEmpty {
                cleanedString = meaningfulSentences.joined(separator: ". ").trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanedString.isEmpty && !cleanedString.hasSuffix(".") && !cleanedString.hasSuffix("!") && !cleanedString.hasSuffix("?") {
                    cleanedString += "."
                }
            }
        }
        
        // Final fallback - if still no meaningful content, return a user-friendly message
        if cleanedString.isEmpty || cleanedString.count < 3 {
            return "This email contains formatting that cannot be displayed as plain text."
        }
        
        return cleanedString
    }
}
