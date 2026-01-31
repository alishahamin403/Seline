# Migration Guide: Fix Duplicates & Apply Database Constraints

## Error You Encountered

```
ERROR: 22000: range lower bound must be less than or equal to range upper bound
```

This means some visits in your database have `entry_time` **after** `exit_time`, which is invalid data. This needs to be fixed before applying the exclusion constraint.

## Step-by-Step Migration Process

### Step 1: Fix Invalid Visit Times
**Apply migration:** `20260130000000_fix_invalid_visit_times.sql`

This migration will:
- Find all visits where entry_time > exit_time
- Swap the times if the difference is <24 hours (likely just backwards)
- Set exit_time to NULL for visits with >24h difference (mark as open visits needing review)

```bash
# Apply this migration first
supabase db push --include-migration 20260130000000_fix_invalid_visit_times.sql
```

### Step 2: Run Deduplication Service
**Before applying the exclusion constraint**, you need to remove all overlapping visits.

Add this button to your Settings or Admin view:

```swift
Button("Clean Up Duplicate Visits") {
    Task {
        isLoading = true
        let result = await VisitDeduplicationService.shared.deduplicateAllVisits()
        isLoading = false

        // Show results to user
        showAlert(
            title: "Deduplication Complete",
            message: """
            Duplicate groups found: \(result.duplicateGroupsFound)
            Visits deleted: \(result.visitsDeleted)
            Notes preserved: \(result.notesPreserved)
            People preserved: \(result.peoplePreserved)
            """
        )
    }
}
```

**Run this and wait for completion** before proceeding to Step 3.

### Step 3: Apply Exclusion Constraint
**Apply migration:** `20260130000001_prevent_overlapping_visits.sql`

This migration will:
- Check for any remaining overlapping visits
- Log warnings if found
- Apply the exclusion constraint (will FAIL if overlaps still exist)

```bash
supabase db push --include-migration 20260130000001_prevent_overlapping_visits.sql
```

If this fails with overlapping visits, go back to Step 2 and run deduplication again.

### Step 4: Add Atomic Upsert Function
**Apply migration:** `20260130000002_atomic_visit_upsert.sql`

```bash
supabase db push --include-migration 20260130000002_atomic_visit_upsert.sql
```

This creates the database function that the updated GeofenceManager uses to atomically create or merge visits.

### Step 5: Add Health Check View
**Apply migration:** `20260130000003_duplicate_detection_view.sql`

```bash
supabase db push --include-migration 20260130000003_duplicate_detection_view.sql
```

This creates a view for monitoring potential duplicates going forward.

## Verification

After completing all steps, verify the fix:

```sql
-- Should return 0 rows (no invalid time ranges)
SELECT id, entry_time, exit_time
FROM location_visits
WHERE exit_time IS NOT NULL
  AND entry_time > exit_time;

-- Should return 0 rows (or very few rows flagging potential issues)
SELECT * FROM visit_health_check;

-- Check that constraint exists
SELECT conname, contype
FROM pg_constraint
WHERE conname = 'no_overlapping_visits';
```

## Quick Migration (All at Once)

If you want to apply all migrations in sequence:

```bash
# Fix invalid times
supabase db push --include-migration 20260130000000_fix_invalid_visit_times.sql

# Run deduplication in app (Step 2)
# ... wait for completion ...

# Apply remaining migrations
supabase db push --include-migration 20260130000001_prevent_overlapping_visits.sql
supabase db push --include-migration 20260130000002_atomic_visit_upsert.sql
supabase db push --include-migration 20260130000003_duplicate_detection_view.sql
```

## Troubleshooting

### If Step 3 fails with "exclusion constraint violation"

This means there are still overlapping visits. Run this query to find them:

```sql
SELECT v1.id as visit1_id, v1.entry_time as v1_entry, v1.exit_time as v1_exit,
       v2.id as visit2_id, v2.entry_time as v2_entry, v2.exit_time as v2_exit,
       v1.saved_place_id
FROM location_visits v1
INNER JOIN location_visits v2 ON
    v1.user_id = v2.user_id
    AND v1.saved_place_id = v2.saved_place_id
    AND v1.id < v2.id
    AND tsrange(v1.entry_time, COALESCE(v1.exit_time, 'infinity'::timestamp), '[)') &&
        tsrange(v2.entry_time, COALESCE(v2.exit_time, 'infinity'::timestamp), '[)')
LIMIT 10;
```

Then either:
- Run the deduplication service again
- Manually delete one of the overlapping visits
- Fix the exit_time to close the overlap

### If deduplication service fails

Check the console logs for specific errors. Common issues:
- Network connectivity
- Missing permissions
- Invalid visit data

You can also manually delete duplicates:

```sql
-- Find duplicates for a specific location and date
SELECT * FROM location_visits
WHERE saved_place_id = 'YOUR_PLACE_ID'
  AND DATE(entry_time) = '2026-01-30'
ORDER BY entry_time;

-- Delete specific visit by ID
DELETE FROM location_visits WHERE id = 'VISIT_ID';
```

## Expected Results

After successful completion:
- No visits with entry_time > exit_time
- No overlapping visits at the same location
- Database constraint prevents future overlaps
- Location history loads in <500ms (down from 3-10+ seconds)
- No more duplicate visits appearing in the UI
