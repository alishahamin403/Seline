-- Add ai_summary column to saved_emails table for storing AI-generated email summaries
ALTER TABLE saved_emails ADD COLUMN ai_summary TEXT;

-- Create index on ai_summary for faster queries
CREATE INDEX saved_emails_ai_summary_idx ON saved_emails(ai_summary) WHERE ai_summary IS NOT NULL;
