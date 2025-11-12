# Receipt Search and Display Flow Analysis

## 1. HOW RECEIPTS ARE FETCHED WHEN USER ASKS A QUESTION

### Entry Point: `ConversationSearchView.swift` (lines 215-224)
- User types message and taps send button
- Calls `SearchService.shared.addConversationMessage(query)`

### Main Processing: `SearchService.addConversationMessage()` (lines 417-613)
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/SearchService.swift`

Flow:
1. Validates and trims the message
2. Calls `OpenAIService.shared.answerQuestion()` or `answerQuestionWithStreaming()`
3. Passes `conversationHistory` for context

### Receipt Extraction: `OpenAIService.swift` (lines 3580-3700)
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/OpenAIService.swift`

**Two-Tier Search Strategy:**

#### TIER 1: LLM-Based Intelligent Search (lines 3585-3643)
1. Detects expense queries using keywords/verbs
2. Calls `extractExpenseIntent()` to understand what user is asking for
3. Uses `ItemSearchService.shared.searchAllReceiptsForProduct()` to find receipts
4. Returns specialized formatted response based on query type (lookup, list, sum, count, frequency)

**Query Types Extracted:**
- `lookup` - "When did I last buy X?"
- `listAll` - "Show all X purchases"
- `sumAmount` - "How much did I spend on X?"
- `countUnique` - "How many different X places?"
- `frequency` - "How often did I buy X?"

#### TIER 2: Fallback Full Context Analysis (lines 3645-3700)
- If TIER 1 fails, falls back to full context analysis
- LLM analyzes entire conversation context

---

## 2. HOW RECEIPTS ARE PASSED TO LLM FOR PROCESSING

### A. Receipt Search Function
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/ItemSearchService.swift`

#### Primary Function: `searchAllReceiptsForProduct()` (lines 162-241)
```swift
func searchAllReceiptsForProduct(
    _ productName: String,
    in receipts: [ReceiptStat],
    notes: [UUID: Note]
) -> [ItemSearchResult]
```

**How it works:**
1. Takes product name, array of ReceiptStat, and notes dictionary
2. Sorts receipts by date (newest first)
3. Searches for product using 4-level matching strategy:
   - **Level 1:** Exact match in receipt content (confidence: 1.0)
   - **Level 2:** Fuzzy match using Levenshtein distance (confidence: 0.85)
   - **Level 3:** Merchant name contains product (confidence: 0.7)
   - **Level 4:** Title match if note not found (confidence: 0.7)
4. Returns array of `ItemSearchResult` with confidence scores

**Logging:** Heavy debug logging shows all matches with confidence levels

### B. Intent Extraction Function
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/OpenAIService.swift`

#### Function: `extractExpenseIntent()` (lines 5050-5144)
```swift
func extractExpenseIntent(from query: String) async -> ExpenseIntent?
```

**How it works:**
1. Sends query to GPT-4o-mini with structured prompt
2. Extracts:
   - `productName` - what the user is searching for
   - `queryType` - enum: lookup/listAll/countUnique/sumAmount/frequency
   - `dateFilter` - optional date constraint
   - `merchantFilter` - optional merchant filter
   - `confidence` - 0.0-1.0 confidence score
3. Returns `ExpenseIntent` struct for downstream processing

### C. Response Formatting With Items
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/OpenAIService.swift`

Functions that format responses AND package receipts:
- `formatLookupResponseWithItems()` (line 5148) - Single most recent purchase
- `formatListAllResponseWithItems()` (line 5246) - All matching receipts
- `formatSumResponseWithItems()` (line 5284) - Total amount spent
- `formatCountUniqueResponseWithItems()` (line 5186) - Unique merchants count
- `formatFrequencyResponseWithItems()` (line 5319) - How many times purchased

**Each function:**
1. Generates response text for LLM
2. Calls `ItemSearchService.shared.createSearchAnswer()` to package receipts
3. Stores result in `OpenAIService.shared.lastSearchAnswer`

---

## 3. HOW RECEIPT CARDS ARE RENDERED/DISPLAYED

### Flow: OpenAIService → SearchService → UI

#### Step 1: Store SearchAnswer in OpenAIService
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/OpenAIService.swift`

```swift
@Published var lastSearchAnswer: SearchAnswer?
```

All formatting functions set: `self.lastSearchAnswer = answer`

`SearchAnswer` struct contains:
```swift
struct SearchAnswer {
    let text: String                      // LLM response text
    let relatedReceipts: [ReceiptStat]    // Receipts to display
    let relatedNotes: [Note]
    // ... other related data
}
```

#### Step 2: Extract RelatedData in SearchService
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/SearchService.swift` (lines 512-532)

After LLM response, `addConversationMessage()`:
1. Checks `OpenAIService.shared.lastSearchAnswer`
2. Converts `ReceiptStat` objects to `RelatedDataItem` objects
3. Builds array of receipt items:
```swift
for receipt in searchAnswer.relatedReceipts {
    items.append(RelatedDataItem(
        id: receipt.id,
        type: .receipt,                  // Type enum
        title: receipt.title,            // Receipt title
        subtitle: receipt.category,      // Category
        date: receipt.date,              // Date
        amount: receipt.amount,          // Amount spent
        merchant: receipt.title          // Merchant name
    ))
}
```

4. Attaches to `ConversationMessage`:
```swift
let finalMsg = ConversationMessage(
    id: streamingMessageID,
    isUser: false,
    text: response,
    relatedData: relatedData,           // Receipt array attached here
    timeStarted: thinkStartTime,
    timeFinished: Date()
)
```

#### Step 3: Render in UI
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/Components/ConversationSearchView.swift`

**In ConversationMessageView (lines 273-357):**
```swift
if !message.isUser, let relatedData = message.relatedData {
    let receipts = relatedData.filter { $0.type == .receipt }
    if !receipts.isEmpty {
        ForEach(receipts) { receipt in
            ReceiptCardView(
                merchant: receipt.merchant ?? receipt.title,
                date: receipt.date,
                amount: receipt.amount,
                colorScheme: colorScheme
            )
        }
    }
}
```

**Receipt Card Component: ReceiptCardView (lines 361-434)**
Displays:
- Receipt icon (blue circle with receipt symbol)
- Merchant name
- Date (formatted as medium date style)
- Amount (formatted as "$X.XX")
- Styled with rounded corners and subtle border

---

## 4. WHERE DEDUPLICATION HAPPENS

### Location 1: In Receipt Fetching
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/OpenAIService.swift` (lines 4251-4256)

```swift
// Fetch receipts (deduplicate IDs first to avoid duplicates)
if let receiptIds = relevantItemIds.receiptIds, !receiptIds.isEmpty {
    let uniqueIds = Array(Set(receiptIds))  // Remove duplicates
    print("📦 Fetch: LLM selected \(receiptIds.count) receipt IDs (\(uniqueIds.count) unique)")
    receipts = notesManager.notes.filter { uniqueIds.contains($0.id) }
}
```

**What:** Converts array of receipt IDs to Set to remove duplicates
**When:** Before filtering `notesManager.notes`

### Location 2: In Topic Extraction
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/ConversationContextService.swift` (line 147)

```swift
return Array(Set(topics))  // Remove duplicates
```

### Location 3: Search Results Deduplication
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/ItemSearchService.swift` (lines 285-287)

```swift
// Find the actual ReceiptStat objects that match our search results
let relatedReceiptIDs = Set(itemResults.map { $0.receiptID })
let relatedReceipts = receipts.filter { relatedReceiptIDs.contains($0.id) }
```

**What:** Converts item result IDs to Set, ensuring each receipt appears once in relatedReceipts

---

## Key Models and Structures

### ConversationMessage
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Models/ConversationModels.swift`

```swift
struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let text: String
    let timestamp: Date
    let relatedData: [RelatedDataItem]?  // ← Contains receipts
    let timeStarted: Date?
    let timeFinished: Date?
}
```

### RelatedDataItem
```swift
struct RelatedDataItem: Identifiable, Codable {
    let id: UUID
    let type: DataType  // .receipt, .event, .note, .location
    let title: String
    let subtitle: String?
    let date: Date?
    let amount: Double?      // ← For receipts
    let merchant: String?    // ← For receipts
}
```

### SearchAnswer (Used Internally)
**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/ItemSearchService.swift`

```swift
struct SearchAnswer {
    let text: String
    let relatedReceipts: [ReceiptStat]
    let relatedNotes: [Note]
}
```

### ItemSearchResult
```swift
struct ItemSearchResult {
    let receiptID: UUID
    let receiptDate: Date
    let merchant: String
    let matchedProduct: String?
    let amount: Double
    let confidence: Double  // 1.0 = exact, 0.85 = fuzzy, 0.7 = merchant only
}
```

---

## Summary of Data Flow

```
User Question
    ↓
SearchService.addConversationMessage()
    ↓
OpenAIService.answerQuestion() / answerQuestionWithStreaming()
    ├─ Detect if expense query
    ├─ TIER 1: Extract intent with LLM
    ├─ Call ItemSearchService.searchAllReceiptsForProduct()
    │  └─ Returns [ItemSearchResult] with confidence scores
    ├─ Format response and create SearchAnswer
    └─ Store in OpenAIService.lastSearchAnswer
    ↓
SearchService receives response
    ├─ Extracts OpenAIService.lastSearchAnswer
    ├─ Converts ReceiptStat → RelatedDataItem
    └─ Attaches relatedData to ConversationMessage
    ↓
UI Renders ConversationMessageView
    ├─ Renders text response
    └─ Renders ReceiptCardView for each related receipt
        ├─ Merchant name
        ├─ Date
        └─ Amount
```

---

## Where Deduplication Should Happen (Recommendations)

Based on the code analysis, receipt deduplication currently happens at:
1. **Receipt ID level** (fetchFullDataForIds) - ensures unique receipt IDs
2. **Search results level** (createSearchAnswer) - ensures each receipt ID appears once
3. **RelatedDataItem conversion** - inherits deduplication from above

However, **potential issue**: If the same receipt ID is returned multiple times from `searchAllReceiptsForProduct()` due to multiple matching patterns, it might appear multiple times in the final display. 

**Recommended fix location**: In `ConversationMessageView` before rendering ReceiptCardView, deduplicate by receipt ID:
```swift
let receipts = relatedData.filter { $0.type == .receipt }
let uniqueReceipts = Dictionary(grouping: receipts, by: { $0.id })
    .values.compactMap { $0.first }
ForEach(uniqueReceipts) { receipt in ... }
```

