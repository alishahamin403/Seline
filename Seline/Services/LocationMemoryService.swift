import Foundation
import PostgREST

// MARK: - LocationMemory Model

struct LocationMemory: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let savedPlaceId: UUID
    let memoryType: MemoryType
    let content: String // Natural language description
    let items: [String]? // For purchases: ["vitamins", "allergy meds"]
    let frequency: String? // "weekly", "monthly", "occasionally"
    let dayOfWeek: String? // If specific to certain days
    let timeOfDay: String? // If specific to certain times
    let createdAt: Date
    var updatedAt: Date
    
    enum MemoryType: String, Codable {
        case purchase // What user usually buys
        case purpose // Why user visits
        case habit // Regular patterns
        case preference // User preferences for this location
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case savedPlaceId = "saved_place_id"
        case memoryType = "memory_type"
        case content
        case items
        case frequency
        case dayOfWeek = "day_of_week"
        case timeOfDay = "time_of_day"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - LocationMemoryService

@MainActor
class LocationMemoryService: ObservableObject {
    static let shared = LocationMemoryService()
    
    private init() {}
    
    // MARK: - CRUD Operations
    
    /// Save or update a location memory
    func saveMemory(
        placeId: UUID,
        type: LocationMemory.MemoryType,
        content: String,
        items: [String]? = nil,
        frequency: String? = nil,
        dayOfWeek: String? = nil,
        timeOfDay: String? = nil
    ) async throws {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "LocationMemoryService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let client = await SupabaseManager.shared.getPostgrestClient()
        
        // Prepare items as JSONB
        var itemsJSON: PostgREST.AnyJSON? = nil
        if let items = items, !items.isEmpty {
            itemsJSON = .object(items.reduce(into: [:]) { dict, item in
                dict[item] = .string(item)
            })
        }
        
        let memoryData: [String: PostgREST.AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "saved_place_id": .string(placeId.uuidString),
            "memory_type": .string(type.rawValue),
            "content": .string(content),
            "items": itemsJSON ?? .null,
            "frequency": frequency != nil ? .string(frequency!) : .null,
            "day_of_week": dayOfWeek != nil ? .string(dayOfWeek!) : .null,
            "time_of_day": timeOfDay != nil ? .string(timeOfDay!) : .null,
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        
        // Use upsert to update if exists, insert if new
        try await client
            .from("location_memories")
            .upsert(memoryData, onConflict: "user_id,saved_place_id,memory_type")
            .execute()
    }
    
    /// Get all memories for a location
    func getMemories(for placeId: UUID) async throws -> [LocationMemory] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "LocationMemoryService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let client = await SupabaseManager.shared.getPostgrestClient()
        let response = try await client
            .from("location_memories")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("saved_place_id", value: placeId.uuidString)
            .order("updated_at", ascending: false)
            .execute()
        
        let decoder = JSONDecoder.supabaseDecoder()
        return try decoder.decode([LocationMemory].self, from: response.data)
    }
    
    /// Get specific memory type for a location
    func getMemory(for placeId: UUID, type: LocationMemory.MemoryType) async throws -> LocationMemory? {
        let memories = try await getMemories(for: placeId)
        return memories.first { $0.memoryType == type }
    }
    
    /// Delete a memory
    func deleteMemory(_ memoryId: UUID) async throws {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "LocationMemoryService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }
        
        let client = await SupabaseManager.shared.getPostgrestClient()
        try await client
            .from("location_memories")
            .delete()
            .eq("id", value: memoryId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
}
