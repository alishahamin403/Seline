-- Migration: Add unique constraint to prevent duplicate visit entries
-- Purpose: Prevent race conditions from creating multiple visits with identical entry times
-- Impact: Database-level enforcement of visit uniqueness

-- Add unique index on (user_id, saved_place_id, entry_time) for open visits
-- Only enforce on open visits (exit_time IS NULL) to allow historical duplicates
CREATE UNIQUE INDEX IF NOT EXISTS idx_location_visits_unique_entry
ON location_visits(user_id, saved_place_id, entry_time)
WHERE exit_time IS NULL;

-- Add comment for documentation
COMMENT ON INDEX idx_location_visits_unique_entry IS
'Prevents duplicate open visits with same entry time. Only enforced on incomplete visits (exit_time IS NULL).';

-- Log successful migration
DO $$
BEGIN
    RAISE NOTICE '✅ Added unique constraint on visit entry times for open visits';
END $$;
