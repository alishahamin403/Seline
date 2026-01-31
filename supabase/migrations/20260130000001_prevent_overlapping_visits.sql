-- Prevent overlapping visits at the same location
-- This is the strongest guard against duplicates

-- Enable the btree_gist extension for exclusion constraints
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- First, check for any overlapping visits and log them
DO $$
DECLARE
    overlap_count INTEGER;
    invalid_range_count INTEGER;
BEGIN
    -- Check for invalid time ranges (entry > exit)
    SELECT COUNT(*) INTO invalid_range_count
    FROM location_visits
    WHERE exit_time IS NOT NULL
      AND entry_time > exit_time;

    IF invalid_range_count > 0 THEN
        RAISE EXCEPTION 'Found % visits with invalid time ranges (entry > exit). Run migration 20260130000000 first.', invalid_range_count;
    END IF;

    -- Check for overlapping visits
    SELECT COUNT(*) INTO overlap_count
    FROM location_visits v1
    INNER JOIN location_visits v2 ON
        v1.user_id = v2.user_id
        AND v1.saved_place_id = v2.saved_place_id
        AND v1.id < v2.id  -- Avoid counting same pair twice
        AND tsrange(v1.entry_time, COALESCE(v1.exit_time, 'infinity'::timestamp), '[)') &&
            tsrange(v2.entry_time, COALESCE(v2.exit_time, 'infinity'::timestamp), '[)');

    IF overlap_count > 0 THEN
        RAISE WARNING 'Found % pairs of overlapping visits. Consider running VisitDeduplicationService before applying this constraint.', overlap_count;

        -- Log details of overlapping visits for review
        RAISE NOTICE 'Sample overlapping visits:';
        PERFORM v1.id, v1.entry_time, v1.exit_time, v2.id, v2.entry_time, v2.exit_time
        FROM location_visits v1
        INNER JOIN location_visits v2 ON
            v1.user_id = v2.user_id
            AND v1.saved_place_id = v2.saved_place_id
            AND v1.id < v2.id
            AND tsrange(v1.entry_time, COALESCE(v1.exit_time, 'infinity'::timestamp), '[)') &&
                tsrange(v2.entry_time, COALESCE(v2.exit_time, 'infinity'::timestamp), '[)')
        LIMIT 5;
    ELSE
        RAISE NOTICE 'No overlapping visits found - safe to add exclusion constraint';
    END IF;
END $$;

-- Add exclusion constraint to prevent overlapping time ranges
-- This prevents ANY time overlap at the same location for the same user
-- Note: This will FAIL if overlapping visits exist - run deduplication first
ALTER TABLE location_visits
ADD CONSTRAINT no_overlapping_visits
EXCLUDE USING gist (
    user_id WITH =,
    saved_place_id WITH =,
    tsrange(entry_time, COALESCE(exit_time, 'infinity'::timestamp), '[)') WITH &&
);
