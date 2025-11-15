-- Add gmail_label_ids to saved_emails table to track which labels contain each email
ALTER TABLE saved_emails
ADD COLUMN gmail_label_ids TEXT[] DEFAULT ARRAY[]::TEXT[];

-- Create index for faster lookups by label ID
CREATE INDEX saved_emails_gmail_label_ids_idx ON saved_emails USING GIN(gmail_label_ids);
