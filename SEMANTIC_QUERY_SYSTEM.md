# Universal Semantic Query Engine

## Overview

A foundational query system that replaces rigid intent types with flexible semantic intent description. Works across **all app data types** (receipts, emails, events, notes, locations), not just expenses.

## Architecture

### Core Components

#### 1. **SemanticQuery** (SemanticQuery.swift)
Describes exactly what data transformation is needed:

```swift
struct SemanticQuery {
    let intent: QueryIntent              // What user wants (search, compare, analyze, explore, track, summarize, predict)
    let dataSources: [DataSource]        // Where to look (receipts, emails, events, notes, locations, calendar)
    let filters: [AnyFilter]             // How to constrain (date_range, category, text_search, status, amount_range, merchant)
    let operations: [AnyOperation]       // What to compute (aggregate, comparison, search, trend_analysis)
    let presentation: PresentationRules  // How to display (format, items, summary level)
    let confidence: Double               // LLM confidence in extraction
}
```

#### 2. **UniversalQueryExecutor** (UniversalQueryExecutor.swift)
Executes semantic queries:
- Fetches from data sources (TaskManager, NotesManager, EmailService, LocationsManager)
- Applies filters (date, category, text, status, amount, merchant)
- Executes operations (aggregate by category, compare time periods, analyze trends)
- Returns structured QueryResult

#### 3. **UniversalResponseFormatter** (UniversalResponseFormatter.swift)
Intelligently formats results:
- Generates natural language responses
- **Smart decision**: Don't show receipt cards for aggregate/comparison queries
- Provides follow-up suggestions based on intent

#### 4. **OpenAIService.generateSemanticQuery()** (OpenAIService.swift)
LLM-based semantic extraction:
- GPT-4o-mini parses natural language into semantic structure
- Provides reasoning for interpretation
- Returns structured query plan with high confidence

### Integration into Conversation Flow

**SearchService.processWithSemanticQuery()** → **SearchService.addConversationMessage()**

Flow:
1. User enters query → `addConversationMessage()`
2. Try semantic query first: `processWithSemanticQuery()`
   - Generate semantic query from LLM
   - Execute with UniversalQueryExecutor
   - Format with UniversalResponseFormatter
   - Convert to RelatedDataItem for UI
3. If confidence > 0.5, use semantic result immediately
4. Otherwise, fall back to traditional OpenAI conversation

## Example: Comparison Query

**User Query**: "Compare Nov and Oct 2025 for all categories"

### Before (Broken)
- ❌ Forced into `sumAmount` type
- ❌ Ignored date filter
- ❌ Always showed receipt cards
- ❌ Wrong totals, wrong cards

### After (Fixed)
```json
{
  "intent": "compare",
  "dataSources": [{"type": "receipts"}],
  "filters": [{
    "type": "date_range",
    "parameters": {
      "startDate": "2025-10-01",
      "endDate": "2025-11-30"
    }
  }],
  "operations": [
    {
      "type": "comparison",
      "dimension": "time",
      "slices": ["October 2025", "November 2025"],
      "metric": "total"
    },
    {
      "type": "aggregate",
      "groupBy": "category"
    }
  ],
  "presentation": {
    "format": "table",
    "includeIndividualItems": false  // ← NO CARDS!
  }
}
```

**Result**:
✅ Accurate comparison table by category
✅ Zero receipt cards shown
✅ Correct totals for both months

## Supported Intent Types

| Intent | Example Queries |
|--------|-----------------|
| `search` | "Find emails from John last week", "Show notes about project X" |
| `compare` | "Compare Nov vs Oct", "Food vs shopping spending" |
| `analyze` | "Which merchant do I use most?", "Spending trend" |
| `explore` | "Show recent emails", "What locations have I saved?" |
| `track` | "What events are pending?", "Incomplete tasks" |
| `summarize` | "Monthly recap", "Overview of last week" |
| `predict` | "When will I hit budget?", "Next purchase likely" |

## Data Sources

| Source | Access Point | Properties |
|--------|--------------|-----------|
| Receipts | NotesManager (Receipts folder) | date, amount, merchant, category |
| Emails | EmailService | folder, sender, subject, body, timestamp |
| Events | TaskManager | title, date, status (upcoming/completed) |
| Notes | NotesManager | title, content, folder, created date |
| Locations | LocationsManager | name, category, rating, favorited |
| Calendar | TaskManager | calendar events as events |

## Filter Types

- **DateRangeFilter**: `startDate`, `endDate`, `labels`
- **CategoryFilter**: `categories`, `excludeCategories`
- **TextSearchFilter**: `query`, `fields`, `fuzzyMatch`
- **StatusFilter**: `status` (read, unread, completed, pending, etc)
- **AmountRangeFilter**: `minAmount`, `maxAmount`
- **MerchantFilter**: `merchants`, `fuzzyMatch`

## Operation Types

### AggregateOperation
Group and compute metrics:
```swift
type: sum|count|average|min|max
groupBy: category|merchant|date|status
```

### ComparisonOperation
Compare across dimensions:
```swift
dimension: time|category|merchant
slices: ["Oct", "Nov"]
metric: total|count|average
```

### SearchOperation
Find items:
```swift
query: "search term"
rankBy: relevance|date|amount
limit: 10
```

### TrendAnalysisOperation
Analyze over time:
```swift
metric: spending|frequency
timeGranularity: daily|weekly|monthly|yearly
```

## Smart Presentation Rules

**Automatically hides receipt cards when**:
- Intent is `compare` → Show comparison table only
- Intent is `analyze` → Show analysis/summary only
- Intent is `summarize` → Show overview only
- Intent is `predict` → Show forecast only

**Shows receipt cards when**:
- Intent is `search` AND result set < 20 items
- Intent is `explore` AND result set < 20 items
- Intent is `track` AND result set < 20 items

## Adding New Data Types

To add documents or contacts:

```swift
// 1. Add to DataSource enum
case documents(folder: String?)

// 2. Add UniversalItem case
case document(Document)

// 3. Fetch in QueryExecutor
case .documents(let folder):
    let docs = DocumentsManager.shared.documents
    allItems.append(contentsOf: docs.map { UniversalItem.document($0) })

// 4. Add to RelatedDataItem.DataType
case document

// That's it! Filters, operations, and formatter work automatically.
```

## Extensibility

The system is composable and extensible:

- **New filters**: Implement `FilterProtocol`
- **New operations**: Implement `OperationProtocol`
- **New data types**: Add to `DataSource`, `UniversalItem`, `RelatedDataItem.DataType`
- **Custom presentations**: Modify `PresentationRules` and `UniversalResponseFormatter`

## Testing

To test the system:

```swift
// Generate semantic query
let query = await OpenAIService.shared.generateSemanticQuery(
    from: "Compare Nov vs Oct 2025 for all categories"
)

// Execute
let result = await UniversalQueryExecutor.shared.execute(query)

// Format
let formatted = UniversalResponseFormatter.shared.format(result, rules: query.presentation)

// Result: formatted.text contains comparison table, formatted.items is empty
```

## Debugging

Enable debug logging by checking console output:

```
🧠 Semantic Query Generated:
   Intent: compare
   Sources: 1
   Filters: 1
   Operations: 2
   Confidence: 95%

📊 Semantic Query Executed:
   Intent: compare
   Sources: 1
   Filtered items: 35
   Aggregations: 0
   Confidence: 95%

📝 Response Formatted:
   Format: table
   Items to show: 0
   Suggestions: 2
```

## Future Enhancements

1. **Multi-source queries**: Combine data from receipts + emails + locations
2. **Custom aggregations**: Allow user-defined aggregate functions
3. **Prediction operations**: Forecast next month's spending
4. **Visualization suggestions**: Auto-recommend charts/graphs
5. **Context awareness**: Remember previous query context for follow-ups
6. **Reasoning explanations**: Show why semantic query chose specific operations
