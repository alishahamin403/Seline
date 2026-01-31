import Foundation
import PostgREST

/**
 * UserMemoryService - Manages persistent user knowledge/memory
 *
 * Stores contextual information the LLM should remember:
 * - Entity relationships: "JVM" → "haircuts"
 * - Merchant categories: "Starbucks" → "coffee"
 * - User preferences: "prefers detailed responses"
 * - Facts: "works 9-5"
 * - Patterns: "gym visits usually 1 hour"
 */
@MainActor
class UserMemoryService {
    static let shared = UserMemoryService()
    
    enum MemoryType: String, Codable {
        case entityRelationship = "entity_relationship"
        case merchantCategory = "merchant_category"
        case preference = "preference"
        case fact = "fact"
        case pattern = "pattern"
    }
    
    enum MemorySource: String, Codable {
        case explicit = "explicit"
        case inferred = "inferred"
        case conversation = "conversation"
    }
    
    struct Memory: Codable, Identifiable {
        let id: UUID
        let memoryType: MemoryType
        let key: String
        let value: String
        let context: String?
        let confidence: Float
        let source: MemorySource
        let usageCount: Int
        let lastUsedAt: Date?
        let createdAt: Date
        let updatedAt: Date
    }
    
    @Published private(set) var memories: [Memory] = []
    private var lastLoadTime: Date?
    
    private init() {
        Task {
            await loadMemories()
        }
    }
    
    /// Get all memories formatted for LLM context
    func getMemoryContext() async -> String {
        await loadMemoriesIfNeeded()
        
        guard !memories.isEmpty else {
            return ""
        }
        
        var context = "\n=== USER MEMORY (Context to Remember) ===\n"
        context += "The following information has been learned about this user:\n\n"
        
        let grouped = Dictionary(grouping: memories) { $0.memoryType }
        
        for (type, items) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let typeName: String = {
                switch type {
                case .entityRelationship: return "Entity Relationships"
                case .merchantCategory: return "Merchant Categories"
                case .preference: return "Preferences"
                case .fact: return "Facts"
                case .pattern: return "Patterns"
                }
            }()
            
            context += "\(typeName):\n"
            for item in items.sorted(by: { $0.confidence > $1.confidence }) {
                switch type {
                case .entityRelationship:
                    context += "• \"\(item.key)\" = \(item.value)\n"
                    context += "  (When searching for '\(item.value)', also consider '\(item.key)')\n"
                case .merchantCategory:
                    context += "• Merchant \"\(item.key)\" is for: \(item.value)\n"
                case .preference:
                    context += "• \(item.key) = \(item.value)\n"
                case .fact:
                    context += "• \(item.key) = \(item.value)\n"
                case .pattern:
                    context += "• \(item.key) = \(item.value)\n"
                }

                if let ctx = item.context, !ctx.isEmpty {
                    context += "  (Context: \(ctx))\n"
                }
            }
            context += "\n"
        }
        
        return context
    }

    /// Expand a query using user memories
    /// Returns additional search terms based on memory relationships
    func expandQuery(_ query: String) async -> [String] {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("🧠 Query expansion: No user ID")
            return []
        }

        let lowercaseQuery = query.lowercased()
        var expansions: [String] = []

        // Use cached memories if available
        await loadMemoriesIfNeeded()

        print("🧠 Query expansion: Checking \(memories.count) memories for query: '\(query)'")
        print("🧠 Lowercase query: '\(lowercaseQuery)'")

        // Find memories where the query matches the VALUE (e.g., "haircut")
        // and return the KEYS (e.g., "jvmesmrvo", "JVM")
        for memory in memories where memory.confidence >= 0.5 {
            let value = memory.value.lowercased()
            let key = memory.key.lowercased()

            print("🧠 Checking memory: key='\(memory.key)', value='\(memory.value)', type='\(memory.memoryType.rawValue)', confidence=\(memory.confidence)")

            // If query mentions the value (e.g., "haircut"), add the key (e.g., "jvmesmrvo")
            if lowercaseQuery.contains(value) {
                print("🧠 Query contains value '\(value)'!")
                if !expansions.contains(key) {
                    expansions.append(key)
                    print("🧠 ✅ Query expansion: '\(value)' → '\(key)'")
                } else {
                    print("🧠 Already have '\(key)' in expansions")
                }
            }

            // Also work in reverse: if query mentions key, add value
            if lowercaseQuery.contains(key) {
                print("🧠 Query contains key '\(key)'!")
                if !expansions.contains(value) {
                    expansions.append(value)
                    print("🧠 ✅ Query expansion: '\(key)' → '\(value)'")
                } else {
                    print("🧠 Already have '\(value)' in expansions")
                }
            }
        }

        print("🧠 Query expansion result: \(expansions.count) expansions: \(expansions)")
        return expansions
    }

    /// FIX: Delete garbage memories and create correct one
    func fixHaircutMemory() async throws {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "UserMemoryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        let client = await SupabaseManager.shared.getPostgrestClient()

        // Delete garbage memories
        let garbageIds = [
            "a64ac661-c47c-49fc-b84c-cf65d0bb8a5c",
            "50112758-f360-4cda-95d0-1ace82a83b36",
            "22fec72c-797e-45a7-b177-fdbb4b62b99a",
            "a5e1a6d1-ed04-4ccc-ba6d-e3921183ad75"
        ]

        for id in garbageIds {
            try? await client
                .from("user_memory")
                .delete()
                .eq("id", value: id)
                .execute()
        }

        print("✅ Deleted garbage memories")

        // Create correct memories: both spelling variations → Haircut
        try await storeMemory(
            type: .entityRelationship,
            key: "jvmesmrvo",
            value: "Haircut",
            context: "Merchant name for haircut location (January spelling)",
            confidence: 0.9,
            source: .explicit
        )

        try await storeMemory(
            type: .entityRelationship,
            key: "jvmesmvrco",
            value: "Haircut",
            context: "Merchant name for haircut location (October spelling)",
            confidence: 0.9,
            source: .explicit
        )

        print("✅ Created correct memories: jvmesmrvo → Haircut, jvmesmvrco → Haircut")
    }

    /// Store or update a memory
    func storeMemory(
        type: MemoryType,
        key: String,
        value: String,
        context: String? = nil,
        confidence: Float = 0.5,
        source: MemorySource = .inferred
    ) async throws {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            throw NSError(domain: "UserMemoryService", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        let client = await SupabaseManager.shared.getPostgrestClient()
        
        // Build params using PostgREST.AnyJSON (the proper way for PostgREST)
        var params: [String: PostgREST.AnyJSON] = [
            "p_user_id": .string(userId.uuidString),
            "p_memory_type": .string(type.rawValue),
            "p_key": .string(key),
            "p_value": .string(value),
            "p_confidence": .double(Double(confidence)),
            "p_source": .string(source.rawValue)
        ]
        
        // Only include context if it's not nil
        if let context = context {
            params["p_context"] = .string(context)
        }
        
        let _ = try await client
            .rpc("upsert_user_memory", params: params)
            .execute()
        
        await loadMemories()
        print("✅ Stored memory: \(key) → \(value) (confidence: \(confidence))")
    }
    
    private func loadMemoriesIfNeeded() async {
        if let lastLoad = lastLoadTime,
           Date().timeIntervalSince(lastLoad) < 300 {
            return
        }
        await loadMemories()
    }
    
    private func loadMemories() async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return }
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response = try await client
                .from("user_memory")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("confidence", ascending: false)
                .order("usage_count", ascending: false)
                .execute()
            
            let decoder = JSONDecoder.supabaseDecoder()
            let data: [MemorySupabaseData] = try decoder.decode([MemorySupabaseData].self, from: response.data)
            
            self.memories = data.map { $0.toMemory() }
            self.lastLoadTime = Date()
            print("✅ Loaded \(memories.count) user memories")
        } catch {
            print("⚠️ Failed to load user memories: \(error)")
        }
    }
}

private struct MemorySupabaseData: Codable {
    let id: String
    let memory_type: String
    let key: String
    let value: String
    let context: String?
    let confidence: Float
    let source: String
    let usage_count: Int
    let last_used_at: String?
    let created_at: String
    let updated_at: String
    
    func toMemory() -> UserMemoryService.Memory {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return UserMemoryService.Memory(
            id: UUID(uuidString: id)!,
            memoryType: UserMemoryService.MemoryType(rawValue: memory_type) ?? .fact,
            key: key,
            value: value,
            context: context,
            confidence: confidence,
            source: UserMemoryService.MemorySource(rawValue: source) ?? .inferred,
            usageCount: usage_count,
            lastUsedAt: last_used_at.flatMap { iso.date(from: $0) },
            createdAt: iso.date(from: created_at) ?? Date(),
            updatedAt: iso.date(from: updated_at) ?? Date()
        )
    }
}
