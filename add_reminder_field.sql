-- Add reminder_time column to tasks table
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS reminder_time TEXT;

-- Add comment to describe the column
COMMENT ON COLUMN tasks.reminder_time IS 'When to remind the user: 15min, 1hour, 3hours, 1day, or none';