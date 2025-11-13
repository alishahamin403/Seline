import Foundation

/// Manages persistent storage and loading of user profiles
class UserProfilePersistenceService {
    private static let userProfileKey = "com.vibecode.seline.userprofile"
    private static let userProfileDirectory = "UserProfiles"

    /// Load existing user profile or return nil if none exists
    static func loadUserProfile() -> UserProfile? {
        // Try to load from UserDefaults first (simple key-value storage)
        if let data = UserDefaults.standard.data(forKey: userProfileKey) {
            do {
                let decoder = JSONDecoder()
                let profile = try decoder.decode(UserProfile.self, from: data)
                print("📋 Loaded user profile: \(profile.totalSessionsAnalyzed) sessions analyzed")
                return profile
            } catch {
                print("❌ Error decoding user profile: \(error)")
                return nil
            }
        }

        // No profile found
        print("📋 No existing user profile found")
        return nil
    }

    /// Save user profile to persistent storage
    static func saveUserProfile(_ profile: UserProfile) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(profile)
            UserDefaults.standard.set(data, forKey: userProfileKey)
            print("💾 User profile saved (\(profile.totalSessionsAnalyzed) sessions)")
        } catch {
            print("❌ Error saving user profile: \(error)")
        }
    }

    /// Update user profile by learning from current session patterns
    static func updateProfileFromPatterns(_ currentPatterns: UserPatterns, existingProfile: UserProfile?) -> UserProfile {
        var builder = UserProfileBuilder()

        if let existing = existingProfile {
            // Start with existing data
            builder.createdDate = existing.createdDate
            builder.totalSessionsAnalyzed = existing.totalSessionsAnalyzed + 1
            builder.preferredCategories = existing.preferredCategories
            builder.favoriteLocations = existing.favoriteLocations
            builder.frequentActivities = existing.frequentActivities
            builder.preferredCuisines = existing.preferredCuisines
            builder.busySeasons = existing.busySeasons
            builder.quietSeasons = existing.quietSeasons
            builder.responsePreferences = existing.responsePreferences
            builder.queryTopics = existing.queryTopics
            builder.notablePreferences = existing.notablePreferences

            // Add new spending record
            if existing.historicalAverageMonthlySpending > 0 {
                builder.spendingRecords = [existing.historicalAverageMonthlySpending]
            }
            builder.spendingRecords.append(currentPatterns.averageMonthlySpending)

            // Add new event record
            if existing.typicalEventsPerMonth > 0 {
                builder.eventRecords = [existing.typicalEventsPerMonth]
            }
            builder.eventRecords.append(currentPatterns.averageEventsPerWeek * 4.33)  // weeks to months
        } else {
            // First time - initialize from current patterns
            builder.totalSessionsAnalyzed = 1
            builder.spendingRecords = [currentPatterns.averageMonthlySpending]
            builder.eventRecords = [currentPatterns.averageEventsPerWeek * 4.33]
        }

        // Update from current patterns
        let currentCategories = currentPatterns.topExpenseCategories.map { $0.category }
        builder.preferredCategories = mergeStringLists(builder.preferredCategories, with: currentCategories, maxItems: 5)

        let currentLocations = currentPatterns.mostVisitedLocations.map { $0.name }
        builder.favoriteLocations = mergeStringLists(builder.favoriteLocations, with: currentLocations, maxItems: 5)

        builder.frequentActivities = mergeStringLists(
            builder.frequentActivities,
            with: currentPatterns.mostFrequentEvents.map { $0.title },
            maxItems: 5
        )

        builder.preferredCuisines = mergeStringLists(
            builder.preferredCuisines,
            with: currentPatterns.favoriteRestaurantTypes,
            maxItems: 3
        )

        // Build and return updated profile
        let updatedProfile = builder.build()
        saveUserProfile(updatedProfile)

        return updatedProfile
    }

    /// Merge string lists, keeping top items by frequency
    private static func mergeStringLists(_ existing: [String], with new: [String], maxItems: Int) -> [String] {
        var merged = existing
        for item in new {
            if !merged.contains(item) {
                merged.append(item)
            }
        }
        // Keep only top maxItems
        return Array(merged.prefix(maxItems))
    }

    /// Format user profile into readable context for LLM
    static func formatProfileForLLM(_ profile: UserProfile) -> String {
        var formatted = ""

        formatted += "## LEARNED USER PROFILE\n\n"

        formatted += "HISTORICAL SPENDING:\n"
        formatted += "• Average Monthly: $\(String(format: "%.2f", profile.historicalAverageMonthlySpending))\n"
        formatted += "• Range: $\(String(format: "%.2f", profile.spendingRange.min)) - $\(String(format: "%.2f", profile.spendingRange.max))\n"
        formatted += "• Typical Categories: \(profile.preferredCategories.joined(separator: ", "))\n\n"

        formatted += "ACTIVITY PATTERNS:\n"
        formatted += "• Average Events/Month: \(String(format: "%.1f", profile.typicalEventsPerMonth))\n"
        formatted += "• Frequent Activities: \(profile.frequentActivities.joined(separator: ", "))\n\n"

        formatted += "LOCATION PREFERENCES:\n"
        formatted += "• Favorite Places: \(profile.favoriteLocations.joined(separator: ", "))\n"
        formatted += "• Preferred Cuisines: \(profile.preferredCuisines.joined(separator: ", "))\n\n"

        formatted += "PROFILE NOTES:\n"
        formatted += "• Sessions Analyzed: \(profile.totalSessionsAnalyzed)\n"
        formatted += "• Profile Created: \(DateFormatter.localizedString(from: profile.createdDate, dateStyle: .medium, timeStyle: .none))\n"
        formatted += "• Last Updated: \(DateFormatter.localizedString(from: profile.lastUpdated, dateStyle: .medium, timeStyle: .none))\n"

        if !profile.notablePreferences.isEmpty {
            formatted += "• Notable Preferences: \(profile.notablePreferences.joined(separator: ", "))\n"
        }

        formatted += "\n"

        return formatted
    }

    /// Clear user profile data on logout
    static func clearUserProfile() {
        UserDefaults.standard.removeObject(forKey: userProfileKey)
        print("🗑️ Cleared user profile data")
    }
}
