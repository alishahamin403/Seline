-- View to monitor potential duplicates after cleanup
-- Query this regularly to ensure no new duplicates are created

CREATE OR REPLACE VIEW visit_health_check AS
SELECT
    user_id,
    saved_place_id,
    DATE(entry_time) as visit_date,
    COUNT(*) as visit_count,
    COUNT(*) FILTER (WHERE exit_time IS NULL) as open_visits,
    ARRAY_AGG(id ORDER BY entry_time) as visit_ids,
    ARRAY_AGG(entry_time ORDER BY entry_time) as entry_times,
    ARRAY_AGG(exit_time ORDER BY entry_time) as exit_times
FROM location_visits
GROUP BY user_id, saved_place_id, DATE(entry_time)
HAVING COUNT(*) > 3  -- Flag days with >3 visits to same place
ORDER BY visit_count DESC;

-- Grant access to authenticated users
GRANT SELECT ON visit_health_check TO authenticated;
