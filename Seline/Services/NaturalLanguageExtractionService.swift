import Foundation

// MARK: - Extracted Information Model

struct ExtractedLocationInfo {
    let items: [String] // What user bought/mentioned
    let purpose: String? // Why they visited
    let frequency: String? // How often
    let dayOfWeek: String? // Specific day
    let timeOfDay: String? // Specific time
    let rawText: String // Original user input
}

// MARK: - NaturalLanguageExtractionService

@MainActor
class NaturalLanguageExtractionService {
    static let shared = NaturalLanguageExtractionService()
    
    private init() {}
    
    /// Extract information from user's natural language input about a location
    /// Example: "I went to Rexall and bought vitamins and allergy meds for my seasonal allergies"
    /// Returns: items=["vitamins", "allergy meds"], purpose="seasonal allergies"
    func extractInfo(from text: String) -> ExtractedLocationInfo {
        let lowercased = text.lowercased()
        
        // Extract items (what they bought)
        var items: [String] = []
        
        // Common patterns for mentioning items
        let itemPatterns = [
            "bought (.+?)(?:\\s+and\\s+|,|$)",
            "got (.+?)(?:\\s+and\\s+|,|$)",
            "purchased (.+?)(?:\\s+and\\s+|,|$)",
            "picked up (.+?)(?:\\s+and\\s+|,|$)",
            "grabbed (.+?)(?:\\s+and\\s+|,|$)"
        ]
        
        for pattern in itemPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: lowercased, options: [], range: NSRange(location: 0, length: lowercased.utf16.count))
                for match in matches {
                    if match.numberOfRanges > 1,
                       let range = Range(match.range(at: 1), in: lowercased) {
                        let itemText = String(lowercased[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                        // Split by "and" or "," and clean up
                        let itemParts = itemText.replacingOccurrences(of: " and ", with: ",")
                            .components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty && !$0.contains(" for ") && !$0.contains(" to ") }
                        items.append(contentsOf: itemParts)
                    }
                }
            }
        }
        
        // Extract purpose/reason (why they visited)
        var purpose: String? = nil
        
        let purposePatterns = [
            "for (.+?)(?:\\.|$)",
            "because (.+?)(?:\\.|$)",
            "to (.+?)(?:\\.|$)"
        ]
        
        for pattern in purposePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: lowercased, options: [], range: NSRange(location: 0, length: lowercased.utf16.count))
                for match in matches {
                    if match.numberOfRanges > 1,
                       let range = Range(match.range(at: 1), in: lowercased) {
                        purpose = String(lowercased[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                        break
                    }
                }
            }
        }
        
        // Extract frequency
        var frequency: String? = nil
        if lowercased.contains("usually") || lowercased.contains("regularly") || lowercased.contains("often") {
            if lowercased.contains("weekly") || lowercased.contains("every week") {
                frequency = "weekly"
            } else if lowercased.contains("monthly") || lowercased.contains("every month") {
                frequency = "monthly"
            } else if lowercased.contains("daily") || lowercased.contains("every day") {
                frequency = "daily"
            } else {
                frequency = "regularly"
            }
        }
        
        // Extract day of week
        var dayOfWeek: String? = nil
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for day in days {
            if lowercased.contains(day) {
                dayOfWeek = day.capitalized
                break
            }
        }
        
        // Extract time of day
        var timeOfDay: String? = nil
        if lowercased.contains("morning") {
            timeOfDay = "morning"
        } else if lowercased.contains("afternoon") {
            timeOfDay = "afternoon"
        } else if lowercased.contains("evening") || lowercased.contains("night") {
            timeOfDay = "evening"
        }
        
        return ExtractedLocationInfo(
            items: items,
            purpose: purpose,
            frequency: frequency,
            dayOfWeek: dayOfWeek,
            timeOfDay: timeOfDay,
            rawText: text
        )
    }
    
    /// Extract visit purpose from user's natural language input
    /// Example: "Went to get coffee" → "get coffee"
    func extractVisitPurpose(from text: String) -> String? {
        let lowercased = text.lowercased()
        
        // Remove common prefixes
        let prefixes = ["i went", "went", "stopped by", "visited", "i'm at", "i'm visiting"]
        var cleaned = lowercased
        for prefix in prefixes {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        // Extract purpose patterns
        let purposePatterns = [
            "to (.+?)(?:\\.|$)",
            "for (.+?)(?:\\.|$)",
            "because (.+?)(?:\\.|$)"
        ]
        
        for pattern in purposePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let matches = regex.matches(in: cleaned, options: [], range: NSRange(location: 0, length: cleaned.utf16.count))
                for match in matches {
                    if match.numberOfRanges > 1,
                       let range = Range(match.range(at: 1), in: cleaned) {
                        return String(cleaned[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        
        // If no pattern matched, return cleaned text if it's meaningful
        if cleaned.count > 3 && cleaned.count < 100 {
            return cleaned.capitalized
        }
        
        return nil
    }
}
