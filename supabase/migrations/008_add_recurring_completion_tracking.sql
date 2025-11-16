-- Add columns to track recurring event completion history in Supabase
-- This allows the LLM to know the actual dates when recurring events occurred
-- (e.g., "when was my last haircut?" can be answered accurately)

ALTER TABLE tasks ADD COLUMN IF NOT EXISTS completed_occurrences TIMESTAMP[] DEFAULT '{}';
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS last_completion_date TIMESTAMP;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS completion_count INT DEFAULT 0;

-- Create index on last_completion_date for faster queries
CREATE INDEX IF NOT EXISTS idx_tasks_last_completion_date ON tasks(user_id, last_completion_date);

-- Add comment explaining the purpose
COMMENT ON COLUMN tasks.completed_occurrences IS 'Array of timestamps when this recurring event was completed. Used by LLM to answer questions about past occurrences.';
COMMENT ON COLUMN tasks.last_completion_date IS 'Denormalized field: timestamp of the most recent completion for quick access.';
COMMENT ON COLUMN tasks.completion_count IS 'Denormalized field: total number of times this recurring event has been completed.';
