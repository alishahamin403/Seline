import SwiftUI

struct TimelineEventColorManager {
    // MARK: - Blue Color Palette for Timeline Events
    // Variations based on light/dark mode and filter type

    enum FilterType: Equatable {
        case all
        case personal
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
    static func timelineEventAccentColor(
        filterType: FilterType,
        colorScheme: ColorScheme
    ) -> Color {
        switch filterType {
        case .all:
            // "All" filter uses a balanced blue
            return colorScheme == .dark ?
                Color(red: 0.518, green: 0.792, blue: 0.914) : // #84cae9 (lighter for dark mode)
                Color(red: 0.396, green: 0.635, blue: 0.737)   // #65a2bc (darker for light mode)

        case .personal:
            // "Personal" filter uses the primary blue shade (darker in light mode, lighter in dark mode)
            return colorScheme == .dark ?
                Color(red: 0.40, green: 0.65, blue: 0.80) : // Lighter blue for dark mode
                Color(red: 0.20, green: 0.34, blue: 0.40)   // #345766 (darker blue for light mode)

        case .tag(let tagId):
            // Tag-based events use a secondary blue shade, slightly different from personal
            return colorScheme == .dark ?
                Color(red: 0.50, green: 0.72, blue: 0.88) : // Slightly different lighter blue for dark mode
                Color(red: 0.298, green: 0.486, blue: 0.565) // #4c7c90 (different dark blue for light mode)
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
