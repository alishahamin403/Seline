# Midnight Split Migration Guide

## Problem
Visits that span midnight (e.g., from 11 PM on day 1 to 3 AM on day 2) are stored as a single visit in Supabase. The calendar view splits them on-the-fly for display, but the visit history view shows the raw unsplit data, causing inconsistency.

## Solution
Split all midnight-spanning visits directly in the Supabase database so both calendar and history views show consistent data.

## Migration File
`supabase/migrations/034_split_midnight_spanning_visits.sql`

## What It Does
1. Finds all visits where `DATE(entry_time) != DATE(exit_time)` and not already split
2. Splits each visit into two:
   - **Part 1**: Entry time → 23:59:59 of entry day (merge_reason: 'midnight_split_part1')
   - **Part 2**: 00:00:00 of exit day → Exit time (merge_reason: 'midnight_split_part2')
3. Deletes the original unsplit visit
4. Preserves all visit metadata (notes, session_id, etc.)

## Example
**Before:**
- Visit: 2026-01-23 13:10:58 → 2026-01-24 03:22:38 (851 minutes)

**After:**
- Part 1: 2026-01-23 13:10:58 → 2026-01-23 23:59:59 (649 minutes)
- Part 2: 2026-01-24 00:00:00 → 2026-01-24 03:22:38 (202 minutes)

## How to Apply

### Option 1: Using Supabase CLI (Recommended)
```bash
cd /Users/alishahamin/Desktop/Vibecode/Seline
supabase db push
```

### Option 2: Manual SQL Execution
1. Open Supabase Dashboard → SQL Editor
2. Copy contents of `supabase/migrations/034_split_midnight_spanning_visits.sql`
3. Run the SQL
4. Verify the results

## Verification

After running the migration, check the results:

```sql
-- Verify no unsplit midnight-spanning visits remain
SELECT COUNT(*) as remaining_unsplit_visits
FROM location_visits
WHERE exit_time IS NOT NULL
  AND DATE(entry_time) != DATE(exit_time)
  AND (merge_reason IS NULL OR merge_reason NOT LIKE '%midnight_split%');

-- Check the split visits for yesterday
SELECT 
    lv.id,
    sp.name as place_name,
    lv.entry_time,
    lv.exit_time,
    lv.duration_minutes,
    lv.merge_reason
FROM location_visits lv
JOIN saved_places sp ON lv.saved_place_id = sp.id
WHERE lv.entry_time >= date_trunc('day', CURRENT_DATE - INTERVAL '1 day')
  AND lv.entry_time < date_trunc('day', CURRENT_DATE)
  AND sp.category = 'Homes'
ORDER BY lv.entry_time ASC;
```

## Impact on App Code

### ✅ No Changes Needed
The app code already handles split visits correctly:
- `processVisitsForDisplay()` recognizes visits with `merge_reason` containing 'midnight_split'
- Visit history will now show split visits directly from Supabase
- Calendar view will continue to work as expected

### ⚠️ Auto-Merge Behavior
Visits with `merge_reason` containing 'midnight_split' will NOT be auto-merged even if they have <5 minute gaps. This is correct behavior to preserve the day boundary.

## Expected Results for Yesterday (2026-01-24)

### Before Migration
Calendar view (with on-the-fly splitting) shows:
- 12:00 AM - 3:22 AM: 51 E 13th St (part 2 of split)
- 3:22 AM - 4:59 AM: 6369 Amber Glen Dr  
- 5:00 AM - 4:56 PM: 6369 Amber Glen Dr
- 6:39 PM - 8:13 PM: 6369 Amber Glen Dr

History view shows RAW DATA (inconsistent).

### After Migration
Both calendar and history views show:
- 12:00 AM - 3:22 AM: 51 E 13th St (midnight_split_part2)
- 3:22 AM - 4:59 AM: 6369 Amber Glen Dr (midnight_split_part1)
- 5:00 AM - 4:56 PM: 6369 Amber Glen Dr (continuous_visit)
- 6:39 PM - 8:13 PM: 6369 Amber Glen Dr (open_visit)

## Future Visits
All new visits are already being split at midnight by the app code before saving to Supabase (via `splitAtMidnightIfNeeded()`). This migration only fixes historical data.

## Rollback (if needed)
This migration is irreversible because it deletes original visits. If you need to rollback:
1. Restore from a Supabase backup before the migration
2. Or manually identify split visits by session_id and merge them back
