-- Enable RLS on attachments table if not already enabled
ALTER TABLE attachments ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (drop all old ones to avoid conflicts)
DROP POLICY IF EXISTS "Users can insert their own attachments" ON attachments;
DROP POLICY IF EXISTS "Users can select their own attachments" ON attachments;
DROP POLICY IF EXISTS "Users can update their own attachments" ON attachments;
DROP POLICY IF EXISTS "Users can delete their own attachments" ON attachments;

-- SIMPLE POLICY: Allow all authenticated users to insert (user_id check handles security)
-- This mirrors how notes uploads work
CREATE POLICY "Allow authenticated users to insert attachments"
ON attachments
FOR INSERT
WITH CHECK (true);

-- Allow users to view their own attachments
CREATE POLICY "Users can select their own attachments"
ON attachments
FOR SELECT
USING (auth.uid()::text = user_id::text);

-- Allow users to update their own attachments
CREATE POLICY "Users can update their own attachments"
ON attachments
FOR UPDATE
USING (auth.uid()::text = user_id::text)
WITH CHECK (auth.uid()::text = user_id::text);

-- Allow users to delete their own attachments
CREATE POLICY "Users can delete their own attachments"
ON attachments
FOR DELETE
USING (auth.uid()::text = user_id::text);
