-- Create email_folders table for custom email folder organization
CREATE TABLE email_folders (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT DEFAULT '#84cae9', -- Default color (matching notes system)
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT email_folders_name_user_unique UNIQUE(user_id, name)
);

-- Enable RLS
ALTER TABLE email_folders ENABLE ROW LEVEL SECURITY;

-- RLS Policies for email_folders
CREATE POLICY "Users can view their own folders"
ON email_folders
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own folders"
ON email_folders
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own folders"
ON email_folders
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own folders"
ON email_folders
FOR DELETE
USING (auth.uid() = user_id);

-- Create index for faster lookups
CREATE INDEX email_folders_user_id_idx ON email_folders(user_id);
