# Database Verification Report

## Summary
✅ **All midnight-spanning visits are already split in Supabase**
✅ **No visits need splitting**
✅ **Database is correct and matches calendar view logic**

## Verification Results

### Total Midnight-Spanning Visits
- **Total visits that span midnight**: 5
- **Already split with midnight_split marker**: 5
- **Unsplit visits needing migration**: 0

### Home Visits for Yesterday (2026-01-24)

| # | Time | Place | Duration | Merge Reason | Session ID |
|---|------|-------|----------|--------------|------------|
| 1 | 12:00 AM - 3:22 AM | 51 E 13th St | 203 min | midnight_split_part2 | 07d951a8... |
| 2 | 3:22 AM - 4:59 AM | 6369 Amber Glen Dr | 97 min | midnight_split_part1 | dac7d570... |
| 3 | 5:00 AM - 4:56 PM | 6369 Amber Glen Dr | 716 min | continuous_visit | dac7d570... |
| 4 | 6:39 PM - 8:13 PM | 6369 Amber Glen Dr | 93 min | open_visit | 84634c4e... |
| 5 | 10:45 PM - 10:51 PM | 51 E 13th St | 5 min | - | 010eee0f... |

### Processing Notes

**Visits #2 and #3 have the SAME session_id** but will NOT be merged because:
- Visit #2 has `midnight_split_part1` in merge_reason
- The `autoMergeVisits()` function does NOT merge midnight-split visits
- This preserves the midnight boundary

Therefore, **both calendar and history views should show 5 home visits**.

## User-Reported Times vs Database

You reported seeing 3 visits at:
1. **12:00 AM** ✅ Matches visit #1
2. **1:39 PM** ❌ Database shows 6:39 PM (visit #4)
3. **11:15 PM** ❌ Database shows 10:45 PM (visit #5)

## Possible Explanations

### 1. Timezone Conversion Issue
- Database stores times in UTC
- App displays in local timezone
- If timezone offset is being applied incorrectly or twice, times would shift

### 2. Cache Issue
- Calendar view might be showing cached data
- Try invalidating the cache or restarting the app

### 3. Display Formatting Issue
- Time formatter might be converting 12-hour format incorrectly
- 18:39 (6:39 PM) might be displaying as 1:39 PM if AM/PM is inverted

### 4. Wrong Day Selected
- You might be viewing a different day than yesterday
- Or calendar is showing merged data from multiple days

### 5. Processing Logic Merging Visits
- The `processVisitsForDisplay()` might be merging some visits unexpectedly
- Check if visits with same session_id are being combined

## Debugging Steps

### Step 1: Check what the app is actually querying
Look at the query in `LocationTimelineView.swift` line 1207:
```swift
.gte("entry_time", value: startOfDay.ISO8601Format())
.lt("entry_time", value: endOfDay.ISO8601Format())
```

Verify `startOfDay` and `endOfDay` are correct for yesterday.

### Step 2: Check timezone handling
Add logging to see what timezone the dates are in:
```swift
print("📅 Selected date: \(selectedDate)")
print("📅 Start of day: \(startOfDay)")
print("📅 End of day: \(endOfDay)")
print("📅 ISO8601: \(startOfDay.ISO8601Format())")
```

### Step 3: Check processVisitsForDisplay output
Add logging to see what visits are being processed:
```swift
print("📍 Raw visits count: \(rawVisits.count)")
print("📍 Processed visits count: \(processedVisits.count)")
for visit in processedVisits {
    print("  - \(visit.entryTime) at \(place.displayName)")
}
```

### Step 4: Clear cache
The app caches visit data. Try:
1. Restart the app
2. Or call `LocationVisitAnalytics.shared.invalidateAllVisitCaches()`

### Step 5: Check visit history view
Compare what visit history shows vs calendar view for the same location.

## Migration Status

❌ **Migration NOT needed** - Data is already correct in Supabase

The migration file `034_split_midnight_spanning_visits.sql` was created but doesn't need to be run since all visits are already split.

## Recommendation

The issue appears to be in the **app's display layer**, not the database. Focus debugging on:
1. Timezone handling
2. Cache invalidation
3. Time formatting in the UI
4. Which day is actually being queried

The database is correct and consistent with the calendar view's splitting logic.
