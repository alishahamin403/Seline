//
//  SemanticValidationService.swift
//  Seline
//
//  Created by Claude on 12/12/24.
//

import Foundation

/// Service that validates whether visits make semantic sense based on location type,
/// time of day, duration, and typical patterns
@MainActor
class SemanticValidationService: ObservableObject {
    static let shared = SemanticValidationService()

    private init() {}

    // MARK: - Validation Rules by Category

    struct ValidationRules {
        let typicalHours: ClosedRange<Int>?  // Operating hours (nil = 24/7)
        let minimumDuration: Int              // Minutes
        let maximumDuration: Int?             // Minutes (nil = unlimited)
        let allowedDaysOfWeek: Set<Int>?     // 1=Sunday, 7=Saturday (nil = all days)
    }

    /// Get validation rules for a location category
    private func getRules(for category: String) -> ValidationRules {
        switch category.lowercased() {
        case "restaurant", "cafe", "coffee":
            return ValidationRules(
                typicalHours: 6...23,
                minimumDuration: 15,
                maximumDuration: 180,
                allowedDaysOfWeek: nil
            )

        case "gym", "fitness":
            return ValidationRules(
                typicalHours: 5...23,
                minimumDuration: 20,
                maximumDuration: 180,
                allowedDaysOfWeek: nil
            )

        case "work", "office":
            return ValidationRules(
                typicalHours: 6...22,
                minimumDuration: 60,
                maximumDuration: 720, // 12 hours max work day
                allowedDaysOfWeek: [2, 3, 4, 5, 6] // Mon-Fri
            )

        case "home":
            return ValidationRules(
                typicalHours: nil, // 24/7
                minimumDuration: 30,
                maximumDuration: nil,
                allowedDaysOfWeek: nil
            )

        case "grocery", "supermarket", "store":
            return ValidationRules(
                typicalHours: 7...23,
                minimumDuration: 10,
                maximumDuration: 120,
                allowedDaysOfWeek: nil
            )

        case "bar", "nightclub":
            return ValidationRules(
                typicalHours: 18...3, // Special handling for past midnight
                minimumDuration: 30,
                maximumDuration: 360,
                allowedDaysOfWeek: nil
            )

        case "school", "university", "college":
            return ValidationRules(
                typicalHours: 7...22,
                minimumDuration: 45,
                maximumDuration: 480,
                allowedDaysOfWeek: [2, 3, 4, 5, 6] // Mon-Fri
            )

        case "church", "temple", "mosque", "synagogue":
            return ValidationRules(
                typicalHours: nil,
                minimumDuration: 20,
                maximumDuration: 240,
                allowedDaysOfWeek: nil
            )

        case "hospital", "clinic", "doctor":
            return ValidationRules(
                typicalHours: nil, // Can visit anytime
                minimumDuration: 15,
                maximumDuration: 480,
                allowedDaysOfWeek: nil
            )

        case "park", "recreation":
            return ValidationRules(
                typicalHours: 6...22,
                minimumDuration: 15,
                maximumDuration: 300,
                allowedDaysOfWeek: nil
            )

        case "gas station":
            return ValidationRules(
                typicalHours: nil,
                minimumDuration: 5,
                maximumDuration: 30,
                allowedDaysOfWeek: nil
            )

        default:
            // Generic rules for unknown categories
            return ValidationRules(
                typicalHours: nil,
                minimumDuration: 5,
                maximumDuration: nil,
                allowedDaysOfWeek: nil
            )
        }
    }

    // MARK: - Validation Methods

    /// Validate if a visit makes semantic sense
    /// Returns (isValid, confidence, issues)
    func validateVisit(
        category: String,
        entryTime: Date,
        exitTime: Date?,
        durationMinutes: Int
    ) -> (valid: Bool, confidence: Double, issues: [String]) {
        let rules = getRules(for: category)
        var issues: [String] = []
        var confidence: Double = 1.0

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: entryTime)
        let weekday = calendar.component(.weekday, from: entryTime)

        // Check 1: Operating Hours
        if let typicalHours = rules.typicalHours {
            if !isWithinHours(hour: hour, range: typicalHours) {
                issues.append("Visit at \(hour):00 outside typical hours \(typicalHours)")
                confidence -= 0.3

                // Very suspicious hours (2-5 AM for most places)
                if hour >= 2 && hour <= 5 && category.lowercased() != "home" {
                    confidence -= 0.2
                }
            }
        }

        // Check 2: Duration - Too Short
        if durationMinutes < rules.minimumDuration {
            issues.append("Duration \(durationMinutes)min below minimum \(rules.minimumDuration)min")
            confidence -= 0.25

            // Very short visits are highly suspicious
            if durationMinutes < rules.minimumDuration / 2 {
                confidence -= 0.25
            }
        }

        // Check 3: Duration - Too Long
        if let maxDuration = rules.maximumDuration, durationMinutes > maxDuration {
            issues.append("Duration \(durationMinutes)min exceeds maximum \(maxDuration)min")
            confidence -= 0.2
        }

        // Check 4: Day of Week
        if let allowedDays = rules.allowedDaysOfWeek, !allowedDays.contains(weekday) {
            let dayName = calendar.weekdaySymbols[weekday - 1]
            issues.append("Visit on \(dayName) outside typical days")
            confidence -= 0.15
        }

        // Check 5: Contextual validation
        let contextualIssues = validateContext(category: category, entryTime: entryTime, durationMinutes: durationMinutes)
        if !contextualIssues.isEmpty {
            issues.append(contentsOf: contextualIssues)
            confidence -= Double(contextualIssues.count) * 0.1
        }

        // Clamp confidence between 0 and 1
        confidence = max(0.0, min(1.0, confidence))

        // Consider valid if confidence >= 0.5
        let valid = confidence >= 0.5

        return (valid, confidence, issues)
    }

    /// Check if hour falls within operating hours (handles past-midnight ranges)
    private func isWithinHours(hour: Int, range: ClosedRange<Int>) -> Bool {
        if range.upperBound >= range.lowerBound {
            // Normal range (e.g., 9-17)
            return range.contains(hour)
        } else {
            // Past-midnight range (e.g., 18-3)
            return hour >= range.lowerBound || hour <= range.upperBound
        }
    }

    /// Additional contextual validation rules
    private func validateContext(category: String, entryTime: Date, durationMinutes: Int) -> [String] {
        var issues: [String] = []

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: entryTime)
        let minute = calendar.component(.minute, from: entryTime)

        switch category.lowercased() {
        case "gym", "fitness":
            // Very short gym visits are suspicious
            if durationMinutes < 20 {
                issues.append("Gym visit under 20 minutes unlikely")
            }

        case "restaurant", "cafe":
            // Restaurant visits at odd hours
            if (hour < 6 || (hour >= 15 && hour < 17) || hour >= 23) {
                // Outside breakfast/lunch/dinner times
                issues.append("Restaurant visit outside typical meal times")
            }

        case "gas station":
            // Gas station visits should be very brief
            if durationMinutes > 20 {
                issues.append("Gas station visit over 20 minutes unusual")
            }

        case "work", "office":
            // Work visits on weekends
            let weekday = calendar.component(.weekday, from: entryTime)
            if weekday == 1 || weekday == 7 { // Sunday or Saturday
                // Not necessarily wrong, but worth noting
                issues.append("Work visit on weekend")
            }

            // Very brief work visits
            if durationMinutes < 30 {
                issues.append("Work visit under 30 minutes unusual")
            }

        case "grocery", "supermarket":
            // Very long grocery trips
            if durationMinutes > 90 {
                issues.append("Grocery visit over 90 minutes unusual")
            }

        default:
            break
        }

        return issues
    }

    /// Quick validation - just check if category/time combination is reasonable
    func isReasonable(category: String, hour: Int) -> Bool {
        let rules = getRules(for: category)

        // Check operating hours
        if let typicalHours = rules.typicalHours {
            return isWithinHours(hour: hour, range: typicalHours)
        }

        // 24/7 locations always reasonable
        return true
    }

    /// Get human-readable validation summary
    func getValidationSummary(category: String, entryTime: Date, durationMinutes: Int) -> String {
        let (valid, confidence, issues) = validateVisit(
            category: category,
            entryTime: entryTime,
            exitTime: entryTime.addingTimeInterval(Double(durationMinutes * 60)),
            durationMinutes: durationMinutes
        )

        if valid {
            return "✅ Valid visit (confidence: \(Int(confidence * 100))%)"
        } else {
            let issueList = issues.joined(separator: ", ")
            return "⚠️ Suspicious visit (confidence: \(Int(confidence * 100))%): \(issueList)"
        }
    }
}
