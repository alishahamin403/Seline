-- Seline Email App - Row Level Security Policies
-- Ensures users can only access their own data
-- Created: 2025-08-28

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE emails ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE sync_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE search_analytics ENABLE ROW LEVEL SECURITY;

-- Users table policies
-- Users can view and update their own profile
CREATE POLICY "Users can view own profile" ON users
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
    FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON users
    FOR INSERT WITH CHECK (auth.uid() = id);

-- Emails table policies
-- Users can only access their own emails
CREATE POLICY "Users can view own emails" ON emails
    FOR SELECT USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can insert own emails" ON emails
    FOR INSERT WITH CHECK (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can update own emails" ON emails
    FOR UPDATE USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can delete own emails" ON emails
    FOR DELETE USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

-- Email attachments policies
-- Users can only access attachments for their own emails
CREATE POLICY "Users can view own email attachments" ON email_attachments
    FOR SELECT USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can insert own email attachments" ON email_attachments
    FOR INSERT WITH CHECK (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can update own email attachments" ON email_attachments
    FOR UPDATE USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can delete own email attachments" ON email_attachments
    FOR DELETE USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

-- Email categories policies
-- Users can only access their own categories
CREATE POLICY "Users can view own categories" ON email_categories
    FOR SELECT USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can insert own categories" ON email_categories
    FOR INSERT WITH CHECK (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can update own categories" ON email_categories
    FOR UPDATE USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can delete own categories" ON email_categories
    FOR DELETE USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

-- Sync status policies
-- Users can only access their own sync status
CREATE POLICY "Users can view own sync status" ON sync_status
    FOR SELECT USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can insert own sync status" ON sync_status
    FOR INSERT WITH CHECK (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can update own sync status" ON sync_status
    FOR UPDATE USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

-- Search analytics policies
-- Users can only access their own search analytics
CREATE POLICY "Users can view own search analytics" ON search_analytics
    FOR SELECT USING (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

CREATE POLICY "Users can insert own search analytics" ON search_analytics
    FOR INSERT WITH CHECK (
        user_id IN (
            SELECT id FROM users WHERE auth.uid() = id
        )
    );

-- Grant permissions to authenticated users
-- These grants allow authenticated users to access tables (RLS policies control what they can see/modify)
GRANT ALL ON users TO authenticated;
GRANT ALL ON emails TO authenticated;
GRANT ALL ON email_attachments TO authenticated;
GRANT ALL ON email_categories TO authenticated;
GRANT ALL ON sync_status TO authenticated;
GRANT ALL ON search_analytics TO authenticated;

-- Grant usage on sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Comments for documentation
COMMENT ON POLICY "Users can view own profile" ON users IS 'Allow users to view their own profile data';
COMMENT ON POLICY "Users can view own emails" ON emails IS 'Restrict email access to the authenticated user only';
COMMENT ON POLICY "Users can view own email attachments" ON email_attachments IS 'Restrict attachment access to the authenticated user only';
COMMENT ON POLICY "Users can view own categories" ON email_categories IS 'Restrict category access to the authenticated user only';
COMMENT ON POLICY "Users can view own sync status" ON sync_status IS 'Restrict sync status access to the authenticated user only';
COMMENT ON POLICY "Users can view own search analytics" ON search_analytics IS 'Restrict search analytics access to the authenticated user only';