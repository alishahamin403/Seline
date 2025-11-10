-- Create saved_emails table to store full email content in custom folders
CREATE TABLE saved_emails (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email_folder_id UUID NOT NULL REFERENCES email_folders(id) ON DELETE CASCADE,
  gmail_message_id TEXT NOT NULL, -- Original Gmail message ID for reference
  subject TEXT NOT NULL,
  sender_name TEXT,
  sender_email TEXT NOT NULL,
  recipients TEXT[] DEFAULT ARRAY[]::TEXT[], -- Array of recipient emails
  cc_recipients TEXT[] DEFAULT ARRAY[]::TEXT[], -- Array of CC recipient emails
  body TEXT, -- Full HTML body of email
  snippet TEXT, -- Preview text
  timestamp TIMESTAMP WITH TIME ZONE NOT NULL, -- Original email date
  saved_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT saved_emails_unique_per_folder UNIQUE(user_id, email_folder_id, gmail_message_id)
);

-- Enable RLS
ALTER TABLE saved_emails ENABLE ROW LEVEL SECURITY;

-- RLS Policies for saved_emails
CREATE POLICY "Users can view their own saved emails"
ON saved_emails
FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own saved emails"
ON saved_emails
FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own saved emails"
ON saved_emails
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own saved emails"
ON saved_emails
FOR DELETE
USING (auth.uid() = user_id);

-- Create indexes for faster lookups
CREATE INDEX saved_emails_user_id_idx ON saved_emails(user_id);
CREATE INDEX saved_emails_folder_id_idx ON saved_emails(email_folder_id);
CREATE INDEX saved_emails_gmail_message_id_idx ON saved_emails(gmail_message_id);
CREATE INDEX saved_emails_timestamp_idx ON saved_emails(timestamp DESC);
