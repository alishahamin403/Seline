import Foundation
import SwiftUI

/// Centralized provider for category icons and colors
/// Prevents duplication across multiple views
struct CategoryIconProvider {

    // MARK: - Icons (Emoji)

    static func icon(for category: String) -> String {
        let cat = category.lowercased()
        
        if cat.contains("food") || cat.contains("dining") || cat.contains("restaurant") {
            return "🍔"
        } else if cat.contains("transport") || cat.contains("gas") || cat.contains("uber") || cat.contains("lyft") {
            return "🚗"
        } else if cat.contains("health") || cat.contains("medical") || cat.contains("pharmacy") {
            return "🏥"
        } else if cat.contains("entertainment") || cat.contains("movie") || cat.contains("netflix") {
            return "🎬"
        } else if cat.contains("shopping") || cat.contains("retail") || cat.contains("store") {
            return "🛍"
        } else if cat.contains("software") || cat.contains("subscription") || cat.contains("app") {
            return "💻"
        } else if cat.contains("travel") || cat.contains("accommodation") || cat.contains("hotel") || cat.contains("flight") {
            return "✈️"
        } else if cat.contains("utilities") || cat.contains("internet") || cat.contains("electric") || cat.contains("water") {
            return "💡"
        } else if cat.contains("professional") || cat.contains("service") {
            return "💼"
        } else if cat.contains("auto") || cat.contains("vehicle") || cat.contains("car") {
            return "🚙"
        } else if cat.contains("home") || cat.contains("maintenance") || cat.contains("repair") {
            return "🏠"
        } else if cat.contains("membership") || cat.contains("gym") {
            return "💳"
        } else {
            return "📦" // Other
        }
    }

    // MARK: - Colors (SwiftUI Color)
    // Uses neutral, muted colors (same as email avatars) for neutral, easy-on-the-eyes appearance

    static func color(for category: String) -> Color {
        // Neutral, muted colors (same as email avatar fill colors)
        let colors: [Color] = [
            Color(red: 0.45, green: 0.52, blue: 0.60),  // Slate blue-gray
            Color(red: 0.55, green: 0.55, blue: 0.55),  // Neutral gray
            Color(red: 0.40, green: 0.55, blue: 0.55),  // Muted teal
            Color(red: 0.55, green: 0.50, blue: 0.45),  // Warm taupe
            Color(red: 0.50, green: 0.45, blue: 0.55),  // Muted purple
            Color(red: 0.45, green: 0.55, blue: 0.50),  // Sage green
        ]

        // Generate deterministic color based on category name using stable hash
        let hash = HashUtils.deterministicHash(category)
        let colorIndex = abs(hash) % colors.count
        return colors[colorIndex]
    }
}
