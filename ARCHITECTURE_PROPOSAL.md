# Scalable Context Retrieval Architecture

## Problem Statement
Current system breaks down when user has 1000+ receipts/visits/notes:
- Vector search hard-limited to 50 items
- No aggregation or summarization
- All data sent as raw text (expensive + slow)
- Semantic queries miss most data

## Solution: 3-Tier Intelligent Retrieval System

### Tier 1: Query Intent Classification

**Classify queries into 4 types:**

1. **AGGREGATE** - Needs totals/counts, not individual items
   - "How much did I spend on haircuts?"
   - "How many times did I visit the gym?"
   - "What's my average receipt total?"

2. **COMPLETE** - Needs ALL items (but can summarize)
   - "Show me all haircuts"
   - "List all receipts from Starbucks"
   - "Every visit to the gym"

3. **SAMPLE** - Needs representative examples
   - "Show me some receipts"
   - "Recent haircuts"
   - "A few gym visits"

4. **DATE_SPECIFIC** - Needs complete data for a time range
   - "What did I do yesterday?"
   - "Receipts from last week"
   - "Visits in January"

### Tier 2: Retrieval Strategy (Per Query Type)

#### AGGREGATE Queries
**Strategy:** Database-level aggregation, return summary only

```swift
// Example: "How much did I spend on haircuts?"
1. Use query expansion: "haircuts" → ["jvmesmrvo", "jvmesmvrco", "haircut"]
2. Filter receipts by expanded terms (database-level)
3. Aggregate: SUM(amount), COUNT(*), GROUP BY month
4. Return: "43 receipts, $1,247 total, breakdown by month"
5. Token cost: ~100 tokens vs 12,900 tokens for full data
```

**Implementation:**
- New function: `aggregateReceipts(matching: [String]) -> AggregateResult`
- Returns: total, count, avg, min, max, by_month, by_category
- NO individual receipts sent to LLM

#### COMPLETE Queries
**Strategy:** Structured filtering + tiered summarization

```swift
// Example: "Show me all haircuts"
1. Use query expansion to get all variants
2. Database filter: WHERE content MATCHES ANY(variants)
3. If results < 50: Send full content
4. If results 50-200: Send condensed (title, date, amount only)
5. If results > 200: Send summary + top 20 detailed + counts by month
```

**Context Format:**
```
HAIRCUTS (143 total, $2,156 spent):

Summary by Year:
- 2025: 72 visits, $1,080 avg $15/visit
- 2024: 71 visits, $1,076 avg $15.15/visit

Most Recent (detailed):
1. Jan 2026: jvmesmrvo - $18
2. Dec 2025: jvmesmrvo - $15
... (top 20 only)

All Visits (condensed):
- Jan 2026: jvmesmrvo $18
- Oct 2025: jvmesmvrco $15
... (all 143, condensed format)
```

Token cost: ~3,000 tokens vs 42,900 for full content

#### SAMPLE Queries
**Strategy:** Vector search with smart sampling

```swift
// Example: "Show me some receipts"
1. Use current vector search (top 50 by relevance)
2. No changes needed - this works well
```

#### DATE_SPECIFIC Queries
**Strategy:** Complete data for date range (current approach works)

```swift
// Example: "What did I do yesterday?"
1. Fetch ALL visits/receipts/events for that date
2. Send complete data (usually <100 items per day)
3. No changes needed - current approach is correct
```

### Tier 3: Database Optimization Layer

**Add new Supabase functions for efficient retrieval:**

1. **Structured Filtering** (before vector search)
```sql
-- Function: filter_receipts_by_terms
-- Returns: All receipts matching ANY term (no embedding needed)
CREATE FUNCTION filter_receipts_by_terms(
  p_user_id UUID,
  p_terms TEXT[],
  p_date_start TIMESTAMP DEFAULT NULL,
  p_date_end TIMESTAMP DEFAULT NULL
) RETURNS TABLE(...) AS $$
  SELECT * FROM embeddings
  WHERE user_id = p_user_id
    AND document_type = 'receipt'
    AND (title ILIKE ANY(p_terms) OR content ILIKE ANY(p_terms))
    AND (p_date_start IS NULL OR created_at >= p_date_start)
    AND (p_date_end IS NULL OR created_at < p_date_end)
  ORDER BY created_at DESC;
$$;
```

2. **Aggregation Functions**
```sql
-- Function: aggregate_receipts
-- Returns: Summary stats without individual rows
CREATE FUNCTION aggregate_receipts(
  p_user_id UUID,
  p_terms TEXT[],
  p_date_start TIMESTAMP DEFAULT NULL,
  p_date_end TIMESTAMP DEFAULT NULL
) RETURNS JSON AS $$
  SELECT json_build_object(
    'total_amount', COALESCE(SUM((metadata->>'amount')::NUMERIC), 0),
    'count', COUNT(*),
    'avg_amount', COALESCE(AVG((metadata->>'amount')::NUMERIC), 0),
    'min_amount', MIN((metadata->>'amount')::NUMERIC),
    'max_amount', MAX((metadata->>'amount')::NUMERIC),
    'by_month', json_agg(DISTINCT metadata->>'month_year'),
    'by_category', json_object_agg(
      metadata->>'category',
      COUNT(*)
    )
  )
  FROM embeddings
  WHERE user_id = p_user_id
    AND document_type = 'receipt'
    AND (title ILIKE ANY(p_terms) OR content ILIKE ANY(p_terms))
    AND (p_date_start IS NULL OR created_at >= p_date_start)
    AND (p_date_end IS NULL OR created_at < p_date_end);
$$;
```

3. **Hybrid Search** (combine structured filter + vector ranking)
```sql
-- Function: hybrid_search
-- First filter by terms, THEN rank by vector similarity
-- This ensures we get ALL matches, not just top-50
CREATE FUNCTION hybrid_search(
  p_user_id UUID,
  p_query_embedding VECTOR(1536),
  p_terms TEXT[],
  p_similarity_threshold FLOAT DEFAULT 0.2,
  p_limit INT DEFAULT 1000  -- Much higher limit
) RETURNS TABLE(...) AS $$
  SELECT *,
    1 - (embedding <=> p_query_embedding) as similarity
  FROM embeddings
  WHERE user_id = p_user_id
    AND (title ILIKE ANY(p_terms) OR content ILIKE ANY(p_terms))
    AND (1 - (embedding <=> p_query_embedding)) > p_similarity_threshold
  ORDER BY similarity DESC
  LIMIT p_limit;
$$;
```

## Implementation Plan

### Phase 1: Add Query Classification (1-2 hours)
- [ ] Add `classifyQueryIntent()` to VectorContextBuilder
- [ ] Use LLM to classify into AGGREGATE/COMPLETE/SAMPLE/DATE_SPECIFIC
- [ ] Route to appropriate strategy

### Phase 2: Add Aggregation Functions (2-3 hours)
- [ ] Create Supabase functions for aggregation
- [ ] Add `aggregateReceipts()`, `aggregateVisits()` to VectorSearchService
- [ ] Test with "how much did I spend" queries

### Phase 3: Add Tiered Summarization (2-3 hours)
- [ ] Add logic to condense results when count > 50
- [ ] Create summary format (by month, by category, etc.)
- [ ] Send detailed + condensed in same context

### Phase 4: Add Structured Filtering (3-4 hours)
- [ ] Create `filter_by_terms()` Supabase functions
- [ ] Use query expansion from UserMemoryService
- [ ] Combine with vector search for hybrid approach

### Phase 5: Optimize Context Format (1-2 hours)
- [ ] Design hierarchical context structure
- [ ] Test token counts with real data
- [ ] Benchmark: 1000 receipts should be <5K tokens

## Cost Analysis

### Current System (1000 receipts)
- Vector search: Top 50 receipts × ~300 chars = 15,000 chars ≈ 3,750 tokens
- Problem: Missing 950 receipts!
- Cost per query: ~$0.01 (Gemini 2.0 Flash input)

### New System (1000 receipts)

**AGGREGATE query:** "How much did I spend on haircuts?"
- Context: Summary stats only ≈ 400 tokens
- Cost: $0.001 (90% cheaper, 100% accurate)

**COMPLETE query:** "Show me all haircuts"
- Context: Summary + condensed list ≈ 3,000 tokens
- Cost: $0.006 (40% cheaper, 100% complete)

**SAMPLE query:** "Show me some receipts"
- Context: Top 50 detailed ≈ 3,750 tokens (same as current)
- Cost: $0.01 (same cost, same quality)

## Benefits

1. **Completeness:** ALL data accessible, not just top-50
2. **Cost-effective:** 40-90% cheaper for large datasets
3. **Faster:** Database aggregation vs sending all data
4. **Scalable:** Works with 10K+ items with same performance
5. **Accurate:** LLM gets complete information for calculations

## Technical Details

### New Services to Add

1. **QueryIntentClassifier.swift**
   - Analyzes query to determine intent
   - Returns: queryType, needsAggregation, filters

2. **AggregationService.swift**
   - Handles database-level aggregations
   - Returns summary stats without full content

3. **ContextTieringService.swift**
   - Decides how to format results based on count
   - Handles summarization strategies

### Modified Services

1. **VectorSearchService.swift**
   - Remove hard limit of 50
   - Add `searchAll()` method for complete retrieval
   - Add `aggregate()` method for summary stats

2. **VectorContextBuilder.swift**
   - Route queries based on intent
   - Apply appropriate retrieval + formatting strategy
   - Remove maxTotalItems limit

3. **UserMemoryService.swift**
   - Already has `expandQuery()` - use this more aggressively
   - Add caching for common expansions

## Migration Path

1. Deploy new Supabase functions (no breaking changes)
2. Add new Swift services alongside existing ones
3. Update VectorContextBuilder to use new routing
4. Test with production data
5. Monitor token usage and accuracy
6. Deprecate old hard limits once stable

## Success Metrics

- Query "all haircuts" returns 100% of haircuts (not 50)
- Query "how much spent on X" uses <500 tokens
- Query "show all receipts" completes in <3 seconds
- Token usage reduced by 50% on average
- Zero "missing data" user complaints
