# Seline Query Processing - Visual Architecture Flow

## Complete Message Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          USER INPUT IN CHAT                                  │
│                       "How much did I spend at                               │
│                      coffee shops last month?"                               │
└────────────────────────────────┬──────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SelineChat.sendMessage()                                  │
│                  (Seline/Services/SelineChat.swift)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. Add to conversation history                                              │
│ 2. Call buildSystemPrompt()                                                 │
│ 3. Build messages for API                                                   │
│ 4. Stream response from OpenAI                                              │
│ 5. Add assistant response to history                                        │
└────────────────────────────────┬──────────────────────────────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
    ┌──────────────────────────┐  ┌──────────────────────────┐
    │  CURRENT FLOW (Unused)   │  │   NEW FLOW (Ready)       │
    │   (Full Context)         │  │  (Filtered Context)      │
    ├──────────────────────────┤  ├──────────────────────────┤
    │ buildSystemPrompt()      │  │ 1. extractIntent()       │
    │  ↓                       │  │ 2. filterDataForQuery()  │
    │ SelineAppContext         │  │ 3. buildStructuredCtx()  │
    │  .buildContextPrompt()   │  │ 4. serializeToJSON()     │
    │  ↓                       │  │ 5. buildSpecialPrompt()  │
    │ [ALL DATA]               │  │  ↓                       │
    │ - 100+ events            │  │ [FILTERED DATA]          │
    │ - 50+ receipts           │  │ - 3-5 receipts           │
    │ - 50+ notes              │  │ - 0 notes                │
    │ - 200+ emails            │  │ - 0 events               │
    │ - 15+ locations          │  │ - 0 emails               │
    │                          │  │ - 0 locations            │
    │ 2000-4000 tokens         │  │                          │
    │                          │  │ 300-800 tokens           │
    └──────────────────────────┘  └──────────────────────────┘
                    │                         │
                    │                         │
                    └────────────┬────────────┘
                                 │
                                 ▼
    ┌──────────────────────────────────────────────────────┐
    │            Build System Prompt                       │
    │            (Generic or Specialized)                 │
    └──────────────────────────────────────────────────────┘
                                 │
                                 ▼
    ┌──────────────────────────────────────────────────────┐
    │            OpenAI API Call                           │
    │  model: gpt-4o-mini                                 │
    │  temperature: 0.7                                   │
    │  max_tokens: 800                                    │
    └──────────────────────────────────────────────────────┘
                                 │
                                 ▼
    ┌──────────────────────────────────────────────────────┐
    │            Stream Response                           │
    │  Chunk by chunk callback                            │
    └──────────────────────────────────────────────────────┘
                                 │
                                 ▼
    ┌──────────────────────────────────────────────────────┐
    │   Return Response to Caller                         │
    │   Add to Conversation History                       │
    │   Trigger UI Callbacks                              │
    └──────────────────────────────────────────────────────┘
```

---

## Intent Extraction Pipeline

```
┌──────────────────────────────────────────────────────────────┐
│  Query: "How much did I spend at coffee shops last month?"   │
└──────────────────────────────────┬───────────────────────────┘
                                   │
                                   ▼
        ┌──────────────────────────────────────────┐
        │  Step 1: Entity Extraction               │
        │  - Remove filler words                   │
        │  - Keep meaningful words > 2 chars       │
        └──────────────────────────────────────────┘
                     │
                     ▼
        ┌──────────────────────────────────────────┐
        │  Entities: ["coffee", "month", "shops",  │
        │            "spend"]                      │
        └──────────────────────────────────────────┘
                     │
           ┌─────────┼─────────┐
           │         │         │
           ▼         ▼         ▼
      ┌────────┐ ┌────────┐ ┌──────────┐
      │Step 2: │ │Step 3: │ │ Step 4:  │
      │ Date   │ │ Location│ │ Intent   │
      │Range   │ │ Filter  │ │ Classify │
      │        │ │        │ │          │
      │"month" │ │"coffee"│ │ Scoring  │
      │ ↓      │ │ ↓      │ │ ↓        │
      │"last   │ │Coffee: │ │expenses: │
      │ month" │ │ yes    │ │ 0.85     │
      │        │ │        │ │ (HIGH)   │
      └────────┘ └────────┘ └──────────┘
           │         │         │
           └─────────┼─────────┘
                     ▼
        ┌──────────────────────────────────────────┐
        │  Step 5: Sub-Intent Detection            │
        │  - Check for secondary intents           │
        │  - Multi-intent detection (if any)       │
        │  Result: None (single intent)            │
        └──────────────────────────────────────────┘
                     │
                     ▼
        ┌──────────────────────────────────────────┐
        │  IntentContext Created:                  │
        │  intent: .expenses                       │
        │  entities: ["coffee", "month",           │
        │           "shops", "spend"]              │
        │  dateRange: DateRange(start: Oct 1,      │
        │            end: Oct 31, period: .last)   │
        │  locationFilter:                         │
        │    LocationFilter(category: "coffee")    │
        │  confidence: 0.85                        │
        │  matchType: keyword_fuzzy                │
        └──────────────────────────────────────────┘
```

---

## Data Filtering Pipeline

```
┌──────────────────────────────────────────────────────────────┐
│  IntentContext from above                                    │
│  intent: .expenses                                           │
│  entities: ["coffee", "month", "shops", "spend"]            │
│  dateRange: October (last month)                            │
│  locationFilter: category: "coffee"                         │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────────┐
        │  DataFilter.filterDataForQuery()          │
        │  (LLMArchitecture/DataFilter.swift)      │
        │                                           │
        │  Switch on intent.intent = .expenses     │
        └───────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────────┐
        │  Call ReceiptFilter.filterReceipts()      │
        │  (LLMArchitecture/ReceiptFilter.swift)   │
        └───────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
    ┌─────────┐      ┌──────────┐      ┌────────────┐
    │Get All  │      │Filter by │      │Merchant    │
    │Receipts │      │Date Range│      │Intelligence│
    │(50 total)│     │October   │      │Lookup      │
    │        │      │(15 match) │      │           │
    │        │      │        │      │(Coffee     │
    │        │      │        │      │ Shops id.) │
    └─────────┘      └──────────┘      └────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            ▼
        ┌───────────────────────────────────────────┐
        │  Match Receipts Against Entities          │
        │  - "Espresso Joe's" contains "coffee" ✓   │
        │  - "Brew Haven" category = coffee ✓       │
        │  - "Starbucks" merchant type = coffee ✓   │
        │  - "Taco Bell" ✗ (not coffee)            │
        │  Scoring:                                 │
        │  - Keyword match: +2.0                    │
        │  - Merchant intelligence: +1.5            │
        │  - Category match: +3.0                   │
        └───────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────────┐
        │  Amount Range Detection                   │
        │  - Entities have no $ amounts             │
        │  - No amount filtering                    │
        └───────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────────┐
        │  Calculate Statistics                     │
        │  Total: $87.50 (10 receipts)              │
        │  Average: $8.75                           │
        │  High: $15.00                             │
        │  Low: $4.50                               │
        │  Categories: [Coffee: $87.50 (100%)]     │
        └───────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────────┐
        │  FilteredContext Returned:                │
        │  ├── receipts: [ReceiptWithRelevance]    │
        │  │   10 receipts with scores & types     │
        │  ├── notes: nil                          │
        │  ├── locations: nil                      │
        │  ├── tasks: nil                          │
        │  ├── emails: nil                         │
        │  ├── receiptStatistics: (totals, etc)    │
        │  └── metadata:                           │
        │      ├── queryIntent: "expenses"         │
        │      ├── dateRangeQueried: "lastMonth"   │
        │      └── currentWeather: nil             │
        └───────────────────────────────────────────┘
```

---

## Context Builder Pipeline

```
┌──────────────────────────────────────────────────────────────┐
│  FilteredContext (10 receipts, rest nil)                     │
│  conversationHistory: [previous messages...]                 │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────────┐
        │  ContextBuilder.buildStructuredContext()  │
        │  (LLMArchitecture/ContextBuilder.swift)   │
        └───────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
    ┌─────────┐      ┌──────────┐      ┌─────────────┐
    │Build    │      │Build     │      │Analyze      │
    │Metadata │      │Context   │      │Follow-up    │
    │         │      │Data      │      │Context      │
    │- intent │      │- receipts│      │             │
    │- date   │      │  JSON    │      │- Is follow- │
    │- timezone│     │- summary │      │  up: NO     │
    │- weather│     │- stats   │      │- Previous   │
    │         │      │         │      │  topic: nil │
    └─────────┘      └──────────┘      └─────────────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            ▼
        ┌───────────────────────────────────────────┐
        │  Build Conversation History JSON          │
        │  - User: "How much at coffee shops..."    │
        │  - Assistant: "Previous response..."      │
        │  - User: "Last month?"                    │
        └───────────────────────────────────────────┘
                            │
                            ▼
        ┌───────────────────────────────────────────┐
        │  StructuredLLMContext Created:            │
        │  ├── metadata: {                          │
        │  │     intent: "expenses",                │
        │  │     dateRangeQueried: "lastMonth",     │
        │  │     temporalContext: { ... }           │
        │  │   }                                    │
        │  ├── context: {                           │
        │  │     receipts: [                        │
        │  │       {                                │
        │  │         id: "uuid1",                   │
        │  │         merchant: "Espresso Joe's",    │
        │  │         amount: 8.50,                  │
        │  │         date: "2025-10-15",            │
        │  │         category: "Coffee",            │
        │  │         relevanceScore: 0.95,          │
        │  │         matchType: "category_match",   │
        │  │         merchantType: "Coffee Shop",   │
        │  │         merchantProducts: ["Coffee",   │
        │  │           "Pastries", "Drinks"]        │
        │  │       },                               │
        │  │       ... (9 more receipts)            │
        │  │     ],                                 │
        │  │     receiptSummary: {                  │
        │  │       totalAmount: 87.50,              │
        │  │       totalCount: 10,                  │
        │  │       averageAmount: 8.75,             │
        │  │       byCategory: [                    │
        │  │         {category: "Coffee",           │
        │  │          total: 87.50,                 │
        │  │          count: 10,                    │
        │  │          percentage: 100}              │
        │  │       ]                                │
        │  │     }                                  │
        │  │   }                                    │
        │  └── conversationHistory: [...]           │
        │  }                                        │
        └───────────────────────────────────────────┘
```

---

## Relevance Scoring Examples

### Receipt Relevance Scoring Breakdown

```
Receipt: "Espresso Joe's - October 15, 2025 - $8.50"

Scoring:
────────────────────────────────────────────────────
Action                              Score    Total
────────────────────────────────────────────────────
Date range match (Oct ✓)           +5.0     = 5.0
Keyword: "coffee" in "Joe's"        +2.0     = 7.0
Merchant intelligence match         +1.5     = 8.5
Category: Coffee                    +3.0     = 11.5
─────────────────────────────────────────────────
Relevance Score = min(11.5/5.0, 1.0) = 1.0 (MAX)
────────────────────────────────────────────────────
```

### Note Relevance Scoring Breakdown

```
Query: "Find notes about coffee"
Note: "Coffee Tips and Tricks"

Scoring:
────────────────────────────────────────────────────
Action                              Score    Total
────────────────────────────────────────────────────
Title contains "coffee"             +5.0     = 5.0
Content has coffee keyword          +2.0     = 7.0
─────────────────────────────────────────────────
Relevance Score = min(7.0/10.0, 1.0) = 0.70
────────────────────────────────────────────────────
```

---

## Intent Classification Confidence Matrix

```
Query                           Calendar  Email  Notes  Location  Expenses  Confidence
─────────────────────────────────────────────────────────────────────────────────────
"What's on my schedule?"         HIGH      LOW    LOW    LOW       LOW       Calendar
                                 0.95      0.1    0.0    0.0       0.0       ✓ CALENDAR

"Email from John"                LOW       HIGH   LOW    LOW       LOW       Email
                                 0.1       0.95   0.05   0.0       0.0       ✓ EMAIL

"Spent at coffee this month"     LOW       LOW    LOW    MED       HIGH      Expenses
                                 0.05      0.1    0.1    0.45      0.85      ✓ EXPENSES

"Find notes about Python"        LOW       LOW    HIGH   LOW       LOW       Notes
                                 0.0       0.05   0.95   0.0       0.0       ✓ NOTES

"Coffee shops nearby Toronto"    LOW       LOW    LOW    HIGH      LOW       Location
                                 0.05      0.0    0.0    0.90      0.1       ✓ LOCATION

"When am I free and what's       HIGH      LOW    LOW    LOW       LOW       Calendar
my budget this month?"           0.85      0.1    0.0    0.0       0.70      ✓ MULTI
                                                                              (Calendar +
                                                                               Expenses)
```

---

## Token Count Comparison

```
Query: "How much did I spend at coffee shops last month?"

┌─────────────────────────────────────────────────────────────┐
│ CURRENT APPROACH (Full Context)                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ System Prompt (generic):              ~100 tokens          │
│ All Events (100+):                    ~800 tokens          │
│ All Receipts (50+):                   ~600 tokens          │
│ All Notes (50+):                      ~400 tokens          │
│ All Emails (200+):                    ~1200 tokens         │
│ All Locations (15+):                  ~200 tokens          │
│ Conversation history (2 msgs):        ~100 tokens          │
│ User query:                           ~20 tokens           │
│                                                             │
│ TOTAL:                                ~3420 tokens         │
└─────────────────────────────────────────────────────────────┘
                            vs
┌─────────────────────────────────────────────────────────────┐
│ NEW APPROACH (Filtered Context)                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ System Prompt (specialized):          ~150 tokens          │
│ Filtered Receipts (10):               ~300 tokens          │
│ Receipt Summary:                      ~100 tokens          │
│ Conversation history (2 msgs):        ~100 tokens          │
│ User query:                           ~20 tokens           │
│                                                             │
│ TOTAL:                                ~670 tokens          │
└─────────────────────────────────────────────────────────────┘

SAVINGS: 3420 - 670 = 2750 tokens (80% reduction!)
```

---

## Query Processing Decision Tree

```
                     User Query Received
                            │
                            ▼
                   Extract Intent & Entities
                   ├─ Keywords detected
                   ├─ Date range parsed
                   ├─ Location filters found
                   └─ Confidence scored
                            │
                ┌───────────┬┴┬───────────┐
                │           │ │           │
                ▼           ▼ ▼           ▼
            Calendar?    Email?  Notes?  Location?  Expenses?
              (HIGH)      (HIGH)  (HIGH)   (HIGH)     (HIGH)
                │           │      │        │          │
                │           │      │        │          │
         YES ───┴─┬─────┬───┴───┬──┴───┬────┴─── YES
                   │     │       │      │
                   │     │       │      └─ Filter Receipts
                   │     │       │         ├─ Date range
                   │     │       │         ├─ Keyword match
                   │     │       │         ├─ Merchant intel
                   │     │       │         └─ Amount range
                   │     │       │
                   │     │       └─ Filter Notes
                   │     │           ├─ Title match
                   │     │           ├─ Content match
                   │     │           └─ Date range
                   │     │
                   │     └─ Filter Emails
                   │         ├─ Sender match
                   │         ├─ Subject match
                   │         ├─ Body match
                   │         ├─ Date range
                   │         └─ Importance
                   │
                   └─ Filter Tasks
                       ├─ Date range (required)
                       ├─ Title match
                       └─ Category match
                            │
                            ▼
                    Build Filtered Context
                    ├─ Relevance scores
                    ├─ Match types
                    ├─ Rank by relevance
                    └─ Include summaries
                            │
                            ▼
                    Build Structured JSON
                    ├─ Metadata
                    ├─ Context data
                    ├─ Conversation history
                    └─ Follow-up analysis
                            │
                            ▼
                    Send to LLM with
                    Specialized Prompt
                            │
                            ▼
                    Stream Response
                    & Add to History
```

---

## Integration Roadmap

```
PHASE 1: Foundation (Now) ✓
├─ IntentExtractor created and working
├─ DataFilter logic implemented
├─ ReceiptFilter with merchant intelligence
└─ ContextBuilder ready to use

PHASE 2: Integration (To Do)
├─ Modify SelineChat.sendMessage()
├─ Call IntentExtractor in message flow
├─ Call DataFilter with intent
├─ Replace buildContextPrompt() with filtered version
└─ Test with sample queries

PHASE 3: Optimization (To Do)
├─ Add confidence-based fallback
├─ Implement caching of intent results
├─ Specialized prompts for high-confidence queries
├─ A/B testing: full vs. filtered context
└─ Performance monitoring

PHASE 4: Enhancement (To Do)
├─ ML-based intent refinement
├─ Learning from user corrections
├─ Cross-intent relationship detection
├─ Temporal pattern learning
└─ User preference personalization
```

