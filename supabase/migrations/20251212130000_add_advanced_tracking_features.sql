-- Migration: Add Advanced Tracking Features
-- Adds support for motion validation, signal quality tracking, adaptive thresholds,
-- WiFi fingerprinting, and user feedback

-- Add new columns to location_visits table for enhanced tracking
ALTER TABLE location_visits
ADD COLUMN IF NOT EXISTS signal_drops INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS motion_validated BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS stationary_percentage REAL DEFAULT 1.0,
ADD COLUMN IF NOT EXISTS wifi_matched BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_outlier BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_commute_stop BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS semantic_valid BOOLEAN DEFAULT TRUE;

-- Create table for learned location thresholds
CREATE TABLE IF NOT EXISTS location_thresholds (
    place_id UUID PRIMARY KEY REFERENCES saved_places(id) ON DELETE CASCADE,
    min_duration_minutes INTEGER DEFAULT 10,
    dwell_time_seconds INTEGER DEFAULT 180,
    learned_from_feedback BOOLEAN DEFAULT FALSE,
    feedback_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create table for WiFi fingerprints (helps indoor location accuracy)
CREATE TABLE IF NOT EXISTS location_wifi_fingerprints (
    place_id UUID REFERENCES saved_places(id) ON DELETE CASCADE,
    bssid TEXT NOT NULL,
    ssid TEXT,
    confidence REAL DEFAULT 1.0,
    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (place_id, bssid)
);

-- Create table for user feedback on visits
CREATE TABLE IF NOT EXISTS visit_feedback (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    visit_id UUID REFERENCES location_visits(id) ON DELETE CASCADE,
    feedback_type TEXT NOT NULL CHECK (feedback_type IN ('too_short', 'wrong_location', 'just_passing_by', 'incorrect_time', 'duplicate', 'correct')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_location_visits_signal_quality ON location_visits(signal_drops) WHERE signal_drops > 0;
CREATE INDEX IF NOT EXISTS idx_location_visits_outliers ON location_visits(is_outlier) WHERE is_outlier = TRUE;
CREATE INDEX IF NOT EXISTS idx_location_visits_commute_stops ON location_visits(is_commute_stop) WHERE is_commute_stop = TRUE;
CREATE INDEX IF NOT EXISTS idx_wifi_fingerprints_place ON location_wifi_fingerprints(place_id);
CREATE INDEX IF NOT EXISTS idx_visit_feedback_user ON visit_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_visit_feedback_type ON visit_feedback(feedback_type);

-- Add RLS policies for new tables
ALTER TABLE location_thresholds ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_wifi_fingerprints ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_feedback ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own location thresholds
CREATE POLICY location_thresholds_select ON location_thresholds
    FOR SELECT USING (
        place_id IN (SELECT id FROM saved_places WHERE user_id = auth.uid())
    );

CREATE POLICY location_thresholds_insert ON location_thresholds
    FOR INSERT WITH CHECK (
        place_id IN (SELECT id FROM saved_places WHERE user_id = auth.uid())
    );

CREATE POLICY location_thresholds_update ON location_thresholds
    FOR UPDATE USING (
        place_id IN (SELECT id FROM saved_places WHERE user_id = auth.uid())
    );

-- Policy: Users can only see their own WiFi fingerprints
CREATE POLICY wifi_fingerprints_select ON location_wifi_fingerprints
    FOR SELECT USING (
        place_id IN (SELECT id FROM saved_places WHERE user_id = auth.uid())
    );

CREATE POLICY wifi_fingerprints_insert ON location_wifi_fingerprints
    FOR INSERT WITH CHECK (
        place_id IN (SELECT id FROM saved_places WHERE user_id = auth.uid())
    );

CREATE POLICY wifi_fingerprints_update ON location_wifi_fingerprints
    FOR UPDATE USING (
        place_id IN (SELECT id FROM saved_places WHERE user_id = auth.uid())
    );

-- Policy: Users can only manage their own feedback
CREATE POLICY visit_feedback_select ON visit_feedback
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY visit_feedback_insert ON visit_feedback
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- Create function to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_location_thresholds_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update timestamp
CREATE TRIGGER location_thresholds_updated_at
    BEFORE UPDATE ON location_thresholds
    FOR EACH ROW
    EXECUTE FUNCTION update_location_thresholds_updated_at();

-- Comment on tables for documentation
COMMENT ON TABLE location_thresholds IS 'Stores learned minimum duration and dwell time thresholds per location based on user patterns and feedback';
COMMENT ON TABLE location_wifi_fingerprints IS 'WiFi network fingerprints for indoor location accuracy validation';
COMMENT ON TABLE visit_feedback IS 'User feedback on visit accuracy for system learning and improvement';
