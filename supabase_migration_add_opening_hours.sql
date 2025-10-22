-- Migration: Add opening_hours and is_open_now columns to saved_places table
-- Run this migration in Supabase SQL editor or via Supabase CLI

ALTER TABLE saved_places
ADD COLUMN IF NOT EXISTS opening_hours text,
ADD COLUMN IF NOT EXISTS is_open_now boolean;

-- Add comments to describe the new columns
COMMENT ON COLUMN saved_places.opening_hours IS 'Base64 encoded JSON array of opening hours weekday descriptions';
COMMENT ON COLUMN saved_places.is_open_now IS 'Whether the place is currently open (based on opening hours)';
