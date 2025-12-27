import SwiftUI

struct TimelineEventColorManager {
    // MARK: - Neutral Color Palette (20 colors for dark/light mode)
    // Pre-selected neutral colors that work effectively in both dark and light modes
    
    struct NeutralColorPalette {
        // 20 distinct neutral colors with dark/light mode variants
        // Each color is represented as (darkModeColor, lightModeColor)
        // All colors use white text for consistency
        static let colors: [(dark: Color, light: Color, needsLightText: Bool)] = [
            // 1. Slate blue-gray
            (Color(red: 0.5, green: 0.55, blue: 0.65), Color(red: 0.3, green: 0.35, blue: 0.45), true),
            // 2. Sage green
            (Color(red: 0.45, green: 0.6, blue: 0.55), Color(red: 0.25, green: 0.4, blue: 0.35), true),
            // 3. Dusty rose
            (Color(red: 0.65, green: 0.5, blue: 0.55), Color(red: 0.45, green: 0.3, blue: 0.35), true),
            // 4. Muted purple
            (Color(red: 0.6, green: 0.5, blue: 0.65), Color(red: 0.4, green: 0.3, blue: 0.45), true),
            // 5. Warm terracotta
            (Color(red: 0.7, green: 0.55, blue: 0.45), Color(red: 0.5, green: 0.35, blue: 0.25), true),
            // 6. Cool teal
            (Color(red: 0.4, green: 0.6, blue: 0.65), Color(red: 0.2, green: 0.4, blue: 0.45), true),
            // 7. Soft lavender
            (Color(red: 0.65, green: 0.55, blue: 0.7), Color(red: 0.45, green: 0.35, blue: 0.5), true),
            // 8. Olive green
            (Color(red: 0.55, green: 0.6, blue: 0.45), Color(red: 0.35, green: 0.4, blue: 0.25), true),
            // 9. Burnt orange
            (Color(red: 0.7, green: 0.5, blue: 0.4), Color(red: 0.5, green: 0.3, blue: 0.2), true),
            // 10. Steel blue
            (Color(red: 0.45, green: 0.55, blue: 0.7), Color(red: 0.25, green: 0.35, blue: 0.5), true),
            // 11. Mauve
            (Color(red: 0.65, green: 0.5, blue: 0.6), Color(red: 0.45, green: 0.3, blue: 0.4), true),
            // 12. Forest green
            (Color(red: 0.4, green: 0.55, blue: 0.5), Color(red: 0.2, green: 0.35, blue: 0.3), true),
            // 13. Rust brown
            (Color(red: 0.65, green: 0.45, blue: 0.4), Color(red: 0.45, green: 0.25, blue: 0.2), true),
            // 14. Periwinkle blue
            (Color(red: 0.55, green: 0.5, blue: 0.7), Color(red: 0.35, green: 0.3, blue: 0.5), true),
            // 15. Moss green
            (Color(red: 0.5, green: 0.65, blue: 0.5), Color(red: 0.3, green: 0.45, blue: 0.3), true),
            // 16. Dusty coral
            (Color(red: 0.7, green: 0.55, blue: 0.5), Color(red: 0.5, green: 0.35, blue: 0.3), true),
            // 17. Deep indigo
            (Color(red: 0.45, green: 0.5, blue: 0.7), Color(red: 0.25, green: 0.3, blue: 0.5), true),
            // 18. Sage blue-green
            (Color(red: 0.4, green: 0.65, blue: 0.6), Color(red: 0.2, green: 0.45, blue: 0.4), true),
            // 19. Plum
            (Color(red: 0.6, green: 0.45, blue: 0.55), Color(red: 0.4, green: 0.25, blue: 0.35), true),
            // 20. Charcoal blue
            (Color(red: 0.5, green: 0.5, blue: 0.6), Color(red: 0.3, green: 0.3, blue: 0.4), true),
        ]
        
        static func colorForIndex(_ index: Int, colorScheme: ColorScheme) -> Color {
            let normalizedIndex = index % colors.count
            let colorPair = colors[normalizedIndex]
            return colorScheme == .dark ? colorPair.dark : colorPair.light
        }
        
        static func needsLightText(_ index: Int) -> Bool {
            let normalizedIndex = index % colors.count
            return colors[normalizedIndex].needsLightText
        }
    }

    enum FilterType: Equatable, Hashable {
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
        isCompleted: Bool,
        tagColorIndex: Int? = nil
    ) -> Color {
        let accentColor = timelineEventAccentColor(filterType: filterType, colorScheme: colorScheme, tagColorIndex: tagColorIndex)

        // Return solid color (no opacity) - for completed events, use same solid color
        // Completion is indicated by strikethrough text, not color dimming
        return accentColor
    }
    
    // MARK: - Get Text Color for Timeline Event
    /// Returns white text color for all events (consistent across dark and light mode)
    static func timelineEventTextColor(
        filterType: FilterType,
        colorScheme: ColorScheme,
        tagColorIndex: Int? = nil
    ) -> Color {
        // Always use white text for events in both dark and light mode
        return Color.white
    }

    // MARK: - Get Accent Color for Timeline Event
    /// Returns the appropriate color for the timeline event based on task type and color scheme
    /// Uses neutral color palette for all filter types
    static func timelineEventAccentColor(
        filterType: FilterType,
        colorScheme: ColorScheme,
        tagColorIndex: Int? = nil
    ) -> Color {
        switch filterType {
        case .personal:
            // Personal events use neutral color index 0
            return NeutralColorPalette.colorForIndex(0, colorScheme: colorScheme)

        case .personalSync:
            // Calendar synced events use neutral color index 1
            return NeutralColorPalette.colorForIndex(1, colorScheme: colorScheme)

        case .tag(let tagId):
            // Tag-based events use the tag's colorIndex from the neutral palette
            return getTagColor(tagId: tagId, colorIndex: tagColorIndex, colorScheme: colorScheme)
        }
    }

    // MARK: - Get Actual Tag Color
    /// Returns the color for a tag based on the actual stored colorIndex
    /// When colorIndex is not available, uses a deterministic hash-based approach
    /// Uses neutral color palette (20 colors) that work in both dark and light modes
    static func getTagColor(tagId: String, colorIndex: Int? = nil, colorScheme: ColorScheme? = nil) -> Color {
        let index: Int
        if let colorIndex = colorIndex {
            index = colorIndex
        } else {
            // Fallback: Use hash of tag ID for deterministic color (same hash across rebuilds)
            let hash = tagId.hashValue
            index = abs(hash) % 20  // 20 colors in NeutralColorPalette
        }
        
        // Use the colorScheme parameter if provided, otherwise default to current scheme
        // For now, we'll need to pass colorScheme when calling this
        // But since we can't access environment here, we'll return a color that works in both modes
        // The caller should pass colorScheme when available
        if let colorScheme = colorScheme {
            return NeutralColorPalette.colorForIndex(index, colorScheme: colorScheme)
        } else {
            // Default to light mode variant (will be overridden by caller with colorScheme)
            return NeutralColorPalette.colorForIndex(index, colorScheme: .light)
        }
    }
    
    // Helper to determine if a tag color needs white or black text
    static func tagColorTextColor(colorIndex: Int, colorScheme: ColorScheme) -> Color {
        // Always use white text for tags in both dark and light mode
        return Color.white
    }

    // MARK: - Get Button Color for Filter Buttons
    /// Returns the color for filter buttons based on button style
    /// Uses neutral color palette for all filter types
    static func filterButtonAccentColor(
        buttonStyle: ButtonStyle,
        colorScheme: ColorScheme,
        tagColorIndex: Int? = nil
    ) -> Color {
        switch buttonStyle {
        case .all:
            // "All" button uses camera icon color
            return Color(red: 0.2, green: 0.2, blue: 0.2)

        case .personal:
            // Personal uses neutral color index 0
            return NeutralColorPalette.colorForIndex(0, colorScheme: colorScheme)

        case .personalSync:
            // Sync uses neutral color index 1
            return NeutralColorPalette.colorForIndex(1, colorScheme: colorScheme)

        case .tag(let tagId):
            // Tags use the tag's actual colorIndex from neutral palette
            return getTagColor(tagId: tagId, colorIndex: tagColorIndex, colorScheme: colorScheme)
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
