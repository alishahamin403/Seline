-- Add custom name columns for quick locations
-- This allows users to give custom nicknames to their saved quick locations

ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS location1_name TEXT,
ADD COLUMN IF NOT EXISTS location2_name TEXT,
ADD COLUMN IF NOT EXISTS location3_name TEXT,
ADD COLUMN IF NOT EXISTS location4_name TEXT;

-- Add comments to explain the columns
COMMENT ON COLUMN user_profiles.location1_name IS 'Custom nickname for quick location 1 (e.g., "Home", "My Office")';
COMMENT ON COLUMN user_profiles.location2_name IS 'Custom nickname for quick location 2';
COMMENT ON COLUMN user_profiles.location3_name IS 'Custom nickname for quick location 3';
COMMENT ON COLUMN user_profiles.location4_name IS 'Custom nickname for quick location 4';
