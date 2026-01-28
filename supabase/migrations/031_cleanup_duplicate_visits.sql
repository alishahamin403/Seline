-- Migration: Cleanup existing duplicate visits before enforcing uniqueness
-- Purpose: Remove duplicate visits that share the same (user_id, saved_place_id, entry_time)
-- Strategy: Keep the most recently created visit, delete older duplicates

-- Step 1: Identify and log duplicate visits
DO $$
DECLARE
    duplicate_count INT;
BEGIN
    SELECT COUNT(*)
    INTO duplicate_count
    FROM (
        SELECT user_id, saved_place_id, entry_time, COUNT(*) as dup_count
        FROM location_visits
        WHERE exit_time IS NOT NULL -- Only process closed visits for safety
        GROUP BY user_id, saved_place_id, entry_time
        HAVING COUNT(*) > 1
    ) duplicates;

    RAISE NOTICE '🔍 Found % groups of duplicate visits to clean up', duplicate_count;
END $$;

-- Step 2: Delete duplicate visits, keeping the most recent
-- Uses a CTE to find duplicates and keep only the latest created_at
WITH duplicates AS (
    SELECT
        user_id,
        saved_place_id,
        entry_time,
        array_agg(id ORDER BY created_at DESC) as visit_ids,
        COUNT(*) as duplicate_count
    FROM location_visits
    WHERE exit_time IS NOT NULL -- Only clean up closed visits
    GROUP BY user_id, saved_place_id, entry_time
    HAVING COUNT(*) > 1
),
to_delete AS (
    -- Keep first visit (most recent), delete the rest
    SELECT
        unnest(visit_ids[2:]) as id
    FROM duplicates
)
DELETE FROM location_visits
WHERE id IN (SELECT id FROM to_delete);

-- Step 3: Log cleanup results
DO $$
DECLARE
    deleted_count INT;
BEGIN
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RAISE NOTICE '✅ Cleaned up % duplicate visit records', deleted_count;
END $$;

-- Step 4: Verify no duplicates remain
DO $$
DECLARE
    remaining_duplicates INT;
BEGIN
    SELECT COUNT(*)
    INTO remaining_duplicates
    FROM (
        SELECT user_id, saved_place_id, entry_time, COUNT(*) as dup_count
        FROM location_visits
        GROUP BY user_id, saved_place_id, entry_time
        HAVING COUNT(*) > 1
    ) remaining;

    IF remaining_duplicates > 0 THEN
        RAISE WARNING '⚠️ Still have % groups of duplicate visits (may include open visits)', remaining_duplicates;
    ELSE
        RAISE NOTICE '✅ No duplicate visits remaining';
    END IF;
END $$;
