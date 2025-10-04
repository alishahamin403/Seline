-- Add is_draft column to notes table
ALTER TABLE notes ADD COLUMN IF NOT EXISTS is_draft BOOLEAN DEFAULT false;

-- Update existing notes to not be drafts
UPDATE notes SET is_draft = false WHERE is_draft IS NULL;
