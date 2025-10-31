-- Enable RLS on attachments table if not already enabled
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can insert their own attachments" ON attachments;
DROP POLICY IF EXISTS "Users can select their own attachments" ON attachments;
DROP POLICY IF EXISTS "Users can update their own attachments" ON attachments;
DROP POLICY IF EXISTS "Users can delete their own attachments" ON attachments;

-- Allow users to insert attachments for their own notes
CREATE POLICY "Users can insert their own attachments"
ON attachments
FOR INSERT
WITH CHECK (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1 FROM notes
    WHERE notes.id = attachments.note_id
    AND notes.user_id = auth.uid()
  )
);

-- Allow users to select their own attachments
CREATE POLICY "Users can select their own attachments"
ON attachments
FOR SELECT
USING (auth.uid() = user_id);

-- Allow users to update their own attachments
CREATE POLICY "Users can update their own attachments"
ON attachments
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Allow users to delete their own attachments
CREATE POLICY "Users can delete their own attachments"
ON attachments
FOR DELETE
USING (auth.uid() = user_id);
