import Foundation
import SwiftUI
import PostgREST

// MARK: - Person Models

/// Represents a person saved by the user with personal info and relationships
struct Person: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var nickname: String?
    var relationship: RelationshipType
    var customRelationship: String? // For "Other" relationship type
    
    // Personal Attributes
    var birthday: Date?
    var favouriteFood: String?
    var favouriteGift: String?
    var favouriteColor: String?
    var interests: [String]?
    var notes: String?
    var howWeMet: String?
    
    // Contact Info
    var phone: String?
    var email: String?
    var address: String?
    var instagram: String?
    var linkedIn: String?
    
    // Photo
    var photoURL: String?
    
    // Relationships with other people
    var linkedPeople: [PersonLink]?
    
    // Location connections (stored separately in junction table, loaded on demand)
    var favouritePlaceIds: [UUID]?
    
    // Metadata
    var isFavourite: Bool
    var dateCreated: Date
    var dateModified: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        nickname: String? = nil,
        relationship: RelationshipType = .friend,
        customRelationship: String? = nil,
        birthday: Date? = nil,
        favouriteFood: String? = nil,
        favouriteGift: String? = nil,
        favouriteColor: String? = nil,
        interests: [String]? = nil,
        notes: String? = nil,
        howWeMet: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        address: String? = nil,
        instagram: String? = nil,
        linkedIn: String? = nil,
        photoURL: String? = nil,
        linkedPeople: [PersonLink]? = nil,
        favouritePlaceIds: [UUID]? = nil,
        isFavourite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.relationship = relationship
        self.customRelationship = customRelationship
        self.birthday = birthday
        self.favouriteFood = favouriteFood
        self.favouriteGift = favouriteGift
        self.favouriteColor = favouriteColor
        self.interests = interests
        self.notes = notes
        self.howWeMet = howWeMet
        self.phone = phone
        self.email = email
        self.address = address
        self.instagram = instagram
        self.linkedIn = linkedIn
        self.photoURL = photoURL
        self.linkedPeople = linkedPeople
        self.favouritePlaceIds = favouritePlaceIds
        self.isFavourite = isFavourite
        self.dateCreated = Date()
        self.dateModified = Date()
    }
    
    // MARK: - Computed Properties
    
    /// Display name - shows nickname if set, otherwise name
    var displayName: String {
        return nickname ?? name
    }
    
    /// Formatted birthday string
    var formattedBirthday: String? {
        guard let birthday = birthday else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: birthday)
    }
    
    /// Age calculated from birthday
    var age: Int? {
        guard let birthday = birthday else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: birthday, to: now)
        return ageComponents.year
    }
    
    /// Relationship display text
    var relationshipDisplayText: String {
        if relationship == .other, let custom = customRelationship {
            return custom
        }
        return relationship.displayName
    }
    
    /// Get the icon for this person based on relationship
    func getDisplayIcon() -> String {
        return relationship.icon
    }
    
    /// Get initials for avatar placeholder
    var initials: String {
        let names = name.split(separator: " ")
        if names.count >= 2 {
            return String(names[0].prefix(1) + names[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Relationship Type

enum RelationshipType: String, Codable, CaseIterable, Hashable {
    case family = "family"
    case closeFriend = "close_friend"
    case friend = "friend"
    case coworker = "coworker"
    case acquaintance = "acquaintance"
    case partner = "partner"
    case neighbor = "neighbor"
    case classmate = "classmate"
    case mentor = "mentor"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .family: return "Family"
        case .closeFriend: return "Close Friend"
        case .friend: return "Friend"
        case .coworker: return "Coworker"
        case .acquaintance: return "Acquaintance"
        case .partner: return "Partner"
        case .neighbor: return "Neighbor"
        case .classmate: return "Classmate"
        case .mentor: return "Mentor"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .family: return "figure.2.and.child.holdinghands"
        case .closeFriend: return "heart.fill"
        case .friend: return "person.2.fill"
        case .coworker: return "briefcase.fill"
        case .acquaintance: return "person.fill"
        case .partner: return "heart.circle.fill"
        case .neighbor: return "house.and.flag.fill"
        case .classmate: return "graduationcap.fill"
        case .mentor: return "star.fill"
        case .other: return "person.crop.circle"
        }
    }
    
    var sortOrder: Int {
        switch self {
        case .family: return 0
        case .partner: return 1
        case .closeFriend: return 2
        case .friend: return 3
        case .coworker: return 4
        case .classmate: return 5
        case .neighbor: return 6
        case .mentor: return 7
        case .acquaintance: return 8
        case .other: return 9
        }
    }
}

// MARK: - Person Link (Relationship between people)

/// Represents a relationship link between two people
struct PersonLink: Codable, Hashable, Identifiable {
    var id: UUID
    var personId: UUID
    var relatedPersonId: UUID
    var relationshipLabel: String // e.g., "Mother", "Brother", "Manager", "Wife"
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        personId: UUID,
        relatedPersonId: UUID,
        relationshipLabel: String
    ) {
        self.id = id
        self.personId = personId
        self.relatedPersonId = relatedPersonId
        self.relationshipLabel = relationshipLabel
        self.createdAt = Date()
    }
}

// MARK: - Visit Person Connection

/// Represents a person connected to a location visit
struct VisitPersonConnection: Codable, Hashable, Identifiable {
    var id: UUID
    var visitId: UUID
    var personId: UUID
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        visitId: UUID,
        personId: UUID
    ) {
        self.id = id
        self.visitId = visitId
        self.personId = personId
        self.createdAt = Date()
    }
}

// MARK: - Receipt Person Connection

/// Represents a person connected to a receipt (note)
struct ReceiptPersonConnection: Codable, Hashable, Identifiable {
    var id: UUID
    var noteId: UUID
    var personId: UUID
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        noteId: UUID,
        personId: UUID
    ) {
        self.id = id
        self.noteId = noteId
        self.personId = personId
        self.createdAt = Date()
    }
}

// MARK: - Person Favourite Place

/// Represents a favourite place for a person
struct PersonFavouritePlace: Codable, Hashable, Identifiable {
    var id: UUID
    var personId: UUID
    var placeId: UUID
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        personId: UUID,
        placeId: UUID
    ) {
        self.id = id
        self.personId = personId
        self.placeId = placeId
        self.createdAt = Date()
    }
}

// MARK: - Supabase Data Structures

struct PersonSupabaseData: Codable {
    let id: String
    let user_id: String
    let name: String
    let nickname: String?
    let relationship: String
    let custom_relationship: String?
    let birthday: String?
    let favourite_food: String?
    let favourite_gift: String?
    let favourite_color: String?
    let interests: [String]?
    let notes: String?
    let how_we_met: String?
    let phone: String?
    let email: String?
    let address: String?
    let instagram: String?
    let linkedin: String?
    let photo_url: String?
    let is_favourite: Bool
    let date_created: String
    let date_modified: String
}

struct PersonLinkSupabaseData: Codable {
    let id: String
    let person_id: String
    let related_person_id: String
    let relationship_label: String
    let created_at: String
}

struct VisitPersonSupabaseData: Codable {
    let id: String
    let visit_id: String
    let person_id: String
    let created_at: String
}

struct ReceiptPersonSupabaseData: Codable {
    let id: String
    let note_id: String
    let person_id: String
    let created_at: String
}

struct PersonFavouritePlaceSupabaseData: Codable {
    let id: String
    let person_id: String
    let place_id: String
    let created_at: String
}

// MARK: - Conversion Helpers

extension Person {
    init?(from data: PersonSupabaseData) {
        guard let id = UUID(uuidString: data.id) else {
            print("❌ Failed to parse person ID: \(data.id)")
            return nil
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var dateCreated = formatter.date(from: data.date_created)
        var dateModified = formatter.date(from: data.date_modified)
        
        if dateCreated == nil {
            formatter.formatOptions = [.withInternetDateTime]
            dateCreated = formatter.date(from: data.date_created)
        }
        
        if dateModified == nil {
            formatter.formatOptions = [.withInternetDateTime]
            dateModified = formatter.date(from: data.date_modified)
        }
        
        guard let dateCreated = dateCreated, let dateModified = dateModified else {
            print("❌ Failed to parse dates for person: \(data.name)")
            return nil
        }
        
        // Parse birthday if present
        var birthday: Date? = nil
        if let birthdayStr = data.birthday {
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            birthday = dateOnlyFormatter.date(from: birthdayStr)
        }
        
        // Parse relationship type
        let relationship = RelationshipType(rawValue: data.relationship) ?? .friend
        
        self.id = id
        self.name = data.name
        self.nickname = data.nickname
        self.relationship = relationship
        self.customRelationship = data.custom_relationship
        self.birthday = birthday
        self.favouriteFood = data.favourite_food
        self.favouriteGift = data.favourite_gift
        self.favouriteColor = data.favourite_color
        self.interests = data.interests
        self.notes = data.notes
        self.howWeMet = data.how_we_met
        self.phone = data.phone
        self.email = data.email
        self.address = data.address
        self.instagram = data.instagram
        self.linkedIn = data.linkedin
        self.photoURL = data.photo_url
        self.linkedPeople = nil // Loaded separately
        self.favouritePlaceIds = nil // Loaded separately
        self.isFavourite = data.is_favourite
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }
    
    func toSupabaseData(userId: UUID) -> [String: PostgREST.AnyJSON] {
        let formatter = ISO8601DateFormatter()
        
        var data: [String: PostgREST.AnyJSON] = [
            "id": .string(id.uuidString),
            "user_id": .string(userId.uuidString),
            "name": .string(name),
            "relationship": .string(relationship.rawValue),
            "is_favourite": .bool(isFavourite),
            "date_created": .string(formatter.string(from: dateCreated)),
            "date_modified": .string(formatter.string(from: dateModified))
        ]
        
        // Optional fields
        data["nickname"] = nickname != nil ? .string(nickname!) : .null
        data["custom_relationship"] = customRelationship != nil ? .string(customRelationship!) : .null
        
        if let birthday = birthday {
            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            data["birthday"] = .string(dateOnlyFormatter.string(from: birthday))
        } else {
            data["birthday"] = .null
        }
        
        data["favourite_food"] = favouriteFood != nil ? .string(favouriteFood!) : .null
        data["favourite_gift"] = favouriteGift != nil ? .string(favouriteGift!) : .null
        data["favourite_color"] = favouriteColor != nil ? .string(favouriteColor!) : .null
        
        if let interests = interests, !interests.isEmpty {
            data["interests"] = .array(interests.map { .string($0) })
        } else {
            data["interests"] = .null
        }
        
        data["notes"] = notes != nil ? .string(notes!) : .null
        data["how_we_met"] = howWeMet != nil ? .string(howWeMet!) : .null
        data["phone"] = phone != nil ? .string(phone!) : .null
        data["email"] = email != nil ? .string(email!) : .null
        data["address"] = address != nil ? .string(address!) : .null
        data["instagram"] = instagram != nil ? .string(instagram!) : .null
        data["linkedin"] = linkedIn != nil ? .string(linkedIn!) : .null
        data["photo_url"] = photoURL != nil ? .string(photoURL!) : .null
        
        return data
    }
}

extension PersonLink {
    init?(from data: PersonLinkSupabaseData) {
        guard let id = UUID(uuidString: data.id),
              let personId = UUID(uuidString: data.person_id),
              let relatedPersonId = UUID(uuidString: data.related_person_id) else {
            return nil
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var createdAt = formatter.date(from: data.created_at)
        if createdAt == nil {
            formatter.formatOptions = [.withInternetDateTime]
            createdAt = formatter.date(from: data.created_at)
        }
        
        guard let createdAt = createdAt else { return nil }
        
        self.id = id
        self.personId = personId
        self.relatedPersonId = relatedPersonId
        self.relationshipLabel = data.relationship_label
        self.createdAt = createdAt
    }
}

extension VisitPersonConnection {
    init?(from data: VisitPersonSupabaseData) {
        guard let id = UUID(uuidString: data.id),
              let visitId = UUID(uuidString: data.visit_id),
              let personId = UUID(uuidString: data.person_id) else {
            return nil
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var createdAt = formatter.date(from: data.created_at)
        if createdAt == nil {
            formatter.formatOptions = [.withInternetDateTime]
            createdAt = formatter.date(from: data.created_at)
        }
        
        guard let createdAt = createdAt else { return nil }
        
        self.id = id
        self.visitId = visitId
        self.personId = personId
        self.createdAt = createdAt
    }
}

extension ReceiptPersonConnection {
    init?(from data: ReceiptPersonSupabaseData) {
        guard let id = UUID(uuidString: data.id),
              let noteId = UUID(uuidString: data.note_id),
              let personId = UUID(uuidString: data.person_id) else {
            return nil
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var createdAt = formatter.date(from: data.created_at)
        if createdAt == nil {
            formatter.formatOptions = [.withInternetDateTime]
            createdAt = formatter.date(from: data.created_at)
        }
        
        guard let createdAt = createdAt else { return nil }
        
        self.id = id
        self.noteId = noteId
        self.personId = personId
        self.createdAt = createdAt
    }
}

extension PersonFavouritePlace {
    init?(from data: PersonFavouritePlaceSupabaseData) {
        guard let id = UUID(uuidString: data.id),
              let personId = UUID(uuidString: data.person_id),
              let placeId = UUID(uuidString: data.place_id) else {
            return nil
        }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var createdAt = formatter.date(from: data.created_at)
        if createdAt == nil {
            formatter.formatOptions = [.withInternetDateTime]
            createdAt = formatter.date(from: data.created_at)
        }
        
        guard let createdAt = createdAt else { return nil }
        
        self.id = id
        self.personId = personId
        self.placeId = placeId
        self.createdAt = createdAt
    }
}

// MARK: - Person Metadata for LLM Context

struct PersonMetadata: Codable, Identifiable {
    let id: UUID
    let name: String
    let nickname: String?
    let relationship: String
    let birthday: String?
    let favouriteFood: String?
    let favouriteGift: String?
    let favouriteColor: String?
    let isFavourite: Bool
    
    init(from person: Person) {
        self.id = person.id
        self.name = person.name
        self.nickname = person.nickname
        self.relationship = person.relationshipDisplayText
        self.birthday = person.formattedBirthday
        self.favouriteFood = person.favouriteFood
        self.favouriteGift = person.favouriteGift
        self.favouriteColor = person.favouriteColor
        self.isFavourite = person.isFavourite
    }
}
