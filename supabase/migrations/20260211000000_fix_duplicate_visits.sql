-- Migration: Fix duplicate visits bug
-- Date: 2026-02-11
-- Purpose: Fix DATE(exit_time) check that prevents open visits from being merged
--
-- Bug:
-- The condition "AND DATE(exit_time) = DATE(p_entry_time)" fails for open visits
-- because DATE(NULL) = NULL, which makes the entire WHERE clause exclude open visits.
-- This causes every geofence entry to create a NEW visit instead of merging with
-- the existing open visit, resulting in duplicate visits.
--
-- Fix:
-- Change to "AND (exit_time IS NULL OR DATE(exit_time) = DATE(p_entry_time))"
-- This allows open visits to pass the calendar day check while still restricting
-- closed visits to the same calendar day.

CREATE OR REPLACE FUNCTION public.upsert_location_visit(
    p_user_id uuid,
    p_saved_place_id uuid,
    p_entry_time timestamp,
    p_session_id uuid,
    p_merge_window_minutes integer DEFAULT 7
) RETURNS TABLE(visit_id uuid, action text, merge_reason text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_visit location_visits%ROWTYPE;
    v_new_visit_id uuid;
    v_merge_reason text;
BEGIN
    -- Find existing visit to merge with
    -- For open visits (exit_time IS NULL), skip the calendar day check
    -- For closed visits, only merge if on same calendar day
    SELECT * INTO v_existing_visit
    FROM location_visits
    WHERE user_id = p_user_id
      AND saved_place_id = p_saved_place_id
      AND (
          exit_time IS NULL  -- Open visit
          OR exit_time >= (p_entry_time - interval '1 minute' * p_merge_window_minutes)  -- Recent closed visit
      )
      AND (
          exit_time IS NULL  -- Allow open visits regardless of date
          OR DATE(exit_time) = DATE(p_entry_time)  -- Closed visits must be same day
      )
    ORDER BY entry_time DESC
    LIMIT 1
    FOR UPDATE NOWAIT;  -- Fail fast if locked

    -- Check if we found a mergeable visit
    IF FOUND THEN
        -- Determine merge reason
        IF v_existing_visit.exit_time IS NULL THEN
            v_merge_reason := 'continued_open_visit';
        ELSE
            v_merge_reason := 'quick_return';
        END IF;

        -- Reopen the existing visit
        UPDATE location_visits
        SET exit_time = NULL,
            duration_minutes = NULL,
            session_id = p_session_id,
            merge_reason = v_merge_reason,
            confidence_score = 1.0,
            updated_at = NOW()
        WHERE id = v_existing_visit.id;

        RETURN QUERY SELECT v_existing_visit.id, 'merged'::text, v_merge_reason;
    ELSE
        -- Create new visit
        v_new_visit_id := gen_random_uuid();
        INSERT INTO location_visits (
            id, user_id, saved_place_id, entry_time, session_id,
            confidence_score, created_at, updated_at,
            day_of_week, month, year, time_of_day
        ) VALUES (
            v_new_visit_id, p_user_id, p_saved_place_id, p_entry_time, p_session_id,
            1.0, NOW(), NOW(),
            to_char(p_entry_time, 'Day'),
            EXTRACT(MONTH FROM p_entry_time)::int,
            EXTRACT(YEAR FROM p_entry_time)::int,
            CASE
                WHEN EXTRACT(HOUR FROM p_entry_time) < 6 THEN 'Night'
                WHEN EXTRACT(HOUR FROM p_entry_time) < 12 THEN 'Morning'
                WHEN EXTRACT(HOUR FROM p_entry_time) < 18 THEN 'Afternoon'
                ELSE 'Evening'
            END
        );

        RETURN QUERY SELECT v_new_visit_id, 'created'::text, NULL::text;
    END IF;
EXCEPTION
    WHEN lock_not_available THEN
        -- Another transaction is modifying this visit, fail gracefully
        RAISE EXCEPTION 'Visit is being modified by another process';
END;
$$;

-- Update function comment
COMMENT ON FUNCTION public.upsert_location_visit IS
'Atomically creates or merges location visits with 7-minute merge window.
Handles open visits (NULL exit_time) by skipping calendar day check.
For closed visits, only merges if on the same calendar day.
Prevents duplicate visits by properly merging with existing open visits.';
