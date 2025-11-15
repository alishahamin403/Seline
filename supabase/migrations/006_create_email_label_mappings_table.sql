-- Create email_label_mappings table to track Gmail label -> Seline folder relationships
CREATE TABLE email_label_mappings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  gmail_label_id TEXT NOT NULL,
  gmail_label_name TEXT NOT NULL,
  folder_id UUID NOT NULL REFERENCES email_folders(id) ON DELETE CASCADE,
  gmail_label_color TEXT, -- Store Gmail label color (backgroundColor)
  last_synced_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  sync_status TEXT DEFAULT 'active' CHECK (sync_status IN ('active', 'archived', 'deleted')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT email_label_mappings_unique UNIQUE(user_id, gmail_label_id)
);

-- Enable RLS
ALTER TABLE email_label_mappings ENABLE ROW LEVEL SECURITY;

-- RLS Policies for email_label_mappings
CREATE POLICY "Users can view their own label mappings"
ON email_label_mappings
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own label mappings"
ON email_label_mappings
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own label mappings"
ON email_label_mappings
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own label mappings"
ON email_label_mappings
FOR DELETE
USING (auth.uid() = user_id);

-- Create indexes for faster lookups
CREATE INDEX email_label_mappings_user_id_idx ON email_label_mappings(user_id);
CREATE INDEX email_label_mappings_gmail_label_id_idx ON email_label_mappings(gmail_label_id);
CREATE INDEX email_label_mappings_folder_id_idx ON email_label_mappings(folder_id);
CREATE INDEX email_label_mappings_sync_status_idx ON email_label_mappings(sync_status);
