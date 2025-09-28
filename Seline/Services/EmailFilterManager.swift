import Foundation
import SwiftUI

@MainActor
class EmailFilterManager: ObservableObject {
    static let shared = EmailFilterManager()

    @AppStorage("emailFilterPreferences") private var filterPreferencesData: Data = Data()
    @Published var preferences: EmailFilterPreferences = .default

    private init() {
        loadPreferences()
    }

    private func loadPreferences() {
        if !filterPreferencesData.isEmpty {
            do {
                preferences = try JSONDecoder().decode(EmailFilterPreferences.self, from: filterPreferencesData)
            } catch {
                print("Failed to decode filter preferences: \(error)")
                preferences = .default
            }
        }
    }

    func savePreferences() {
        do {
            let data = try JSONEncoder().encode(preferences)
            filterPreferencesData = data
        } catch {
            print("Failed to encode filter preferences: \(error)")
        }
    }

    func toggleCategory(_ category: EmailCategory) {
        preferences.toggleCategory(category)
        savePreferences()
    }

    func isCategoryEnabled(_ category: EmailCategory) -> Bool {
        return preferences.isCategoryEnabled(category)
    }

    func enableAllCategories() {
        preferences.enabledCategories = Set(EmailCategory.allCases)
        savePreferences()
    }

    func disableAllCategories() {
        preferences.enabledCategories = []
        savePreferences()
    }

    func resetToDefaults() {
        preferences = .default
        savePreferences()
    }

    func categorizeEmail(_ email: Email) -> EmailCategory {
        let subject = email.subject.lowercased()
        let senderEmail = email.sender.email.lowercased()
        let senderName = email.sender.name?.lowercased() ?? ""
        let snippet = email.snippet.lowercased()

        // Check for promotional emails
        let promotionalKeywords = [
            "newsletter", "unsubscribe", "promo", "promotion", "sale", "discount",
            "offer", "deal", "marketing", "advertisement", "special offer", "limited time"
        ]

        let promotionalSenders = [
            "marketing", "promo", "newsletter", "offers", "deals", "sales"
        ]

        if promotionalKeywords.contains(where: { subject.contains($0) || snippet.contains($0) }) ||
           promotionalSenders.contains(where: { senderEmail.contains($0) || senderName.contains($0) }) {
            return .promotional
        }

        // Check for automated emails
        let automatedKeywords = ["no-reply", "noreply", "donotreply", "automated", "system", "notification"]
        let automatedSenders = ["noreply", "no-reply", "donotreply", "automated", "system"]

        if automatedKeywords.contains(where: { subject.contains($0) || senderEmail.contains($0) }) ||
           automatedSenders.contains(where: { senderEmail.contains($0) || senderName.contains($0) }) {
            return .automated
        }

        // Check for updates
        let updateKeywords = ["update", "notification", "digest", "summary", "weekly", "daily", "monthly"]

        if updateKeywords.contains(where: { subject.contains($0) || snippet.contains($0) }) {
            return .updates
        }

        // Check for social media
        let socialKeywords = ["facebook", "twitter", "instagram", "linkedin", "social", "follow", "like", "comment"]
        let socialSenders = ["facebook", "twitter", "instagram", "linkedin", "social"]

        if socialKeywords.contains(where: { subject.contains($0) || snippet.contains($0) }) ||
           socialSenders.contains(where: { senderEmail.contains($0) }) {
            return .social
        }

        // Check for work emails (common work domains and keywords)
        let workDomains = [".com", ".org", ".net", ".gov", ".edu"]
        let workKeywords = ["meeting", "project", "deadline", "report", "conference", "team", "office", "work"]

        let hasWorkDomain = workDomains.contains { senderEmail.contains($0) }
        let hasWorkKeywords = workKeywords.contains { subject.contains($0) || snippet.contains($0) }

        // If it has work indicators and doesn't seem personal, classify as work
        if hasWorkDomain && hasWorkKeywords && !senderEmail.contains("gmail.") && !senderEmail.contains("yahoo.") && !senderEmail.contains("hotmail.") {
            return .work
        }

        // Default to personal for everything else
        return .personal
    }

    func shouldShowEmail(_ email: Email) -> Bool {
        let category = categorizeEmail(email)
        return isCategoryEnabled(category)
    }

    func getEnabledCategoriesCount() -> Int {
        return preferences.enabledCategories.count
    }

    func getFilteredEmailCount(from emails: [Email]) -> Int {
        return emails.filter { shouldShowEmail($0) }.count
    }

    func getEmailCountForCategory(_ category: EmailCategory, from emails: [Email]) -> Int {
        return emails.filter { categorizeEmail($0) == category }.count
    }
}