# Seline Query Processing Architecture - Complete Analysis

## Overview
The Seline application uses a sophisticated multi-layer query processing system that intelligently filters context data based on user intent before sending to the LLM. The system combines keyword-based intent detection with semantic understanding and specialized data filtering.

---

## 1. MAIN ENTRY POINT: SelineChat.sendMessage()

**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/SelineChat.swift`

```swift
func sendMessage(_ userMessage: String, streaming: Bool = true) async -> String
```

### Flow:
1. **Add user message to history** (line 44-46)
   - Creates `ChatMessage` with timestamp
   - Triggers `onMessageAdded` callback

2. **Build system prompt** (line 51)
   - Calls `buildSystemPrompt()` → Fetches comprehensive context via `SelineAppContext`
   - Includes ALL app data without pre-filtering

3. **Build messages for API** (line 54)
   - Formats conversation history into OpenAI API format

4. **Stream or get response** (line 58-61)
   - `getStreamingResponse()` or `getNonStreamingResponse()`
   - Both use `OpenAIService.simpleChatCompletion()`

5. **Add assistant response** (line 65-67)
   - Stores response and triggers callback

### Current Design:
- **Simple approach**: Send comprehensive context, let LLM understand intent
- **No active filtering yet**: All data passed to system prompt
- **Architecture comment** (lines 3-13): Explicitly states "Let the LLM be smart"

---

## 2. INTENT EXTRACTION LAYER

**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/LLMArchitecture/IntentExtractor.swift`

### Purpose:
Extract user intent and context to enable smart filtering

### Main Function:
```swift
func extractIntent(from query: String) -> IntentContext
```

### Intent Types:
```swift
enum ChatIntent: String {
    case calendar
    case notes
    case locations
    case weather
    case email
    case navigation
    case expenses
    case multi          // Combines multiple intents
    case general        // Generic conversation
}
```

### IntentContext Structure (lines 17-32):
```swift
struct IntentContext {
    let intent: ChatIntent              // Primary intent
    let subIntents: [ChatIntent]        // Multi-intent queries
    let entities: [String]              // Extracted keywords
    let dateRange: DateRange?           // Temporal filter
    let locationFilter: LocationFilter? // Geographic filter
    let confidence: Double              // 0.0 - 1.0
    let matchType: MatchType            // How detected
}
```

### Extraction Pipeline:

#### Step 1: Entity Extraction (lines 118-135)
- Removes filler words (the, a, an, what, when, where, etc.)
- Extracts meaningful keywords (>2 chars)
- Returns unique, sorted entities

**Example:** "What did I spend at coffee shops this month?"
→ entities: ["coffee", "month", "shops", "spend"]

#### Step 2: Date Range Detection (lines 140-197)
Detects temporal patterns:
- "today" → Today
- "tomorrow" → Tomorrow
- "this week" → This Week
- "next week" → Next Week
- "this month" → This Month
- "last month" → Last Month
- "this year" → This Year
- Custom date ranges

Returns: `DateRange(start, end, period)`

#### Step 3: Location Filter Detection (lines 202-245)
Detects geographic mentions:
- Cities: toronto, vancouver, new york, etc.
- Countries: canada, usa, uk, france, etc.
- Categories: cafe, restaurant, coffee, gym, bank, etc.

Returns: `LocationFilter(city, province, country, category, minRating)`

#### Step 4: Intent Classification (lines 250-316)
Keyword-based scoring for each intent type:

```
Calendar Keywords: ["calendar", "schedule", "event", "meeting", "when", ...]
Notes Keywords:    ["note", "notes", "remind", "remember", "memo", ...]
Location Keywords: ["location", "place", "where", "near", "restaurant", ...]
Weather Keywords:  ["weather", "rain", "snow", "temperature", ...]
Email Keywords:    ["email", "message", "inbox", "from", ...]
Navigation Keywords: ["how far", "how long", "distance", "drive", ...]
Expenses Keywords: ["expense", "spend", "spending", "cost", "receipt", ...]
```

**Scoring:** `scoreMatch()` counts keyword matches, normalizes to 0-1

**Confidence:** If top score > 0.3, use it; otherwise fallback to `.general`

#### Step 5: Sub-Intent Detection (lines 335-369)
For multi-intent queries, detects secondary intents with 0.3 threshold

---

## 3. DATA FILTERING LAYER

**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/LLMArchitecture/DataFilter.swift`

### Purpose:
Filter and rank data based on detected intent

### Main Function:
```swift
func filterDataForQuery(
    intent: IntentContext,
    notes: [Note],
    locations: [SavedPlace],
    tasks: [TaskItem],
    emails: [Email],
    receipts: [ReceiptStat],
    weather: WeatherData?
) async -> FilteredContext
```

### Returns: FilteredContext
```swift
struct FilteredContext {
    let notes: [NoteWithRelevance]?
    let locations: [SavedPlaceWithRelevance]?
    let tasks: [TaskItemWithRelevance]?
    let emails: [EmailWithRelevance]?
    let receipts: [ReceiptWithRelevance]?
    let receiptStatistics: ReceiptStatistics?
    let weather: WeatherData?
    let metadata: ContextMetadata
}
```

Each item includes:
- `relevanceScore` (0.0 - 1.0)
- `matchType` (exact, keyword, date, category, etc.)
- Match-specific data (snippets, distance, importance indicators)

### Filtering Strategy by Intent (lines 114-176):

#### Notes Filtering (lines 206-266)
**Scoring logic:**
- Title exact match: +10.0
- Title contains entity: +5.0
- Content contains entity: +2.0 (+ extracts snippet)
- Date range match: +1.5

**Result:** Top 8 by relevance score

**Example:** Query "coffee notes"
- "Coffee Tips" → Score: 10 (title exact)
- "Morning coffee ritual" → Score: 5 (title contains)
- "Had coffee at cafe" → Score: 2 (content match)

#### Tasks/Calendar Filtering (lines 271-328)
**Scoring logic:**
- Date range match: +5.0 (required if date range specified)
- Title contains entity: +3.0
- Description contains entity: +1.5

**Important:** Tasks outside requested date range are skipped entirely

**Result:** All matching tasks sorted by date, then relevance

#### Locations Filtering (lines 333-440)
**Scoring logic:**
- Country match: +5.0
- City match: +4.0
- Province match: +3.0
- Category match: +3.0
- Entity match (name): +3.0
- Entity match (category): +2.0
- Rating boost: +0.5 per rating point

**Geographic constraints:** If location filter specified but doesn't match, skip
**Result:** Top 8 by relevance

#### Email Filtering (lines 445-524)
**Scoring logic:**
- Date range match: +3.0
- Sender match: +4.0
- Subject match: +3.0
- Body match: +2.0
- Importance keywords: +1.0 each ("urgent", "critical", "deadline", etc.)
- Important flag: +0.5

**Result:** Top 10 sorted by relevance, then date (recent first)

#### Receipts/Expenses Filtering (see ReceiptFilter.swift below)

#### Multi-Intent Filtering (lines 146-167)
For queries matching multiple intents:
- Filter all relevant data types
- Include all results for LLM to discover relationships

#### General Intent Filtering (lines 170-174)
Sample approach:
- Notes: prefix(2)
- Locations: prefix(2)
- Tasks: prefix(2)
- Emails: prefix(2)

---

## 4. SPECIALIZED RECEIPT FILTERING

**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/LLMArchitecture/ReceiptFilter.swift`

### Purpose:
Intelligent receipt filtering with merchant intelligence

### Main Function:
```swift
func filterReceiptsForQuery(
    intent: IntentContext,
    receipts: [ReceiptStat]
) async -> [ReceiptWithRelevance]
```

### Filtering Logic (lines 60-126):

#### 1. Merchant Intelligence Lookup (lines 43-57)
- Fetches merchant types (e.g., "Pizzeria", "Coffee Shop")
- Identifies products sold
- Uses `MerchantIntelligenceLayer.shared`

#### 2. Date Range Filtering (lines 60-68)
Required if date range specified; receipts outside range are skipped

#### 3. Category Filtering (lines 71-78)
Matches receipt category against location filter category

#### 4. Merchant Matching (lines 81-100)
- Keyword match in merchant name: +2.0
- Semantic match via merchant intelligence: +1.5
  - Example: "pizza" → Pizzeria → +1.5 semantic boost

#### 5. Amount Range Detection (lines 103-113)
Pattern detection in entities:
- "over $50" → min: $50, max: $1,000,000
- "under $100" → min: $0, max: $100
- "between $20 and $50" → min: $20, max: $50

#### 6. Statistics Calculation (lines 185-221)
Computes:
- Total amount
- Count
- Average
- Highest/lowest
- Breakdown by category with percentages

**Returns:** Top N sorted by date (most recent first)

---

## 5. CONTEXT AGGREGATION LAYER

**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/LLMArchitecture/ContextBuilder.swift`

### Purpose:
Build structured context from filtered data

### Main Function:
```swift
func buildStructuredContext(
    from filteredContext: FilteredContext,
    conversationHistory: [ConversationMessage]
) -> StructuredLLMContext
```

### Output Structure:
```swift
struct StructuredLLMContext {
    let metadata: ContextMetadata
    let context: ContextData
    let conversationHistory: [ConversationMessageJSON]
}
```

### Metadata Includes (lines 9-31):
- timestamp (ISO8601)
- currentWeather
- userTimezone
- intent (from filter)
- dateRangeQueried
- temporalContext (start/end dates, period type)
- followUpContext (is follow-up, previous topic, previous timeframe, related queries)

### Context Data Includes:
- NoteJSON (id, title, excerpt, relevance score, match type)
- LocationJSON (id, name, category, location, rating, relevance, match type, distance)
- TaskJSON (id, title, scheduled time, duration, completed status, relevance, match type)
- EmailJSON (id, from, subject, timestamp, read status, excerpt, relevance, match type, importance)
- ReceiptJSON (id, merchant, amount, date, category, relevance, match type, merchantType, merchantProducts)
- ReceiptSummaryJSON (totals, averages, breakdown by category)

### Temporal Context Analysis (lines 362-383):
Extracts and normalizes date range information from filter

### Follow-up Context Analysis (lines 449-491):
- Detects if query is follow-up (>1 user message in history)
- Extracts previous topic
- Extracts related queries
- Detects previous timeframe

---

## 6. CURRENT STATE: SelineAppContext

**File:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/SelineAppContext.swift`

### What SelineChat.buildSystemPrompt() Does (lines 89-117):
```swift
private func buildSystemPrompt() async -> String {
    let contextPrompt = await appContext.buildContextPrompt()
    
    return """
    You are Seline, a personal AI assistant...
    [System instructions]
    USER DATA CONTEXT:
    \(contextPrompt)
    """
}
```

### What SelineAppContext.buildContextPrompt() Does (lines 169-752):

**Current approach:** Comprehensive data dump with NO intent-based filtering

1. **Refreshes all data** (line 171)
   - Events from TaskManager
   - Custom email folders
   - Receipts from notes
   - Notes
   - Emails
   - Locations

2. **Organizes events** by temporal proximity (lines 210-421):
   - TODAY (sorted by time)
   - TOMORROW (sorted by time)
   - THIS WEEK (days 3-7)
   - UPCOMING (future beyond week)
   - RECURRING EVENTS SUMMARY (monthly/yearly stats)
   - LAST WEEK
   - OLDER PAST EVENTS (last 5 shown)

3. **Groups receipts by month** (lines 426-475):
   - Current month first
   - Previous months by recency
   - Shows top 7 months
   - Includes category breakdown

4. **Organizes emails by folders** (lines 478-675):
   - Standard folders (Inbox, Sent, Drafts, etc.)
   - Custom email folders
   - Shows up to 20 per folder
   - Includes full content, metadata, attachments

5. **Organizes notes by folder** (lines 678-735):
   - Excludes Receipts folder
   - Shows up to 15 per folder (most recent first)
   - Includes full content (up to 1000 lines)

6. **Lists locations** (lines 738-749):
   - Shows up to 15 saved places with ratings

---

## 7. WHERE TO ADD INTELLIGENT FILTERING

The system has the pieces in place but needs integration:

### Current Unused Components:
1. **IntentExtractor** - Ready but not called in main chat flow
2. **DataFilter** - Ready but not called in main chat flow
3. **ContextBuilder** - Ready but not called in main chat flow
4. **SpecializedPromptBuilder** - Ready for specialized prompts

### Integration Point:

Current flow:
```
sendMessage() 
  → buildSystemPrompt() 
    → SelineAppContext.buildContextPrompt() 
      → [ALL data, no filtering]
    → [Full context + instructions]
  → OpenAI API
```

**Needed flow:**
```
sendMessage()
  → extractIntent(query)              [NEW]
  → filterData(intent)                [NEW]
  → buildStructuredContext()          [NEW]
  → buildSpecializedPrompt()          [NEW]
  → [Filtered context + specialized instructions]
  → OpenAI API
```

---

## 8. INTELLIGENT FILTERING STRATEGY

### What Gets Filtered Based on Intent:

#### Expense Query: "How much did I spend at coffee shops last month?"
- **Intent detected:** expenses, location: "coffee"
- **Date range:** "last month"
- **Filtering applied:**
  - Receipts: Only last month, coffee-related merchants
  - Locations: Coffee shops only
  - Notes: Skip (not expense-related)
  - Emails: Skip (not expense-related)
  - Tasks: Skip (not expense-related)
- **Result:** ~10-15 receipts instead of all 50+

#### Calendar Query: "What do I have scheduled this week?"
- **Intent detected:** calendar
- **Date range:** "this week"
- **Filtering applied:**
  - Tasks: Only this week
  - Receipts: Skip
  - Emails: Skip
  - Notes: Skip
  - Locations: Skip
- **Result:** 3-5 events instead of all 100+

#### Email Query: "Did I get an email from John about the project?"
- **Intent detected:** email
- **Entities:** ["john", "project"]
- **Filtering applied:**
  - Emails: Search sender "john" + subject/body "project"
  - Tasks: Skip
  - Receipts: Skip
  - Notes: Skip
  - Locations: Skip
- **Result:** 2-3 relevant emails instead of 200+

#### Notes Query: "What was that note about Python?"
- **Intent detected:** notes
- **Entities:** ["python"]
- **Filtering applied:**
  - Notes: Title or content contains "python"
  - Emails: Skip
  - Tasks: Skip
  - Receipts: Skip
  - Locations: Skip
- **Result:** 1-2 notes instead of 50+

#### Multi-Intent Query: "What's my budget for coffee this month and when is my next coffee meeting?"
- **Intent detected:** expenses + calendar
- **Sub-intents:** [expenses, calendar]
- **Filtering applied:**
  - Expenses: Coffee receipts this month
  - Calendar: Events this month with "coffee"
  - Other data: Skip
- **Result:** ~5 receipts + ~2 events instead of all data

---

## 9. KEY FILTERING METRICS

### Date Range Impact:
- **Without date filtering:** All 300+ historical items sent
- **With date filtering:** 1-20 items per query

### Intent-based Reduction:
| Query Type | All Data | Filtered | Reduction |
|-----------|----------|----------|-----------|
| Calendar | 100+ events | 3-10 | 90%+ |
| Expenses | 50+ receipts | 5-15 | 70%+ |
| Email | 200+ emails | 2-10 | 90%+ |
| Notes | 50+ notes | 1-5 | 90%+ |

### Context Token Savings:
- Full context: 2000-4000 tokens
- Filtered context: 300-800 tokens
- **Reduction:** 60-90%

---

## 10. IMPLEMENTATION CHECKLIST

To activate intelligent filtering in SelineChat:

- [ ] **Step 1:** Call `IntentExtractor.shared.extractIntent(from: userMessage)`
- [ ] **Step 2:** Call `DataFilter.shared.filterDataForQuery(intent:...)`
- [ ] **Step 3:** Call `ContextBuilder.shared.buildStructuredContext(from:conversationHistory:)`
- [ ] **Step 4:** Serialize to JSON: `ContextBuilder.shared.serializeToJSON()`
- [ ] **Step 5:** Use `SpecializedPromptBuilder` for specialized prompts
- [ ] **Step 6:** Send filtered context instead of full context to LLM

### Simple Integration Example:
```swift
func sendMessage(_ userMessage: String, streaming: Bool = true) async -> String {
    let userMsg = ChatMessage(role: .user, content: userMessage, timestamp: Date())
    conversationHistory.append(userMsg)
    onMessageAdded?(userMsg)
    
    // NEW: Extract intent
    let intentContext = IntentExtractor.shared.extractIntent(from: userMessage)
    
    // NEW: Filter data
    let filteredContext = await DataFilter.shared.filterDataForQuery(
        intent: intentContext,
        notes: await appContext.notes,
        locations: await appContext.locations,
        tasks: await appContext.events,
        emails: await appContext.emails,
        receipts: await appContext.receipts,
        weather: nil
    )
    
    // NEW: Build structured context
    let structuredContext = ContextBuilder.shared.buildStructuredContext(
        from: filteredContext,
        conversationHistory: conversationHistory
    )
    
    // NEW: Use filtered context in prompt
    let contextJSON = ContextBuilder.shared.serializeToJSON(structuredContext)
    let systemPrompt = buildSystemPromptWithContext(contextJSON)
    
    // Rest of existing code...
}
```

---

## 11. ENTITY/KEYWORD MATCHING KEYWORDS

### By Intent Type:

**Calendar/Events:**
calendar, schedule, event, meeting, when, appointment, busy, free, available

**Notes:**
note, notes, remind, remember, memo, write, document

**Locations:**
location, place, where, near, nearby, address, visit, restaurant, cafe, coffee, store

**Weather:**
weather, rain, snow, temperature, cold, hot, sunny, cloudy, forecast

**Email:**
email, message, inbox, from, sender, subject

**Navigation:**
how far, how long, distance, travel time, eta, drive, hours away

**Expenses:**
expense, spend, spending, cost, receipt, money, budget, amount, price

**Date Patterns:**
today, tomorrow, this week, next week, this month, last month, this year, past 30 days

---

## 12. CONFIDENCE THRESHOLDS

```
Exact keyword match:     > 0.95  → keyword_exact
Fuzzy keyword match:     > 0.75  → keyword_fuzzy
Pattern detected:        > 0.30  → pattern_detected
Below threshold:         ≤ 0.30  → Fallback to general
```

---

## Summary

Seline has a sophisticated, production-ready query processing pipeline with:
- Intent detection with confidence scoring
- Multi-layer filtering (entity, date range, location)
- Specialized handling for receipts/expenses
- Relevance scoring and ranking
- Merchant intelligence integration
- Temporal context awareness
- Follow-up context detection

The system is currently **disabled** in the main chat flow but can be activated by integrating it into `SelineChat.sendMessage()` to replace the current full-context approach with intelligent, filtered context delivery.

