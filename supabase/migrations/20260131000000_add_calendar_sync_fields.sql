-- Add calendar sync fields to tasks table
-- This enables saving iPhone calendar events to Supabase with full metadata

-- Add calendar-related columns
ALTER TABLE tasks
ADD COLUMN IF NOT EXISTS calendar_event_id text,
ADD COLUMN IF NOT EXISTS calendar_identifier text,
ADD COLUMN IF NOT EXISTS calendar_title text,
ADD COLUMN IF NOT EXISTS calendar_source_type text,
ADD COLUMN IF NOT EXISTS is_from_calendar boolean DEFAULT false;

-- Add index for efficient calendar event lookups
CREATE INDEX IF NOT EXISTS idx_tasks_calendar_event_id
ON tasks(user_id, calendar_event_id)
WHERE calendar_event_id IS NOT NULL;

-- Add index for calendar sync queries
CREATE INDEX IF NOT EXISTS idx_tasks_is_from_calendar
ON tasks(user_id, is_from_calendar)
WHERE is_from_calendar = true;

-- Add unique constraint to prevent duplicate calendar events
-- Same calendar event ID for the same user should only exist once
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_unique_calendar_event
ON tasks(user_id, calendar_event_id)
WHERE calendar_event_id IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN tasks.calendar_event_id IS 'EventKit event identifier from iPhone calendar';
COMMENT ON COLUMN tasks.calendar_identifier IS 'Calendar identifier (EKCalendar.calendarIdentifier)';
COMMENT ON COLUMN tasks.calendar_title IS 'Name of the calendar (e.g., "Work", "Personal", "Gmail")';
COMMENT ON COLUMN tasks.calendar_source_type IS 'Source type: Local, CalDAV, Exchange, Subscribed, Birthdays';
COMMENT ON COLUMN tasks.is_from_calendar IS 'True if this task was synced from iPhone calendar';
