-- Location Tracking V2: Session Support & Smart Geofencing
-- Adds session-based visit tracking to handle app restarts and GPS signal loss
-- Migration: Fresh start (delete existing visits), preserve saved_places

-- Drop existing location_visits table (fresh start)
DROP TABLE IF EXISTS location_visits CASCADE;

-- Create new location_visits table with session support
CREATE TABLE location_visits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    saved_place_id UUID NOT NULL REFERENCES saved_places(id) ON DELETE CASCADE,
    session_id UUID NOT NULL DEFAULT gen_random_uuid(), -- Groups related visits (app restart, GPS loss)
    entry_time TIMESTAMP NOT NULL,
    exit_time TIMESTAMP NULL,
    duration_minutes INT NULL,
    day_of_week VARCHAR(10) NOT NULL,
    time_of_day VARCHAR(10) NOT NULL,
    month INT NOT NULL,
    year INT NOT NULL,
    confidence_score FLOAT DEFAULT 1.0, -- 1.0 (certain), 0.95, 0.85 (app restart/GPS)
    merge_reason VARCHAR(50) NULL, -- "app_restart", "gps_reconnect", "quick_return"
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX idx_location_visits_user_id ON location_visits(user_id);
CREATE INDEX idx_location_visits_saved_place_id ON location_visits(saved_place_id);
CREATE INDEX idx_location_visits_session_id ON location_visits(session_id); -- NEW: For session grouping
CREATE INDEX idx_location_visits_user_place ON location_visits(user_id, saved_place_id);
CREATE INDEX idx_location_visits_entry_time ON location_visits(entry_time DESC);
CREATE INDEX idx_location_visits_exit_time_null ON location_visits(exit_time) WHERE exit_time IS NULL; -- For finding incomplete visits

-- Add custom_geofence_radius to saved_places table (optional user override)
ALTER TABLE saved_places
ADD COLUMN IF NOT EXISTS custom_geofence_radius FLOAT NULL; -- In meters, optional

-- Create a migration version flag table to track if v2 migration has been applied
CREATE TABLE IF NOT EXISTS schema_version (
    id INT PRIMARY KEY,
    version VARCHAR(50) NOT NULL,
    applied_at TIMESTAMP DEFAULT NOW()
);

-- Mark v2 migration as applied
INSERT INTO schema_version (id, version) VALUES (1, '2.0_session_tracking')
ON CONFLICT DO NOTHING;

-- Enable RLS on location_visits (users can only see their own visits)
ALTER TABLE location_visits ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can see only their own visits
CREATE POLICY "Users can view their own visits" ON location_visits
    FOR SELECT USING (auth.uid() = user_id);

-- RLS Policy: Users can create visits for their own places
CREATE POLICY "Users can insert their own visits" ON location_visits
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- RLS Policy: Users can update their own visits
CREATE POLICY "Users can update their own visits" ON location_visits
    FOR UPDATE USING (auth.uid() = user_id);

-- RLS Policy: Users can delete their own visits
CREATE POLICY "Users can delete their own visits" ON location_visits
    FOR DELETE USING (auth.uid() = user_id);
