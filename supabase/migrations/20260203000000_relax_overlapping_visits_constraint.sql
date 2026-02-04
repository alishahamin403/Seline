-- Migration: Relax overlapping visits constraint
-- Date: 2026-02-03
-- Purpose: Remove strict exclusion constraint that blocks legitimate visit merges
--
-- Background:
-- The previous no_overlapping_visits exclusion constraint prevented ANY time overlap,
-- which blocked legitimate operations like:
-- 1. Manual merging of visits 5-10 minutes apart
-- 2. Auto-merging of adjacent visits (where visit1.exit = visit2.entry)
-- 3. Updating visit times when consolidating multiple visits
--
-- Solution:
-- - Remove the exclusion constraint
-- - Keep basic CHECK constraint for data integrity (entry < exit)
-- - Add partial index for monitoring/debugging potential overlaps
-- - Rely on application-level atomic upsert for duplicate prevention

-- Drop the strict exclusion constraint
ALTER TABLE location_visits
DROP CONSTRAINT IF EXISTS no_overlapping_visits;

-- Keep basic time validity check
ALTER TABLE location_visits
DROP CONSTRAINT IF EXISTS valid_visit_times;

ALTER TABLE location_visits
ADD CONSTRAINT valid_visit_times
CHECK (entry_time < exit_time);

-- Add partial index to help monitor for potential overlaps
-- This is for debugging/monitoring only, not enforcement
CREATE INDEX IF NOT EXISTS idx_location_visits_overlap_check
ON location_visits (user_id, saved_place_id, entry_time, exit_time);

-- Add comment explaining the design decision
COMMENT ON TABLE location_visits IS
'Visit merging is handled at application level via atomic upsert_location_visit function.
No database-level overlap constraint to allow legitimate merge operations.
The valid_visit_times constraint ensures basic integrity (entry < exit).';
