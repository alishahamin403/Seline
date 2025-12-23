-- Migration: Add custom_recurrence_days column to tasks table
-- This field stores the specific days of the week for custom recurring events
-- Stored as JSON array of day strings: ["monday", "wednesday", "friday"]

-- Add the custom_recurrence_days column if it doesn't exist
ALTER TABLE tasks
ADD COLUMN IF NOT EXISTS custom_recurrence_days TEXT DEFAULT NULL;

-- Add comment explaining the column
COMMENT ON COLUMN tasks.custom_recurrence_days IS 'JSON array of weekday strings for custom recurring tasks (e.g., ["monday", "wednesday", "friday"])';
