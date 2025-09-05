-- Seline Email App - Supabase Database Schema
-- Phase 2: Production Architecture with Core Data + Supabase Hybrid Storage
-- Created: 2025-08-28

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- Users table for authentication and profile data
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    name TEXT,
    profile_image_url TEXT,
    google_id TEXT UNIQUE,
    access_token_encrypted TEXT, -- Encrypted storage for security
    refresh_token_encrypted TEXT,
    token_expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_sync_at TIMESTAMPTZ,
    settings JSONB DEFAULT '{}',
    storage_quota_bytes BIGINT DEFAULT 104857600, -- 100MB default
    storage_used_bytes BIGINT DEFAULT 0
);

-- Create index on email for fast lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);
CREATE INDEX IF NOT EXISTS idx_users_last_sync ON users(last_sync_at);

-- Emails table for centralized email storage
CREATE TABLE IF NOT EXISTS emails (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    gmail_id TEXT NOT NULL,
    thread_id TEXT,
    subject TEXT NOT NULL,
    body TEXT NOT NULL,
    body_plain TEXT, -- Plain text version for better searching
    sender_name TEXT,
    sender_email TEXT NOT NULL,
    recipients JSONB NOT NULL DEFAULT '[]',
    date_received TIMESTAMPTZ NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    is_important BOOLEAN DEFAULT FALSE,
    is_promotional BOOLEAN DEFAULT FALSE,
    labels JSONB DEFAULT '[]',
    gmail_labels JSONB DEFAULT '[]', -- Original Gmail labels
    attachments_count INTEGER DEFAULT 0,
    attachments JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    synced_at TIMESTAMPTZ DEFAULT NOW(),
    search_vector TSVECTOR, -- For full-text search
    
    -- Ensure unique emails per user
    UNIQUE(user_id, gmail_id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_emails_user_id ON emails(user_id);
CREATE INDEX IF NOT EXISTS idx_emails_gmail_id ON emails(gmail_id);
CREATE INDEX IF NOT EXISTS idx_emails_thread_id ON emails(thread_id);
CREATE INDEX IF NOT EXISTS idx_emails_date_received ON emails(date_received DESC);
CREATE INDEX IF NOT EXISTS idx_emails_is_read ON emails(is_read);
CREATE INDEX IF NOT EXISTS idx_emails_is_important ON emails(is_important);
CREATE INDEX IF NOT EXISTS idx_emails_is_promotional ON emails(is_promotional);
CREATE INDEX IF NOT EXISTS idx_emails_sender_email ON emails(sender_email);
CREATE INDEX IF NOT EXISTS idx_emails_search_vector ON emails USING gin(search_vector);
CREATE INDEX IF NOT EXISTS idx_emails_subject_body ON emails USING gin((subject || ' ' || body) gin_trgm_ops);

-- Email attachments table (normalized for better querying)
CREATE TABLE IF NOT EXISTS email_attachments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email_id UUID NOT NULL REFERENCES emails(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    filename TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    size_bytes INTEGER NOT NULL DEFAULT 0,
    attachment_id TEXT, -- Gmail attachment ID
    content_url TEXT, -- If we store content separately
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attachments_email_id ON email_attachments(email_id);
CREATE INDEX IF NOT EXISTS idx_attachments_user_id ON email_attachments(user_id);
CREATE INDEX IF NOT EXISTS idx_attachments_mime_type ON email_attachments(mime_type);

-- Email categories for advanced filtering
CREATE TABLE IF NOT EXISTS email_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category_type TEXT NOT NULL, -- 'system', 'custom', 'ai_generated'
    color TEXT DEFAULT '#3B82F6',
    rules JSONB DEFAULT '{}', -- Auto-categorization rules
    email_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(user_id, name)
);

CREATE INDEX IF NOT EXISTS idx_categories_user_id ON email_categories(user_id);
CREATE INDEX IF NOT EXISTS idx_categories_type ON email_categories(category_type);

-- Sync status tracking for reliable synchronization
CREATE TABLE IF NOT EXISTS sync_status (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sync_type TEXT NOT NULL, -- 'gmail_fetch', 'gmail_push', 'full_sync', 'incremental_sync'
    status TEXT NOT NULL, -- 'pending', 'running', 'completed', 'failed', 'cancelled'
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    last_email_date TIMESTAMPTZ,
    emails_processed INTEGER DEFAULT 0,
    emails_added INTEGER DEFAULT 0,
    emails_updated INTEGER DEFAULT 0,
    emails_failed INTEGER DEFAULT 0,
    error_message TEXT,
    error_details JSONB,
    metadata JSONB DEFAULT '{}',
    
    UNIQUE(user_id, sync_type, started_at)
);

CREATE INDEX IF NOT EXISTS idx_sync_status_user_id ON sync_status(user_id);
CREATE INDEX IF NOT EXISTS idx_sync_status_type ON sync_status(sync_type);
CREATE INDEX IF NOT EXISTS idx_sync_status_status ON sync_status(status);
CREATE INDEX IF NOT EXISTS idx_sync_status_started_at ON sync_status(started_at DESC);

-- Email search analytics (for improving search)
CREATE TABLE IF NOT EXISTS search_analytics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    search_query TEXT NOT NULL,
    results_count INTEGER NOT NULL,
    clicked_email_id UUID REFERENCES emails(id) ON DELETE SET NULL,
    search_duration_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_search_analytics_user_id ON search_analytics(user_id);
CREATE INDEX IF NOT EXISTS idx_search_analytics_created_at ON search_analytics(created_at DESC);

-- Function to update search vector
CREATE OR REPLACE FUNCTION update_email_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := 
        setweight(to_tsvector('english', COALESCE(NEW.subject, '')), 'A') ||
        setweight(to_tsvector('english', COALESCE(NEW.sender_name, '')), 'B') ||
        setweight(to_tsvector('english', COALESCE(NEW.body_plain, NEW.body, '')), 'C');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update search vector
DROP TRIGGER IF EXISTS emails_search_vector_update ON emails;
CREATE TRIGGER emails_search_vector_update
    BEFORE INSERT OR UPDATE OF subject, body, body_plain, sender_name
    ON emails
    FOR EACH ROW
    EXECUTE FUNCTION update_email_search_vector();

-- Function to update timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at timestamps
CREATE TRIGGER users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER emails_updated_at BEFORE UPDATE ON emails FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER categories_updated_at BEFORE UPDATE ON email_categories FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Comments for documentation
COMMENT ON TABLE users IS 'User accounts and authentication data';
COMMENT ON TABLE emails IS 'Centralized email storage with full-text search capabilities';
COMMENT ON TABLE email_attachments IS 'Normalized email attachments for better querying';
COMMENT ON TABLE email_categories IS 'User-defined and AI-generated email categories';
COMMENT ON TABLE sync_status IS 'Sync operation tracking and error handling';
COMMENT ON TABLE search_analytics IS 'Search usage analytics for improving user experience';

COMMENT ON COLUMN emails.search_vector IS 'Full-text search vector with weighted fields';
COMMENT ON COLUMN emails.body_plain IS 'Plain text version of email body for better search indexing';
COMMENT ON COLUMN sync_status.metadata IS 'Additional sync metadata (quotas, API limits, etc.)';