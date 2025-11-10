-- Create saved_email_attachments table for storing attachment metadata and storage paths
CREATE TABLE saved_email_attachments (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  saved_email_id UUID NOT NULL REFERENCES saved_emails(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  file_size INT8 NOT NULL,
  mime_type TEXT,
  storage_path TEXT NOT NULL, -- Path in Supabase Storage (email-attachments bucket)
  uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT saved_email_attachments_unique_per_email UNIQUE(saved_email_id, file_name)
);

-- Enable RLS
ALTER TABLE saved_email_attachments ENABLE ROW LEVEL SECURITY;

-- RLS Policies for saved_email_attachments
-- Note: Access is controlled through saved_emails foreign key
CREATE POLICY "Users can view attachments for their own emails"
ON saved_email_attachments
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM saved_emails
    WHERE saved_emails.id = saved_email_attachments.saved_email_id
    AND saved_emails.user_id = auth.uid()
  )
);

CREATE POLICY "Users can create attachments for their own emails"
ON saved_email_attachments
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM saved_emails
    WHERE saved_emails.id = saved_email_attachments.saved_email_id
    AND saved_emails.user_id = auth.uid()
  )
);

CREATE POLICY "Users can update attachments for their own emails"
ON saved_email_attachments
FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM saved_emails
    WHERE saved_emails.id = saved_email_attachments.saved_email_id
    AND saved_emails.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM saved_emails
    WHERE saved_emails.id = saved_email_attachments.saved_email_id
    AND saved_emails.user_id = auth.uid()
  )
);

CREATE POLICY "Users can delete attachments for their own emails"
ON saved_email_attachments
FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM saved_emails
    WHERE saved_emails.id = saved_email_attachments.saved_email_id
    AND saved_emails.user_id = auth.uid()
  )
);

-- Create indexes for faster lookups
CREATE INDEX saved_email_attachments_saved_email_id_idx ON saved_email_attachments(saved_email_id);
