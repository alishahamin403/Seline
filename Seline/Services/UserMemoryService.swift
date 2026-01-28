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
                    context += "• \(item.key) → \(item.value)\n"
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
