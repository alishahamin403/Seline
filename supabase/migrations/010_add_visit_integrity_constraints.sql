-- Add data integrity constraints to location_visits table
-- Ensures atomic operations and prevents impossible data states

-- 1. Add unique constraint: Only ONE incomplete visit per user globally
-- This prevents the issue where multiple "Active" visits can exist simultaneously
-- Uses partial index (WHERE exit_time IS NULL) so completed visits don't conflict
ALTER TABLE location_visits
ADD CONSTRAINT only_one_incomplete_visit_per_user
UNIQUE (user_id)
WHERE exit_time IS NULL;

-- 2. Add index for better query performance when checking unresolved visits
CREATE INDEX IF NOT EXISTS idx_location_visits_user_incomplete
ON location_visits(user_id, entry_time DESC)
WHERE exit_time IS NULL;

-- Log the migration
INSERT INTO schema_version (id, version) VALUES (2, '2.1_visit_integrity_constraints')
ON CONFLICT DO NOTHING;
