import Foundation
import EventKit

// MARK: - Calendar Metadata

/// Represents an iPhone calendar with its metadata
struct CalendarMetadata: Identifiable, Codable, Equatable {
    let id: String // EKCalendar.calendarIdentifier
    let title: String
    let sourceType: CalendarSourceType
    let sourceTitle: String
    let color: String // Hex color string
    let allowsContentModifications: Bool

    var displayName: String {
        return title
    }

    var sourceDescription: String {
        return "\(sourceType.displayName) - \(sourceTitle)"
    }
}

// MARK: - Calendar Source Type

/// Calendar source types from EventKit
enum CalendarSourceType: String, Codable, CaseIterable {
    case local = "Local"
    case calDAV = "CalDAV" // iCloud calendars
    case exchange = "Exchange"
    case subscription = "Subscription"
    case birthdays = "Birthdays"
    case mobileMe = "MobileMe" // Legacy iCloud

    var displayName: String {
        switch self {
        case .local: return "Device"
        case .calDAV: return "iCloud"
        case .exchange: return "Exchange"
        case .subscription: return "Subscribed"
        case .birthdays: return "Birthdays"
        case .mobileMe: return "iCloud (Legacy)"
        }
    }

    var iconName: String {
        switch self {
        case .local: return "iphone"
        case .calDAV: return "icloud"
        case .exchange: return "building.2"
        case .subscription: return "link"
        case .birthdays: return "gift"
        case .mobileMe: return "icloud"
        }
    }

    /// Convert from EKSourceType to CalendarSourceType
    static func from(ekSourceType: EKSourceType) -> CalendarSourceType {
        switch ekSourceType {
        case .local:
            return .local
        case .calDAV:
            return .calDAV
        case .exchange:
            return .exchange
        case .subscribed:
            return .subscription
        case .birthdays:
            return .birthdays
        case .mobileMe:
            return .mobileMe
        @unknown default:
            return .local
        }
    }
}

// MARK: - Calendar Selection Preferences

/// Stores user's selected calendars for syncing
class CalendarSyncPreferences: Codable {
    /// Set of calendar identifiers that user wants to sync
    var selectedCalendarIds: Set<String>

    /// Last time preferences were updated
    var lastUpdated: Date

    init(selectedCalendarIds: Set<String> = [], lastUpdated: Date = Date()) {
        self.selectedCalendarIds = selectedCalendarIds
        self.lastUpdated = lastUpdated
    }

    // MARK: - Persistence

    private static let preferencesKey = "calendarSyncPreferences"
    private static let userDefaults = UserDefaults.standard

    /// Save preferences to UserDefaults
    func save() {
        let encoder = JSONEncoder()
        if let encoded = try? encoder.encode(self) {
            Self.userDefaults.set(encoded, forKey: Self.preferencesKey)
            print("✅ Saved calendar preferences: \(selectedCalendarIds.count) calendars selected")
        }
    }

    /// Load preferences from UserDefaults
    static func load() -> CalendarSyncPreferences {
        if let data = userDefaults.data(forKey: preferencesKey),
           let decoded = try? JSONDecoder().decode(CalendarSyncPreferences.self, from: data) {
            print("📥 Loaded calendar preferences: \(decoded.selectedCalendarIds.count) calendars selected")
            return decoded
        }
        return CalendarSyncPreferences()
    }

    /// Clear all preferences
    static func clear() {
        userDefaults.removeObject(forKey: preferencesKey)
        print("🗑️ Cleared calendar preferences")
    }

    // MARK: - Selection Management

    /// Add a calendar to selection
    func select(calendarId: String) {
        selectedCalendarIds.insert(calendarId)
        lastUpdated = Date()
    }

    /// Remove a calendar from selection
    func deselect(calendarId: String) {
        selectedCalendarIds.remove(calendarId)
        lastUpdated = Date()
    }

    /// Toggle calendar selection
    func toggle(calendarId: String) {
        if selectedCalendarIds.contains(calendarId) {
            deselect(calendarId: calendarId)
        } else {
            select(calendarId: calendarId)
        }
    }

    /// Check if calendar is selected
    func isSelected(calendarId: String) -> Bool {
        return selectedCalendarIds.contains(calendarId)
    }

    /// Select all calendars from a list
    func selectAll(calendarIds: [String]) {
        selectedCalendarIds.formUnion(calendarIds)
        lastUpdated = Date()
    }

    /// Deselect all calendars
    func deselectAll() {
        selectedCalendarIds.removeAll()
        lastUpdated = Date()
    }
}

// MARK: - EKCalendar Extension

extension EKCalendar {
    /// Convert to CalendarMetadata
    func toMetadata() -> CalendarMetadata {
        return CalendarMetadata(
            id: calendarIdentifier,
            title: title,
            sourceType: CalendarSourceType.from(ekSourceType: source.sourceType),
            sourceTitle: source.title,
            color: cgColor.toHexString(),
            allowsContentModifications: allowsContentModifications
        )
    }
}

// MARK: - CGColor Extension

extension CGColor {
    /// Convert CGColor to hex string
    func toHexString() -> String {
        guard let components = components, components.count >= 3 else {
            return "#000000"
        }

        let r = Int(components[0] * 255.0)
        let g = Int(components[1] * 255.0)
        let b = Int(components[2] * 255.0)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
