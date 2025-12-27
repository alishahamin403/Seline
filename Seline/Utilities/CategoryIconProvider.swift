import Foundation

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

    static func color(for category: String) -> Color {
        switch category {
        case "Food & Dining":
            return Color(red: 0.831, green: 0.647, blue: 0.455) // #D4A574 (tan/brown)
        case "Transportation":
            return Color(red: 0.627, green: 0.533, blue: 0.408) // #A08968 (brown)
        case "Healthcare":
            return Color(red: 0.831, green: 0.710, blue: 0.627) // #D4B5A0 (light tan)
        case "Entertainment":
            return Color(red: 0.722, green: 0.627, blue: 0.537) // #B8A089 (warm tan)
        case "Shopping":
            return Color(red: 0.792, green: 0.722, blue: 0.659) // #C9B8A8 (light brown)
        case "Software & Subscriptions":
            return Color(red: 0.4, green: 0.6, blue: 0.8) // #6699CC (tech blue)
        case "Accommodation & Travel":
            return Color(red: 0.8, green: 0.6, blue: 0.4) // #CC9966 (travel orange)
        case "Utilities & Internet":
            return Color(red: 0.5, green: 0.7, blue: 0.6) // #80B399 (utility green)
        case "Professional Services":
            return Color(red: 0.7, green: 0.5, blue: 0.8) // #B380CC (professional purple)
        case "Auto & Vehicle":
            return Color(red: 0.8, green: 0.5, blue: 0.4) // #CC8066 (auto red)
        case "Home & Maintenance":
            return Color(red: 0.6, green: 0.7, blue: 0.5) // #99B380 (home green)
        case "Memberships":
            return Color(red: 0.8, green: 0.7, blue: 0.4) // #CCB366 (gold)
        case "Services":
            return Color(red: 0.639, green: 0.608, blue: 0.553) // #A39B8D (legacy services - taupe)
        case "Food":
            return Color(red: 0.831, green: 0.647, blue: 0.455) // #D4A574 (legacy food)
        default:
            return Color.gray
        }
    }
}

import SwiftUI
