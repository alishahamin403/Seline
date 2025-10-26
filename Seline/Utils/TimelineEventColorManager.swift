import SwiftUI

struct TimelineEventColorManager {
    // MARK: - Blue Color Palette for Timeline Events
    // Variations based on light/dark mode and filter type

    enum FilterType: Equatable {
        case all
        case personal
        case personalSync        // Calendar synced events
        case tag(_ id: String)
    }

    // MARK: - Get Background Color for Timeline Event
    /// Returns the appropriate blue color for timeline event background based on filter type and color scheme
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
    /// Returns the appropriate blue shade for the timeline event based on filter type and color scheme
    /// Each filter type has a distinctly different blue color for clear visual differentiation
    static func timelineEventAccentColor(
        filterType: FilterType,
        colorScheme: ColorScheme
    ) -> Color {
        switch filterType {
        case .all:
            // "All" filter uses the medium blue
            return colorScheme == .dark ?
                Color(red: 0.847, green: 0.925, blue: 0.969) : // #d8ecf7 (lightest blue for dark mode)
                Color(red: 0.518, green: 0.792, blue: 0.914)   // #84cae9 (medium blue for light mode)

        case .personal:
            // "Personal" filter uses a distinct medium-light blue
            return colorScheme == .dark ?
                Color(red: 0.518, green: 0.792, blue: 0.914) : // #84cae9 (medium blue for dark mode)
                Color(red: 0.396, green: 0.635, blue: 0.737)   // #65a2bc (blue-gray for light mode)

        case .personalSync:
            // "Personal - Sync" (Calendar synced events) uses teal/cyan for distinction
            return colorScheme == .dark ?
                Color(red: 0.6, green: 0.9, blue: 0.85)      // #99e5d8 (light teal for dark mode)
                : Color(red: 0.2, green: 0.6, blue: 0.55)    // #339988 (teal for light mode)

        case .tag(_):
            // Tag-based events use the darker blue for strong contrast
            return colorScheme == .dark ?
                Color(red: 0.396, green: 0.635, blue: 0.737) : // #65a2bc (blue-gray for dark mode)
                Color(red: 0.20, green: 0.34, blue: 0.40)      // #345766 (darker blue for light mode)
        }
    }

    // MARK: - Determine Filter Type from Task
    /// Helper to determine the filter type based on task's tagId
    static func filterType(from task: TaskItem) -> FilterType {
        if let tagId = task.tagId, !tagId.isEmpty {
            return .tag(tagId)
        } else {
            return .personal
        }
    }
}
