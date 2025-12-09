import Foundation

/// Merchant intelligence service - web search + local cache
/// Identifies what each merchant is (pizzeria, coffee shop, etc)
/// Caches results locally to avoid repeated web searches
@MainActor
class MerchantIntelligenceLayer {
    static let shared = MerchantIntelligenceLayer()

    // MARK: - Types

    struct MerchantInfo: Codable {
        let name: String  // Original merchant name
        let type: String  // "Pizzeria", "Coffee Shop", "Italian Restaurant", etc
        let products: [String]  // ["pizza", "drinks"], ["coffee", "pastry"], etc
        let cachedDate: Date  // When this was last looked up
    }

    // MARK: - Properties

    private let cacheKey = "MerchantIntelligenceCache"
    private var cache: [String: MerchantInfo] = [:]

    // MARK: - Initialization

    private init() {
        loadCache()
    }

    // MARK: - Main API

    /// Get merchant information - uses local cache first, web search as fallback
    func getMerchantInfo(_ merchantName: String) async -> MerchantInfo {
        let key = merchantName.lowercased()

        // Check local cache first
        if let cached = cache[key] {
            // Cache is fresh enough (don't re-lookup same merchant every query)
            return cached
        }

        // Not in cache - web search for it
        let info = await webSearchMerchantType(merchantName)

        // Cache the result
        cache[key] = info
        saveCache()

        return info
    }

    /// Get merchant type for multiple merchants
    func getMerchantTypes(_ merchants: [String]) async -> [String: MerchantInfo] {
        var results: [String: MerchantInfo] = [:]

        for merchant in merchants {
            let info = await getMerchantInfo(merchant)
            results[merchant] = info
        }

        return results
    }

    // MARK: - Web Search

    /// Use LLM to identify merchant type via web search
    private func webSearchMerchantType(_ merchant: String) async -> MerchantInfo {
        let prompt = """
        What type of business/restaurant is "\(merchant)"?
        What products or services do they primarily offer?

        Be specific. Examples:
        - "Pizza Hut" → Type: "Pizza Chain", Products: ["pizza", "wings", "drinks"]
        - "The Brew Cafe" → Type: "Coffee Shop", Products: ["coffee", "pastry", "tea"]
        - "Giovanni's" → Type: "Italian Pizzeria", Products: ["pizza", "pasta", "drinks"]
        - "Whole Foods" → Type: "Grocery Store", Products: ["groceries", "deli", "bakery"]

        Respond in JSON: {"type": "...", "products": ["...", "..."]}
        """

        do {
            let response = try await DeepSeekService.shared.generateText(
                systemPrompt: "You are a business expert. Identify what type of business this is and what they sell.",
                userPrompt: prompt,
                maxTokens: 150,
                temperature: 0.0
            )

            // Parse JSON response
            if let data = response.data(using: String.Encoding.utf8),
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String,
               let products = json["products"] as? [String] {
                return MerchantInfo(
                    name: merchant,
                    type: type,
                    products: products.map { $0.lowercased() },
                    cachedDate: Date()
                )
            }
        } catch {
            print("❌ Error searching merchant '\(merchant)': \(error)")
        }

        // Fallback if parsing fails
        return MerchantInfo(
            name: merchant,
            type: "Unknown Business",
            products: [],
            cachedDate: Date()
        )
    }

    // MARK: - Caching

    private func saveCache() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(cache)
            UserDefaults.standard.set(data, forKey: cacheKey)
        } catch {
            print("❌ Error saving merchant cache: \(error)")
        }
    }

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            cache = [:]
            return
        }

        do {
            let decoder = JSONDecoder()
            cache = try decoder.decode([String: MerchantInfo].self, from: data)
        } catch {
            print("❌ Error loading merchant cache: \(error)")
            cache = [:]
        }
    }

    /// Clear cache (useful for testing or forcing refresh)
    func clearCache() {
        cache = [:]
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }

    // MARK: - Utility

    /// Check if a merchant type suggests they sell a certain product
    func likelyToSell(_ merchant: MerchantInfo, product: String) -> Bool {
        let lowerProduct = product.lowercased()

        // Check if product is in the merchant's product list
        if merchant.products.contains(lowerProduct) {
            return true
        }

        // Check if product is mentioned in merchant type
        if merchant.type.lowercased().contains(lowerProduct) {
            return true
        }

        // Semantic matching for common patterns
        let type = merchant.type.lowercased()
        let products = merchant.products.map { $0.lowercased() }

        // Pizza patterns
        if lowerProduct.contains("pizza") {
            return type.contains("pizza") || type.contains("italian") ||
                   type.contains("pizzeria") || type.contains("grill") ||
                   type.contains("pub") || type.contains("restaurant") &&
                   !type.contains("sushi") && !type.contains("chinese")
        }

        // Coffee patterns
        if lowerProduct.contains("coffee") {
            return type.contains("cafe") || type.contains("coffee") ||
                   products.contains("coffee")
        }

        return false
    }

    /// Get cache stats for debugging
    func getCacheStats() -> (count: Int, merchants: [String]) {
        let merchants = Array(cache.keys).sorted()
        return (count: cache.count, merchants: merchants)
    }
}
