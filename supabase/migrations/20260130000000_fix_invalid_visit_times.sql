-- Fix invalid visit records where entry_time is after exit_time
-- This must run BEFORE the exclusion constraint migration

-- First, let's identify and log the problematic records
DO $$
DECLARE
    invalid_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO invalid_count
    FROM location_visits
    WHERE exit_time IS NOT NULL
      AND entry_time > exit_time;

    RAISE NOTICE 'Found % visits with invalid time ranges (entry > exit)', invalid_count;
END $$;

-- Option 1: Swap entry and exit times if they're reversed
-- This assumes the times are just backwards
UPDATE location_visits
SET
    entry_time = exit_time,
    exit_time = entry_time,
    duration_minutes = EXTRACT(EPOCH FROM (entry_time - exit_time)) / 60
WHERE exit_time IS NOT NULL
  AND entry_time > exit_time
  AND EXTRACT(EPOCH FROM (entry_time - exit_time)) / 60 < 1440; -- Less than 24 hours difference

-- Option 2: For visits where swap doesn't make sense (>24h difference),
-- set exit_time to NULL to mark them as open visits that need review
UPDATE location_visits
SET
    exit_time = NULL,
    duration_minutes = NULL
WHERE exit_time IS NOT NULL
  AND entry_time > exit_time;

-- Log the fixes
DO $$
DECLARE
    remaining_invalid INTEGER;
BEGIN
    SELECT COUNT(*) INTO remaining_invalid
    FROM location_visits
    WHERE exit_time IS NOT NULL
      AND entry_time > exit_time;

    IF remaining_invalid = 0 THEN
        RAISE NOTICE 'All invalid time ranges have been fixed';
    ELSE
        RAISE WARNING 'Still have % invalid visits - manual review needed', remaining_invalid;
    END IF;
END $$;
