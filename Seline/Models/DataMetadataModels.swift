import Foundation

// MARK: - Comprehensive Metadata Models for Intelligent LLM Filtering

/// Lightweight metadata for all data types - sent to LLM for intelligent filtering
struct AppDataMetadata: Codable {
    let receipts: [ReceiptMetadata]
    let events: [EventMetadata]
    let locations: [LocationMetadata]
    let notes: [NoteMetadata]
    let emails: [EmailMetadata]

    var isEmpty: Bool {
        receipts.isEmpty && events.isEmpty && locations.isEmpty && notes.isEmpty && emails.isEmpty
    }
}

// MARK: - Receipt Metadata

struct ReceiptMetadata: Codable, Identifiable {
    let id: UUID
    let merchant: String
    let amount: Double
    let date: Date
    let category: String? // food, gas, etc
    let preview: String? // First 50 chars of content
    let monthYear: String? // "November 2025" for grouping
    let dayOfWeek: String? // "Monday", "Tuesday" etc

    var formattedAmount: String {
        String(format: "$%.2f", amount)
    }

    var isRecent: Bool {
        let calendar = Calendar.current
        let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day ?? Int.max
        return daysAgo <= 30
    }
}

// MARK: - Event Metadata

struct EventMetadata: Codable, Identifiable {
    let id: String
    let title: String
    let date: Date?
    let time: Date? // scheduled time
    let endTime: Date?
    let description: String? // description field
    let location: String? // location if available
    let reminder: String? // reminder time
    let isRecurring: Bool
    let recurrencePattern: String? // "daily", "weekly", "monthly"
    let isCompleted: Bool
    let completedDates: [Date]? // for recurring: which instances were completed
    let eventType: String? // "work", "personal", "fitness", "meeting", etc
    let priority: Int? // 1-5 priority level if available

    var formattedDateTime: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        guard let eventDate = date else { return "No date" }
        return dateFormatter.string(from: eventDate)
    }

    var completionCount: Int {
        completedDates?.count ?? 0
    }

    var completionCountThisMonth: Int {
        guard let completedDates = completedDates else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)

        return completedDates.filter { date in
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            return month == currentMonth && year == currentYear
        }.count
    }

    var completionCountLastMonth: Int {
        guard let completedDates = completedDates else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let currentMonth = calendar.component(.month, from: now)
        let currentYear = calendar.component(.year, from: now)
        let lastMonth = currentMonth == 1 ? 12 : currentMonth - 1
        let lastYear = currentMonth == 1 ? currentYear - 1 : currentYear

        return completedDates.filter { date in
            let month = calendar.component(.month, from: date)
            let year = calendar.component(.year, from: date)
            return month == lastMonth && year == lastYear
        }.count
    }
}

// MARK: - Location Metadata

struct LocationMetadata: Codable, Identifiable {
    let id: UUID
    let name: String
    let customName: String?
    let category: String // cuisine/category type
    let address: String
    let city: String? // City/Town name for geographic filtering
    let province: String? // Province/State name for geographic filtering
    let country: String? // Country name
    let userRating: Int? // 1-10 user rating
    let notes: String? // user's notes about the restaurant
    let cuisine: String? // user's cuisine classification
    let dateCreated: Date
    let dateModified: Date
    let visitCount: Int? // Total number of visits/mentions
    let lastVisited: Date? // Last time visited
    let isFrequent: Bool? // True if visited more than once

    var displayName: String {
        customName ?? name
    }

    var hasNotes: Bool {
        notes?.isEmpty == false
    }

    var visitFrequencyLabel: String {
        guard let count = visitCount else { return "Not tracked" }
        switch count {
        case 0: return "Not visited"
        case 1: return "Once"
        case 2...5: return "\(count) times (occasional)"
        case 6...: return "\(count) times (frequent)"
        default: return "\(count) times"
        }
    }

    var daysSinceVisit: Int? {
        guard let lastVisited = lastVisited else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: lastVisited, to: Date()).day
    }
}

// MARK: - Note Metadata

struct NoteMetadata: Codable, Identifiable {
    let id: UUID
    let title: String
    let preview: String // First 100 chars
    let dateCreated: Date
    let dateModified: Date
    let isPinned: Bool
    let folder: String? // folder name if applicable

    var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        return dateFormatter.string(from: dateModified)
    }
}

// MARK: - Email Metadata

struct EmailMetadata: Codable, Identifiable {
    let id: String
    let from: String // sender email
    let subject: String
    let snippet: String // first line of email
    let date: Date
    let isRead: Bool
    let isImportant: Bool
    let hasAttachments: Bool

    var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
    }
}

// MARK: - LLM Response Model

/// Response from LLM indicating which data it needs
struct DataFilteringResponse: Codable {
    let receiptIds: [UUID]?
    let eventIds: [String]?
    let locationIds: [UUID]?
    let noteIds: [UUID]?
    let emailIds: [String]?
    let reasoning: String? // why it selected these items

    var isEmpty: Bool {
        (receiptIds?.isEmpty ?? true) &&
        (eventIds?.isEmpty ?? true) &&
        (locationIds?.isEmpty ?? true) &&
        (noteIds?.isEmpty ?? true) &&
        (emailIds?.isEmpty ?? true)
    }
}

// MARK: - User Patterns (for predictive intelligence)

/// Learned patterns about user behavior for smarter LLM responses
struct UserPatterns: Codable {
    // Spending patterns
    let topExpenseCategories: [CategorySpending]  // Top spending categories by amount
    let averageMonthlySpending: Double
    let spendingTrend: String  // "increasing", "decreasing", "stable"

    // Event/activity patterns
    let mostFrequentEvents: [EventFrequency]  // Events they do most often
    let averageEventsPerWeek: Double
    let favoriteEventTypes: [String]  // "gym", "work", "personal", etc.

    // Location patterns
    let mostVisitedLocations: [LocationVisit]  // Places they visit most
    let favoriteRestaurantTypes: [String]  // Cuisines they prefer

    // Time patterns
    let mostActiveTimeOfDay: String  // "morning", "afternoon", "evening"
    let busyDays: [String]  // "Monday", "Tuesday", etc.

    // General preferences
    let averageExpenseAmount: Double  // Average transaction size
    let totalTransactions: Int
    let dataPoints: Int  // How many items we analyzed
}

struct CategorySpending: Codable {
    let category: String
    let totalAmount: Double
    let percentage: Double
    let transactionCount: Int
}

struct EventFrequency: Codable {
    let title: String
    let timesPerMonth: Double
    let eventType: String?
    let averageDaysApart: Double?
}

struct LocationVisit: Codable {
    let name: String
    let visitCount: Int
    let category: String
    let lastVisited: Date?
}

// MARK: - Persistent User Profile (cross-session learning)

/// Spending range for user profile
struct SpendingRange: Codable {
    let min: Double
    let max: Double
}

/// Rich user profile that persists across sessions and learns over time
struct UserProfile: Codable {
    // Profile metadata
    let createdDate: Date
    let lastUpdated: Date
    let totalSessionsAnalyzed: Int  // How many conversation sessions have we learned from?

    // Learned preferences
    let preferredCategories: [String]  // Top spending categories
    let favoriteLocations: [String]
    let frequentActivities: [String]
    let preferredCuisines: [String]

    // Historical patterns
    let historicalAverageMonthlySpending: Double
    let spendingRange: SpendingRange
    let typicalEventsPerMonth: Double
    let busySeasons: [String]  // Months they spend more
    let quietSeasons: [String]  // Months they spend less

    // Behavioral insights
    let responsePreferences: [String]  // "detailed", "concise", "comparisons", etc.
    let queryTopics: [String: Int]  // Topic frequency tracking
    let notablePreferences: [String]  // Special preferences we've learned

    // Version tracking (for migration if profile format changes)
    let profileVersion: Int = 1
}

/// User profile that's actively being built/updated
struct UserProfileBuilder {
    var createdDate: Date = Date()
    var totalSessionsAnalyzed: Int = 0

    var preferredCategories: [String] = []
    var favoriteLocations: [String] = []
    var frequentActivities: [String] = []
    var preferredCuisines: [String] = []

    var historicalAverageMonthlySpending: Double = 0
    var spendingRecords: [Double] = []
    var typicalEventsPerMonth: Double = 0
    var eventRecords: [Double] = []

    var busySeasons: [String] = []
    var quietSeasons: [String] = []
    var responsePreferences: [String] = []
    var queryTopics: [String: Int] = [:]
    var notablePreferences: [String] = []

    mutating func build() -> UserProfile {
        // Calculate ranges and averages
        let spendingMin = spendingRecords.min() ?? 0
        let spendingMax = spendingRecords.max() ?? 0
        let spendingAvg = spendingRecords.isEmpty ? 0 : spendingRecords.reduce(0, +) / Double(spendingRecords.count)

        let eventsAvg = eventRecords.isEmpty ? 0 : eventRecords.reduce(0, +) / Double(eventRecords.count)

        return UserProfile(
            createdDate: createdDate,
            lastUpdated: Date(),
            totalSessionsAnalyzed: totalSessionsAnalyzed,
            preferredCategories: preferredCategories,
            favoriteLocations: favoriteLocations,
            frequentActivities: frequentActivities,
            preferredCuisines: preferredCuisines,
            historicalAverageMonthlySpending: spendingAvg,
            spendingRange: SpendingRange(min: spendingMin, max: spendingMax),
            typicalEventsPerMonth: eventsAvg,
            busySeasons: busySeasons,
            quietSeasons: quietSeasons,
            responsePreferences: responsePreferences,
            queryTopics: queryTopics,
            notablePreferences: notablePreferences
        )
    }
}
