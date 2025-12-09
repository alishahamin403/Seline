-- Migration: cleanup_short_visits
-- Purpose: Delete all existing visits shorter than 10 minutes
-- These are false positives from:
--   - Xcode app rebuilds (force-kill → incomplete visit)
--   - GPS glitches (brief entry/exit events)
--   - Passing by locations without actually stopping

-- Delete short completed visits (< 10 minutes)
DELETE FROM location_visits
WHERE duration_minutes < 10
  AND duration_minutes IS NOT NULL
  AND exit_time IS NOT NULL;

-- Note: Going forward, the app will automatically delete short visits
-- via the deleteVisitFromSupabase() function in GeofenceManager
