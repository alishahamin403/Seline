-- Run this command in your Supabase SQL Editor to add the missing column
ALTER TABLE saved_places ADD COLUMN user_cuisine text;

-- Optional: Add a comment
COMMENT ON COLUMN saved_places.user_cuisine IS 'User-selected cuisine preference for the location';
