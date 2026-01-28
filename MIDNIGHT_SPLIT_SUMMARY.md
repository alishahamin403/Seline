# Midnight Split Issue - Summary & Solution

## Problem Identified

You're seeing **3 home visits** in the calendar view at:
- 12:00 AM (midnight)
- 1:39 PM  
- 11:15 PM

But Supabase shows **different times**. Here's why:

### Root Cause

**Visit ID `ff0ff08e-b969-4902-b1a8-acfe92cb27b5`** at **51 E 13th St** spans midnight:
- **Entry**: 2026-01-23 13:10:58 (1:10 PM on Jan 23)
- **Exit**: 2026-01-24 03:22:38 (3:22 AM on Jan 24)
- **Duration**: 851 minutes (14+ hours)
- **Status**: NOT split in database (merge_reason is NULL)

This visit **crosses the midnight boundary** and should be split into two:
- **Part 1**: Jan 23, 1:10 PM → 11:59:59 PM (649 min)
- **Part 2**: Jan 24, 12:00 AM → 3:22 AM (202 min)

### Why the Times Don't Match

1. **Calendar view**: Splits the visit on-the-fly and shows Part 2 starting at **12:00 AM**
2. **Visit history**: Shows the raw unsplit visit from Supabase starting at **1:10 PM** (on Jan 23)

This creates inconsistency between views.

## Solution

Run the migration `034_split_midnight_spanning_visits.sql` to split all midnight-spanning visits directly in Supabase.

### How to Apply

```bash
cd /Users/alishahamin/Desktop/Vibecode/Seline
supabase db push
```

Or manually run the SQL from `supabase/migrations/034_split_midnight_spanning_visits.sql` in Supabase Dashboard.

## Expected Results After Migration

### Home Visits for Yesterday (2026-01-24) - AFTER SPLIT

| # | Time | Place | Duration | Merge Reason |
|---|------|-------|----------|--------------|
| 1 | 12:00 AM - 3:22 AM | 51 E 13th St | 202 min | midnight_split_part2 |
| 2 | 3:22 AM - 4:59 AM | 6369 Amber Glen Dr | 97 min | midnight_split_part1 |
| 3 | 5:00 AM - 4:56 PM | 6369 Amber Glen Dr | 716 min | continuous_visit |
| 4 | 6:39 PM - 8:13 PM | 6369 Amber Glen Dr | 93 min | open_visit |
| 5 | 10:45 PM - 10:51 PM | 51 E 13th St | 5 min | - |

**Total: 5 home visits**

### Why Visits 2 & 3 Won't Merge

Even though there's only a 1-second gap between visits 2 and 3:
- Visit 2 has `midnight_split_part1` in merge_reason
- The auto-merge logic prevents merging midnight-split visits
- This preserves the day boundary (keeps midnight splits separate)

## Impact

✅ **Calendar view** and **Visit history view** will now show identical data  
✅ No app code changes needed  
✅ All future visits already split correctly  
✅ Migration fixes 10+ historical visits

## Visits That Will Be Split

The migration will split **10 visits** including:
1. 51 E 13th St: Jan 23 1:10 PM → Jan 24 3:22 AM ← **This is your issue**
2. 6369 Amber Glen Dr: Jan 22 11:29 PM → Jan 23 4:34 AM
3. 6369 Amber Glen Dr: Jan 20 10:13 PM → Jan 21 3:28 AM
4. ...and 7 more

All are home visits that span midnight and need splitting.

## Verification After Migration

```sql
-- Check home visits for yesterday after migration
SELECT 
    sp.name as place_name,
    lv.entry_time,
    lv.exit_time,
    lv.duration_minutes,
    lv.merge_reason
FROM location_visits lv
JOIN saved_places sp ON lv.saved_place_id = sp.id
WHERE lv.entry_time >= '2026-01-24 00:00:00'
  AND lv.entry_time < '2026-01-25 00:00:00'
  AND sp.category = 'Homes'
ORDER BY lv.entry_time ASC;
```

This should show 5 home visits with the times listed above.
