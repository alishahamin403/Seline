-- Enable RLS policies for conversations table
-- Allow users to insert their own conversations
CREATE POLICY "Users can insert their own conversations"
ON conversations
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

-- Allow users to view their own conversations
CREATE POLICY "Users can view their own conversations"
ON conversations
FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

-- Allow users to update their own conversations
CREATE POLICY "Users can update their own conversations"
ON conversations
FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Allow users to delete their own conversations
CREATE POLICY "Users can delete their own conversations"
ON conversations
FOR DELETE
TO authenticated
USING (auth.uid() = user_id);
