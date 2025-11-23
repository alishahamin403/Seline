import SwiftUI

struct TimelineEventColorManager {
    // MARK: - Google Brand Color Palette for Timeline Events
    // Using Google's brand colors for each filter type, with light/dark mode variants

    enum FilterType: Equatable {
        case personal
        case personalSync        // Calendar synced events
        case tag(_ id: String)
    }

    enum ButtonStyle: Equatable {
        case all
        case personal
        case personalSync
        case tag(_ id: String)
    }

    // MARK: - Get Background Color for Timeline Event
    /// Returns the appropriate Google brand color for timeline event background based on filter type and color scheme
    static func timelineEventBackgroundColor(
        filterType: FilterType,
        colorScheme: ColorScheme,
        isCompleted: Bool
    ) -> Color {
        let accentColor = timelineEventAccentColor(filterType: filterType, colorScheme: colorScheme)

        if isCompleted {
            return accentColor.opacity(0.4)
        } else {
            return accentColor.opacity(colorScheme == .dark ? 0.25 : 0.2)
        }
    }

    // MARK: - Get Accent Color for Timeline Event
    /// Returns the appropriate color for the timeline event based on task type and color scheme
    /// Event colors are based on the task's actual type, not the selected filter view
    static func timelineEventAccentColor(
        filterType: FilterType,
        colorScheme: ColorScheme
    ) -> Color {
        switch filterType {
        case .personal:
            // Personal events use Google Green #34A853
            return colorScheme == .dark ?
                Color(red: 0.7020, green: 0.9216, blue: 0.7647) : // #b3ebc3 (light green for dark mode)
                Color(red: 0.2039, green: 0.6588, blue: 0.3255)   // #34A853 (Google Green for light mode)

        case .personalSync:
            // Calendar synced events use Google Red #EA4335
            return colorScheme == .dark ?
                Color(red: 0.9804, green: 0.7451, blue: 0.7216) : // #ffb3a6 (light red for dark mode)
                Color(red: 0.9176, green: 0.2627, blue: 0.2078)   // #EA4335 (Google Red for light mode)

        case .tag(let tagId):
            // Tag-based events use the tag's actual color from TagColorPalette
            return getTagColor(tagId: tagId)
        }
    }

    // MARK: - Get Actual Tag Color
    /// Looks up the tag from TagManager and returns its actual color from TagColorPalette
    static func getTagColor(tagId: String) -> Color {
        // Call nonisolated method that's safe from any context
        return TagManager.shared.getTagColorForUI(tagId: tagId)
    }

    // MARK: - Get Button Color for Filter Buttons
    /// Returns the color for filter buttons based on button style
    /// Uses actual tag colors from TagColorPalette for tagged filters
    static func filterButtonAccentColor(
        buttonStyle: ButtonStyle,
        colorScheme: ColorScheme
    ) -> Color {
        switch buttonStyle {
        case .all:
            // "All" button is neutral black/white (no special color)
            return colorScheme == .dark ?
                Color(red: 0.3, green: 0.3, blue: 0.3)  // Dark gray for dark mode
                : Color(red: 0.9, green: 0.9, blue: 0.9) // Light gray for light mode

        case .personal:
            // Personal uses Google Green #34A853
            return colorScheme == .dark ?
                Color(red: 0.7020, green: 0.9216, blue: 0.7647) : // #b3ebc3 (light green for dark mode)
                Color(red: 0.2039, green: 0.6588, blue: 0.3255)   // #34A853 (Google Green for light mode)

        case .personalSync:
            // Sync uses Google Red #EA4335
            return colorScheme == .dark ?
                Color(red: 0.9804, green: 0.7451, blue: 0.7216) : // #ffb3a6 (light red for dark mode)
                Color(red: 0.9176, green: 0.2627, blue: 0.2078)   // #EA4335 (Google Red for light mode)

        case .tag(let tagId):
            // Tags use the tag's actual color from TagColorPalette
            return getTagColor(tagId: tagId)
        }
    }

    // MARK: - Determine Filter Type from Task
    /// Helper to determine the filter type based on task's tagId and event source
    static func filterType(from task: TaskItem) -> FilterType {
        // Check if it's a calendar sync event (ID starts with "cal_")
        if task.id.hasPrefix("cal_") {
            return .personalSync
        }

        // Check if it has a tag
        if let tagId = task.tagId, !tagId.isEmpty {
            return .tag(tagId)
        }

        // Default to personal
        return .personal
    }
}
