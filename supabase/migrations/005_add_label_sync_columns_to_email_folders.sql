-- Add columns to email_folders table to support Gmail label syncing
ALTER TABLE email_folders
ADD COLUMN is_imported_label BOOLEAN DEFAULT FALSE,
ADD COLUMN gmail_label_id TEXT,
ADD COLUMN last_synced_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN sync_enabled BOOLEAN DEFAULT TRUE;

-- Create unique index for gmail_label_id (only for imported labels)
CREATE UNIQUE INDEX email_folders_gmail_label_id_user_unique
ON email_folders(user_id, gmail_label_id)
WHERE is_imported_label = TRUE;
