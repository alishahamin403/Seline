import Foundation
import Combine

/// Manages the user's persistent profile, learning from interactions to customize the AI experience.
@MainActor
class UserProfileService: ObservableObject {
    static let shared = UserProfileService()
    
    // MARK: - Models
    
    struct UserProfile: Codable, Equatable {
        var name: String?
        var communicationStyle: CommunicationStyle = .balanced
        var knownFacts: [String] = [] // e.g., "Works 9-5", "Commutes by car"
        var interests: [String] = [] // e.g., "Coding", "Fitness"
        var preferences: [String] = [] // e.g., "Dislikes emojis", "Prefers bullet points"
    }
    
    enum CommunicationStyle: String, Codable {
        case direct // Concise, no fluff
        case balanced // Helpful, friendly but efficient
        case conversational // Chatty, uses emojis, empathetic
        case detailed // Explains reasoning, comprehensive
    }
    
    // MARK: - Properties
    
    @Published private(set) var profile: UserProfile
    private let storageKey = "Seline_UserProfile"
    
    // MARK: - Initialization
    
    private init() {
        // Load from disk or create default
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.profile = decoded
        } else {
            self.profile = UserProfile()
        }
    }
    
    // MARK: - Public API
    
    /// Returns a prompt-ready string description of the user
    func getProfileContext() -> String {
        var context = "USER PROFILE:\n"
        
        if let name = profile.name {
            context += "• Name: \(name)\n"
        }
        
        context += "• Communication Style: \(profile.communicationStyle.rawValue.capitalized)\n"
        
        if !profile.knownFacts.isEmpty {
            context += "• Known Context: \(profile.knownFacts.joined(separator: ", "))\n"
        }
        
        if !profile.interests.isEmpty {
            context += "• Interests: \(profile.interests.joined(separator: ", "))\n"
        }
        
        if !profile.preferences.isEmpty {
            context += "• Preferences: \(profile.preferences.joined(separator: ", "))\n"
        }
        
        return context
    }
    
    /// Update specific fields
    func updateStyle(_ style: CommunicationStyle) {
        profile.communicationStyle = style
        save()
    }
    
    func addFact(_ fact: String) {
        guard !profile.knownFacts.contains(fact) else { return }
        profile.knownFacts.append(fact)
        save()
    }
    
    func removeFact(_ fact: String) {
        profile.knownFacts.removeAll { $0 == fact }
        save()
    }
    
    func addInterest(_ interest: String) {
        guard !profile.interests.contains(interest) else { return }
        profile.interests.append(interest)
        save()
    }
    
    func addPreference(_ preference: String) {
        guard !profile.preferences.contains(preference) else { return }
        profile.preferences.append(preference)
        save()
    }
    
    // MARK: - Persistence
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
