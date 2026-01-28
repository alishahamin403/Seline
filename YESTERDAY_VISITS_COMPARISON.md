# Yesterday's Visits Comparison (2026-01-24)

## Summary
This document compares the visits stored in Supabase for yesterday (2026-01-24) with what should be displayed in the locations calendar view.

## Visits in Supabase (10 total)

| # | Place | Entry Time | Exit Time | Duration | Notes | Session ID | Merge Reason |
|---|-------|------------|-----------|----------|-------|-----------|--------------|
| 1 | 6369 Amber Glen Dr | 03:22:38 | 04:59:59 | 97 min | - | dac7d570... | midnight_split_part1 |
| 2 | 6369 Amber Glen Dr | 05:00:00 | 16:56:53 | 716 min | - | dac7d570... | continuous_visit |
| 3 | LA Fitness | 17:22:47 | 18:22:12 | 59 min | - | eb52e539... | quick_return |
| 4 | 6369 Amber Glen Dr | 18:39:53 | 20:13:39 | 93 min | - | 84634c4e... | open_visit |
| 5 | Marshalls | 21:01:01 | 21:28:40 | 27 min | "Came here to shop for TASIF and sujaiya's dad's gifts for baat pakki" | 9eb7c26a... | app_launch_inside |
| 6 | Tesla Supercharger | 21:30:03 | 21:46:50 | 16 min | - | c8a9f9bb... | null |
| 7 | 51 E 13th St | 22:45:50 | 22:51:07 | 5 min | - | 010eee0f... | null |
| 8 | Lime Ridge Mall | 22:55:42 | 22:58:07 | 2 min | - | 33c394fd... | null |
| 9 | Tesla Supercharger | 23:00:05 | 23:22:21 | 22 min | - | 3cf3cbba... | app_launch_inside |
| 10 | Walmart Supercentre | 23:29:17 | 23:50:01 | 20 min | - | 3619875d... | null |

## ROOT CAUSE: Midnight-Spanning Visit Not Split in Database

**The issue:** A visit from the previous day (2026-01-23) spans midnight but is NOT split in Supabase:
- Visit ID: `ff0ff08e-b969-4902-b1a8-acfe92cb27b5`
- Place: 51 E 13th St (Home)
- Entry: 2026-01-23 13:10:58
- Exit: 2026-01-24 03:22:38
- Duration: 851 minutes (14 hours)

This visit **should** have been split into:
- **Part 1**: 2026-01-23 13:10:58 → 2026-01-23 23:59:59 (649 minutes)
- **Part 2**: 2026-01-24 00:00:00 → 2026-01-24 03:22:38 (202 minutes)

### What You're Seeing in Calendar View

The calendar view splits this visit **on-the-fly** for display, which is why you see:
1. **12:00 AM (midnight)** - Part 2 of the split visit at 51 E 13th St
2. **Other home visits** from 6369 Amber Glen Dr

But the visit history shows the **raw unsplit data** from Supabase, causing inconsistency.

## Expected Display After Migration

After running the migration `034_split_midnight_spanning_visits.sql`, both calendar and history views will show:

### Home Visits for Yesterday (2026-01-24)
1. **12:00 AM - 3:22 AM**: 51 E 13th St (202 min) - `midnight_split_part2`
2. **3:22 AM - 4:59 AM**: 6369 Amber Glen Dr (97 min) - `midnight_split_part1`
3. **5:00 AM - 4:56 PM**: 6369 Amber Glen Dr (716 min) - `continuous_visit`
4. **6:39 PM - 8:13 PM**: 6369 Amber Glen Dr (93 min) - `open_visit`
5. **10:45 PM - 10:51 PM**: 51 E 13th St (5 min)

**Total: 5 home visits**

**Note:** Visits 2 & 3 will NOT be auto-merged even though they have a 1-second gap, because visit 2 has `midnight_split_part1` in its merge_reason. The auto-merge logic specifically prevents merging midnight-split visits to preserve day boundaries.

## Verification Steps

1. **Check if visits 1 & 2 are merged in the app:**
   - Open locations calendar view
   - Select yesterday (2026-01-24)
   - Check if there's one long visit at "6369 Amber Glen Dr" from 03:22 to 16:56
   - OR if there are two separate visits (which would indicate the merge isn't working)

2. **Verify all other visits appear:**
   - LA Fitness (17:22-18:22)
   - 6369 Amber Glen Dr again (18:39-20:13)
   - Marshalls (21:01-21:28) - should show notes
   - Tesla Supercharger (21:30-21:46)
   - 51 E 13th St (22:45-22:51)
   - Lime Ridge Mall (22:55-22:58)
   - Tesla Supercharger (23:00-23:22)
   - Walmart Supercentre (23:29-23:50)

## Potential Issues

1. **If 10 visits are shown instead of 9:**
   - The auto-merge logic for visits 1 & 2 is not working
   - Check `autoMergeVisits()` function in `LocationVisitAnalytics.swift`

2. **If fewer than 9 visits are shown:**
   - Some visits might be filtered out incorrectly
   - Check if any visits are being excluded by duration or other filters

3. **If visit times don't match:**
   - Check timezone handling in the query
   - Verify `startOfDay` calculation matches database timezone

## Query Used for Supabase Check

```sql
SELECT 
    lv.id,
    lv.saved_place_id,
    sp.name as place_name,
    sp.category,
    lv.entry_time,
    lv.exit_time,
    lv.duration_minutes,
    lv.visit_notes,
    lv.session_id,
    lv.merge_reason
FROM location_visits lv
JOIN saved_places sp ON lv.saved_place_id = sp.id
WHERE lv.entry_time >= date_trunc('day', CURRENT_DATE - INTERVAL '1 day')
  AND lv.entry_time < date_trunc('day', CURRENT_DATE)
ORDER BY lv.entry_time ASC;
```
