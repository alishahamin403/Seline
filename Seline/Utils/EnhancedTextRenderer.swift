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
        var attributedString = AttributedString(body)
        
        // Apply base styling
        attributedString.font = DesignSystem.Typography.body
        attributedString.foregroundColor = DesignSystem.Colors.systemTextPrimary
        
        // Format URLs
        formatURLs(in: &attributedString)
        
        // Format email addresses
        formatEmailAddresses(in: &attributedString)
        
        // Format phone numbers
        formatPhoneNumbers(in: &attributedString)
        
        // Format bold text (simple markdown-like)
        formatBoldText(in: &attributedString)
        
        // Format italic text
        formatItalicText(in: &attributedString)
        
        // Format meeting links with special styling
        formatMeetingLinks(in: &attributedString)
        
        return attributedString
    }
    
    private static func formatURLs(in attributedString: inout AttributedString) {
        let urlPattern = #"https?://[^\s<>"{}|\\^`[\]]+"#
        
        if let regex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
            let string = String(attributedString.characters)
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: string) {
                    let urlString = String(string[range])
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
    }
    
    private static func formatEmailAddresses(in attributedString: inout AttributedString) {
        let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
        
        if let regex = try? NSRegularExpression(pattern: emailPattern) {
            let string = String(attributedString.characters)
            let matches = regex.matches(in: string, range: NSRange(location: 0, length: string.count))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: string) {
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
        structure.actionItems = extractActionItems(from: body)
        
        // Extract important dates
        structure.dates = extractDates(from: body)
        
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
}

// MARK: - Supporting Models

struct EmailContentStructure {
    var meetingInfo: MeetingInfo?
    var actionItems: [String] = []
    var dates: [String] = []
    var contacts: [String] = []
}

struct MeetingInfo {
    var title: String?
    var time: String?
    var joinUrl: String?
}
