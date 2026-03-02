import Foundation

private struct JournalHeaderSummaryCacheEntry: Codable {
    let fingerprint: String
    let summary: String
    let updatedAt: Date
}

enum JournalHeaderSummaryCache {
    private static let storageKey = "journal.header.summary.cache.v1"
    private static let maxEntries = 250
    private static let defaults = UserDefaults.standard

    static func summary(for noteId: UUID, text: String) -> String? {
        let key = cacheKey(for: noteId)
        let expectedFingerprint = fingerprint(for: text)

        guard let entry = loadCache()[key], entry.fingerprint == expectedFingerprint else {
            return nil
        }

        let cleanedSummary = entry.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanedSummary.isEmpty ? nil : cleanedSummary
    }

    static func store(_ summary: String, for noteId: UUID, text: String) {
        let cleanedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedSummary.isEmpty else { return }

        var cache = loadCache()
        cache[cacheKey(for: noteId)] = JournalHeaderSummaryCacheEntry(
            fingerprint: fingerprint(for: text),
            summary: cleanedSummary,
            updatedAt: Date()
        )
        saveCache(prunedCache(from: cache))
    }

    private static func fingerprint(for text: String) -> String {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedText.count):\(HashUtils.deterministicHash(normalizedText))"
    }

    private static func cacheKey(for noteId: UUID) -> String {
        noteId.uuidString.lowercased()
    }

    private static func loadCache() -> [String: JournalHeaderSummaryCacheEntry] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: JournalHeaderSummaryCacheEntry].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveCache(_ cache: [String: JournalHeaderSummaryCacheEntry]) {
        guard let encoded = try? JSONEncoder().encode(cache) else { return }
        defaults.set(encoded, forKey: storageKey)
    }

    private static func prunedCache(from cache: [String: JournalHeaderSummaryCacheEntry]) -> [String: JournalHeaderSummaryCacheEntry] {
        guard cache.count > maxEntries else { return cache }

        let newestEntries = cache
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .prefix(maxEntries)

        return Dictionary(uniqueKeysWithValues: newestEntries.map { ($0.key, $0.value) })
    }
}
