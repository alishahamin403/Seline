import Foundation

struct RecurringEventStat: Identifiable, Equatable {
    let id: String
    let eventName: String
    let frequency: RecurrenceFrequency
    let expectedCount: Int
    let completedCount: Int
    let missedCount: Int
    let missedDates: [Date]
    let completionRate: Double

    init(id: String, eventName: String, frequency: RecurrenceFrequency, expectedCount: Int, completedCount: Int, missedDates: [Date]) {
        self.id = id
        self.eventName = eventName
        self.frequency = frequency
        self.expectedCount = expectedCount
        self.completedCount = completedCount
        self.missedCount = missedDates.count
        self.missedDates = missedDates
        self.completionRate = expectedCount > 0 ? Double(completedCount) / Double(expectedCount) : 0.0
    }

    var completionPercentage: Int {
        return Int(completionRate * 100)
    }

    var frequencyDisplayName: String {
        return frequency.displayName
    }
}

struct WeeklyMissedEventSummary {
    let weekStartDate: Date
    let weekEndDate: Date
    let missedEvents: [MissedEventDetail]
    let totalMissedCount: Int

    struct MissedEventDetail: Identifiable {
        let id: String
        let eventName: String
        let frequency: RecurrenceFrequency
        let missedCount: Int
        let expectedCount: Int

        var missRate: Double {
            return expectedCount > 0 ? Double(missedCount) / Double(expectedCount) : 0.0
        }

        var missRatePercentage: Int {
            return Int(missRate * 100)
        }
    }
}

struct MonthlySummary {
    let monthDate: Date
    let totalEvents: Int
    let completedEvents: Int
    let incompleteEvents: Int
    let completionRate: Double
    let recurringCompletedCount: Int
    let recurringMissedCount: Int
    let oneTimeCompletedCount: Int
    let topCompletedEvents: [String] // Top 5 most frequently completed events

    var completionPercentage: Int {
        return Int(completionRate * 100)
    }

    var hasSignificantActivity: Bool {
        return totalEvents > 0
    }
}
