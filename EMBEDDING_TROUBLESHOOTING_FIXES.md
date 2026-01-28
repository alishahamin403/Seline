# Embedding Troubleshooting - Fixes Applied

## Issues Identified

1. **No immediate embedding on create/update**: When notes, emails, tasks, etc. were created or updated, embeddings were only synced periodically (every 5 minutes) or on app launch, causing delays in searchability.

2. **5-minute cooldown too long**: The `syncEmbeddingsIfNeeded()` function had a 5-minute cooldown, preventing immediate embedding of new data.

3. **Similarity threshold too high**: The threshold was 0.25-0.3, which might filter out some relevant results.

4. **Limited error logging**: Errors during embedding weren't logged with enough detail for troubleshooting.

5. **CRITICAL: Intent detection misclassifying visit queries**: Queries like "Describe my visits from yesterday what did I do all day" were being classified as `.schedule` (calendar) instead of `.locations` (visits) because the schedule check came BEFORE the locations check in the code order, and phrases like "day" + "what" matched the schedule pattern. This caused the LLM to return calendar events instead of visit history.

## Fixes Applied

### 1. Immediate Embedding on Note Create/Update ✅

**File**: `Seline/Models/NoteModels.swift`

- Added `embedNoteImmediately()` helper function that embeds notes immediately after successful save/update
- Updated `addNote()`, `addNoteAndWaitForSync()`, `updateNote()`, and `updateNoteAndWaitForSync()` to call embedding immediately after Supabase sync succeeds
- Notes are now searchable within seconds of creation/update instead of waiting up to 5 minutes

### 2. Reduced Cooldown Period ✅

**File**: `Seline/Services/VectorSearchService.swift`

- Reduced cooldown from 5 minutes (300s) to 30 seconds (30s)
- Added `syncEmbeddingsImmediately()` method that bypasses cooldown for force syncs
- This allows more frequent syncing while still preventing excessive API calls

### 3. Lowered Similarity Threshold ✅

**Files**: 
- `Seline/Services/VectorSearchService.swift` (changed from 0.25 to 0.15)
- `supabase/functions/embeddings-proxy/index.ts` (changed default from 0.3 to 0.15)

- Lower threshold improves recall (finds more relevant results)
- May return slightly less precise results, but ensures important data isn't missed

### 4. Enhanced Error Logging ✅

**File**: `Seline/Services/VectorSearchService.swift`

- Added detailed error logging in `batchEmbed()` function
- Added diagnostic warnings in `syncAllEmbeddings()` when no documents are embedded
- Better error messages help identify authentication issues, API failures, or data problems

### 5. Fixed Intent Detection for Visit Queries ✅

**File**: `Seline/Services/VectorContextBuilder.swift`

- **Root cause**: The `analyzeQueryIntent()` function checked for schedule intent BEFORE locations intent. Queries containing "day" + "what" (like "what did I do all day") matched the schedule pattern first, so visit-related queries never reached the locations check.
- **Fix**: Moved the locations check BEFORE the schedule check in the intent detection order
- **Added phrases**: "what did i do" and "all day" now also trigger locations intent
- **Fallback added**: Even if classified as `.schedule`, queries with day references now ALSO get day activity context (visits + events + receipts)
- Added diagnostic logging to show which intent was detected

## Testing Recommendations

1. **Test immediate embedding**:
   - Create a new note
   - Wait 10-15 seconds
   - Ask the LLM about the note content
   - It should be found immediately

2. **Test similarity threshold**:
   - Ask about data that might not match exactly
   - Lower threshold should return more results

3. **Check logs**:
   - Look for "✅ Immediately embedded note" messages
   - Check for any "⚠️" warnings about embedding failures
   - Verify embedding counts in sync completion messages

## Next Steps (Optional Improvements)

1. **Add immediate embedding for other document types**:
   - Emails (when received/sent)
   - Tasks (when created/updated)
   - Locations (when saved/updated)
   - Receipts (when created)
   - Visits (when created)
   - People (when added/updated)

2. **Add manual force-sync UI**:
   - Add a button in Settings or Chat view to manually trigger `syncEmbeddingsImmediately()`
   - Useful for troubleshooting and ensuring all data is embedded

3. **Add embedding status indicator**:
   - Show in UI how many documents are embedded
   - Show last sync time
   - Show if sync is in progress

## Database Verification

To verify embeddings are working correctly, you can check:

```sql
-- Count embeddings by type
SELECT document_type, COUNT(*) 
FROM document_embeddings 
WHERE user_id = '<your-user-id>'
GROUP BY document_type;

-- Check recent embeddings
SELECT document_type, title, created_at, updated_at
FROM document_embeddings
WHERE user_id = '<your-user-id>'
ORDER BY updated_at DESC
LIMIT 20;

-- Check for missing embeddings (compare with actual data)
-- This requires comparing with your actual notes/emails/tasks tables
```

## Common Issues & Solutions

### Issue: "No documents were embedded"
**Possible causes**:
- All documents already embedded (check database)
- Authentication issues (check user session)
- No documents exist in the app

### Issue: "Failed to immediately embed note"
**Possible causes**:
- Network connectivity issues
- API rate limits
- Note encryption/decryption issues
- **Note**: This is not critical - note will be embedded on next sync

### Issue: "Vector search failed"
**Possible causes**:
- Edge function not deployed
- GEMINI_API_KEY not set in Supabase
- Database migration not applied (check vector dimensions are 768)

## Files Modified

1. `Seline/Models/NoteModels.swift` - Added immediate embedding triggers
2. `Seline/Services/VectorSearchService.swift` - Reduced cooldown, improved logging, lowered threshold
3. `supabase/functions/embeddings-proxy/index.ts` - Lowered default similarity threshold
4. `Seline/Services/VectorContextBuilder.swift` - Fixed intent detection order, added visit query phrases

## Database Verification Results

Verified that visits ARE being stored correctly in Supabase:
- 254 visit embeddings exist
- Visits include timestamps, durations, and visit_notes (reasons)
- Example: Marshalls visit on Jan 24 has notes: "Came here to shop for TASIF and sujaiya's dad's gifts for baat pakki"

The issue was NOT with data storage or embeddings - it was with how the query intent was being classified, which caused the wrong context builder to be used.

---

**Date**: January 25, 2026
**Status**: ✅ All fixes applied and ready for testing
