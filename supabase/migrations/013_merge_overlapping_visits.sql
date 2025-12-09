-- Migration: merge_overlapping_visits
-- Purpose: Merge visits where a new visit starts within 10 minutes of the previous visit's end
-- This fixes the issue where continuous visits are incorrectly split into multiple records

-- Create a temporary table to store visit pairs that should be merged
CREATE TEMP TABLE visits_to_merge AS
SELECT DISTINCT ON (v1.id, v2.id)
    v1.id as first_visit_id,
    v1.entry_time as first_entry,
    v1.exit_time as first_exit,
    v1.duration_minutes as first_duration,
    v2.id as second_visit_id,
    v2.entry_time as second_entry,
    v2.exit_time as second_exit,
    v2.duration_minutes as second_duration,
    EXTRACT(EPOCH FROM (v2.entry_time - v1.exit_time))/60 as gap_minutes,
    v1.saved_place_id,
    v1.user_id,
    -- Calculate merged visit times
    v1.entry_time as merged_entry,
    COALESCE(v2.exit_time, v1.exit_time) as merged_exit,
    EXTRACT(EPOCH FROM (COALESCE(v2.exit_time, v1.exit_time) - v1.entry_time))/60 as merged_duration
FROM location_visits v1
JOIN location_visits v2 ON v1.saved_place_id = v2.saved_place_id
    AND v1.user_id = v2.user_id
    AND v2.entry_time > v1.exit_time
    AND v2.entry_time <= v1.exit_time + INTERVAL '10 minutes'
    AND v1.id != v2.id
WHERE v1.exit_time IS NOT NULL
ORDER BY v1.id, v2.id, v2.entry_time;

-- Show what will be merged (for logging)
DO $$
DECLARE
    merge_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO merge_count FROM visits_to_merge;
    RAISE NOTICE 'Found % visit pairs to merge', merge_count;
END $$;

-- Update the first visit to extend to the second visit's exit time
UPDATE location_visits
SET
    exit_time = vtm.merged_exit,
    duration_minutes = ROUND(vtm.merged_duration)::INTEGER,
    merge_reason = COALESCE(merge_reason, '') ||
        CASE
            WHEN merge_reason IS NULL OR merge_reason = '' THEN 'auto_merged_continuous'
            ELSE ',auto_merged_continuous'
        END,
    confidence_score = CASE
        WHEN vtm.gap_minutes <= 3 THEN 0.95
        ELSE 0.90
    END,
    updated_at = NOW()
FROM visits_to_merge vtm
WHERE location_visits.id = vtm.first_visit_id;

-- Delete the second visit (now merged into the first)
DELETE FROM location_visits
WHERE id IN (SELECT second_visit_id FROM visits_to_merge);

-- Log the results
DO $$
DECLARE
    deleted_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO deleted_count FROM visits_to_merge;
    RAISE NOTICE 'Merged and deleted % duplicate visit records', deleted_count;
END $$;

-- Clean up temp table
DROP TABLE visits_to_merge;
