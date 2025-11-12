import Foundation

// MARK: - Search Answer with Related Items

struct SearchAnswer {
    let text: String                        // The answer text (from LLM or computed)
    let relatedReceipts: [ReceiptStat]      // Receipts mentioned in the answer
    let relatedNotes: [Note]                // Notes mentioned in the answer
    let relatedEvents: [Any] = []           // Events mentioned (if available)
    let relatedEmails: [Any] = []           // Emails mentioned (if available)
    let relatedLocations: [Any] = []        // Locations mentioned (if available)

    var hasRelatedItems: Bool {
        return !relatedReceipts.isEmpty || !relatedNotes.isEmpty ||
               !relatedEvents.isEmpty || !relatedEmails.isEmpty || !relatedLocations.isEmpty
    }

    var relatedItemsCount: Int {
        return relatedReceipts.count + relatedNotes.count +
               relatedEvents.count + relatedEmails.count + relatedLocations.count
    }
}

// MARK: - Item Search Result

struct ItemSearchResult {
    let receiptID: UUID
    let receiptDate: Date
    let merchant: String
    let matchedProduct: String?  // The product that was matched (if found)
    let amount: Double
    let confidence: Double  // 1.0 = exact match, 0.7-0.9 = fuzzy match, 0.5 = merchant only

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: receiptDate)
    }
}

// MARK: - Expense Query Type Detection

enum ExpenseQueryType {
    case lookup         // "When did I last buy X?" → Return most recent
    case countUnique    // "How many different X places?" → Count unique merchants
    case listAll        // "Show all X", "List X purchases" → Return all results
    case sumAmount      // "How much did I spend on X?" → Sum amounts
    case frequency      // "How often did I buy X?" → Count total occurrences
}

// MARK: - Expense Intent Extraction Result

struct ExpenseIntent {
    let productName: String         // What product/item is being searched for
    let queryType: ExpenseQueryType // What type of query (lookup, list, sum, etc)
    let dateFilter: String?         // Optional date constraint (e.g., "this month", "last week")
    let merchantFilter: String?     // Optional merchant constraint
    let confidence: Double          // 0.0-1.0 confidence in extraction
}

// MARK: - Item Search Service

class ItemSearchService {
    static let shared = ItemSearchService()

    private init() {}

    // NOTE: Query type detection is now handled by LLM in OpenAIService.extractExpenseIntent()
    // This replaces the old hardcoded logic for better natural language understanding

    // MARK: - Main Search Method

    /// Search receipts for a specific product/item
    /// Returns the most recent receipt containing the product
    /// - Parameters:
    ///   - productName: The product to search for (e.g., "zonnic", "coffee", "pizza")
    ///   - receipts: Array of ReceiptStat to search through
    ///   - notes: Dictionary mapping noteId to Note (for accessing receipt content)
    /// - Returns: ItemSearchResult if found, nil otherwise
    func searchReceiptItems(
        for productName: String,
        in receipts: [ReceiptStat],
        notes: [UUID: Note]
    ) -> ItemSearchResult? {
        let lowerProductName = productName.lowercased()

        // Sort receipts by date DESCENDING (newest first)
        let sortedReceipts = receipts.sorted { $0.date > $1.date }

        print("🔎 ItemSearch: Looking for '\(productName)' across \(sortedReceipts.count) receipts (newest first)")

        // Iterate and search for product
        for (index, receipt) in sortedReceipts.enumerated() {
            // Get the original note to access full content
            guard let note = notes[receipt.noteId] else {
                // If note not found, at least check the title
                if receipt.title.lowercased().contains(lowerProductName) {
                    print("   📌 Match #\(index + 1): Title match - '\(receipt.title)' on \(receipt.date)")
                    return ItemSearchResult(
                        receiptID: receipt.id,
                        receiptDate: receipt.date,
                        merchant: receipt.title,
                        matchedProduct: productName,
                        amount: receipt.amount,
                        confidence: 0.8  // Lower confidence for merchant-only match
                    )
                }
                continue
            }

            // Check for exact match in receipt content (highest confidence)
            if note.content.lowercased().contains(lowerProductName) {
                print("   ✓ Match #\(index + 1): Content match - '\(receipt.title)' on \(receipt.date)")
                return ItemSearchResult(
                    receiptID: receipt.id,
                    receiptDate: receipt.date,
                    merchant: receipt.title,
                    matchedProduct: productName,
                    amount: receipt.amount,
                    confidence: 1.0  // Exact match in receipt content
                )
            }

            // Check for fuzzy match in receipt content
            let fuzzyMatch = findFuzzyMatch(lowerProductName, in: note.content.lowercased())
            if let matchedText = fuzzyMatch {
                print("   ≈ Match #\(index + 1): Fuzzy match - '\(matchedText)' in '\(receipt.title)' on \(receipt.date)")
                return ItemSearchResult(
                    receiptID: receipt.id,
                    receiptDate: receipt.date,
                    merchant: receipt.title,
                    matchedProduct: matchedText,
                    amount: receipt.amount,
                    confidence: 0.85  // Fuzzy match
                )
            }

            // Check if merchant name contains the product (lower confidence)
            if receipt.title.lowercased().contains(lowerProductName) {
                print("   📌 Match #\(index + 1): Merchant match - '\(receipt.title)' on \(receipt.date)")
                return ItemSearchResult(
                    receiptID: receipt.id,
                    receiptDate: receipt.date,
                    merchant: receipt.title,
                    matchedProduct: productName,
                    amount: receipt.amount,
                    confidence: 0.7  // Merchant match only
                )
            }
        }

        print("❌ No matches found for '\(productName)' across any receipt contents")
        return nil
    }

    /// Search for all receipts containing a product
    /// - Parameters:
    ///   - productName: The product to search for
    ///   - receipts: Array of ReceiptStat to search through
    ///   - notes: Dictionary mapping noteId to Note
    /// - Returns: Array of ItemSearchResult sorted by date (most recent first)
    func searchAllReceiptsForProduct(
        _ productName: String,
        in receipts: [ReceiptStat],
        notes: [UUID: Note]
    ) -> [ItemSearchResult] {
        let lowerProductName = productName.lowercased()
        var results: [ItemSearchResult] = []

        // Sort receipts by date DESCENDING (newest first)
        let sortedReceipts = receipts.sorted { $0.date > $1.date }

        for receipt in sortedReceipts {
            guard let note = notes[receipt.noteId] else {
                // If note not found, check the title
                if receipt.title.lowercased().contains(lowerProductName) {
                    results.append(ItemSearchResult(
                        receiptID: receipt.id,
                        receiptDate: receipt.date,
                        merchant: receipt.title,
                        matchedProduct: productName,
                        amount: receipt.amount,
                        confidence: 0.7
                    ))
                }
                continue
            }

            // Check for exact match in receipt content
            if note.content.lowercased().contains(lowerProductName) {
                results.append(ItemSearchResult(
                    receiptID: receipt.id,
                    receiptDate: receipt.date,
                    merchant: receipt.title,
                    matchedProduct: productName,
                    amount: receipt.amount,
                    confidence: 1.0
                ))
                continue
            }

            // Check for fuzzy match
            if let matchedText = findFuzzyMatch(lowerProductName, in: note.content.lowercased()) {
                results.append(ItemSearchResult(
                    receiptID: receipt.id,
                    receiptDate: receipt.date,
                    merchant: receipt.title,
                    matchedProduct: matchedText,
                    amount: receipt.amount,
                    confidence: 0.85
                ))
                continue
            }

            // Check merchant name
            if receipt.title.lowercased().contains(lowerProductName) {
                results.append(ItemSearchResult(
                    receiptID: receipt.id,
                    receiptDate: receipt.date,
                    merchant: receipt.title,
                    matchedProduct: productName,
                    amount: receipt.amount,
                    confidence: 0.7
                ))
            }
        }

        return results
    }

    // MARK: - Aggregation Methods

    /// Get receipts grouped by merchant/location
    /// Used for "How many different pizza places?" queries
    func groupReceiptsByMerchant(for receipts: [ItemSearchResult]) -> [String: [ItemSearchResult]] {
        var grouped: [String: [ItemSearchResult]] = [:]

        for receipt in receipts {
            let merchant = receipt.merchant
            if grouped[merchant] == nil {
                grouped[merchant] = []
            }
            grouped[merchant]?.append(receipt)
        }

        return grouped
    }

    /// Sum total amount spent on a product
    func sumAmount(for receipts: [ItemSearchResult]) -> Double {
        return receipts.reduce(0) { $0 + $1.amount }
    }

    /// Count total occurrences
    func countOccurrences(for receipts: [ItemSearchResult]) -> Int {
        return receipts.count
    }

    /// Get unique merchant count
    func countUniqueMerchants(for receipts: [ItemSearchResult]) -> Int {
        return Set(receipts.map { $0.merchant }).count
    }

    // MARK: - Search Answer Creation

    /// Create a SearchAnswer from ItemSearchResults (converts to full ReceiptStat objects)
    func createSearchAnswer(
        text: String,
        for itemResults: [ItemSearchResult],
        receipts: [ReceiptStat],
        notes: [Note]
    ) -> SearchAnswer {
        // Find the actual ReceiptStat objects that match our search results
        let relatedReceiptIDs = Set(itemResults.map { $0.receiptID })
        let relatedReceipts = receipts.filter { relatedReceiptIDs.contains($0.id) }

        // Find the notes that correspond to these receipts
        let receiptNoteIDs = Set(relatedReceipts.map { $0.noteId })
        let relatedNotes = notes.filter { receiptNoteIDs.contains($0.id) }

        return SearchAnswer(
            text: text,
            relatedReceipts: relatedReceipts,
            relatedNotes: relatedNotes
        )
    }

    /// Create a simple SearchAnswer with just text (no related items)
    func createSimpleAnswer(text: String) -> SearchAnswer {
        return SearchAnswer(
            text: text,
            relatedReceipts: [],
            relatedNotes: []
        )
    }

    // MARK: - Helper Methods

    /// Find fuzzy match using Levenshtein distance
    /// Returns the matched text if found within threshold
    private func findFuzzyMatch(_ searchTerm: String, in text: String) -> String? {
        let words = text.split(separator: " ").map(String.init)

        for word in words {
            let distance = levenshteinDistance(searchTerm, word.lowercased())
            // Allow up to 2 character differences for fuzzy matching
            if distance <= 2 && distance > 0 {
                return word
            }
        }

        return nil
    }

    /// Levenshtein distance algorithm for fuzzy matching
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Chars = Array(s1)
        let s2Chars = Array(s2)
        let m = s1Chars.count
        let n = s2Chars.count

        // Create a matrix
        var matrix = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        // Initialize first row and column
        for i in 0...m {
            matrix[i][0] = i
        }
        for j in 0...n {
            matrix[0][j] = j
        }

        // Fill the matrix
        for i in 1...m {
            for j in 1...n {
                if s1Chars[i - 1] == s2Chars[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = 1 + min(
                        matrix[i - 1][j],      // deletion
                        matrix[i][j - 1],      // insertion
                        matrix[i - 1][j - 1]   // substitution
                    )
                }
            }
        }

        return matrix[m][n]
    }

    // MARK: - Product Name Extraction

    // NOTE: Product name extraction is now handled by LLM in OpenAIService.extractExpenseIntent()
    // This replaces the old hardcoded regex/verb-based extraction for much better natural language understanding
    // The LLM can now handle complex queries like:
    // - "Can you show all the pizza receipts?" → extracts "pizza" correctly
    // - "When did I last buy zonnic?" → extracts "zonnic" correctly
    // - "How many different coffee places?" → extracts "coffee" correctly
    // No more hardcoded filler word lists or regex patterns!
}
