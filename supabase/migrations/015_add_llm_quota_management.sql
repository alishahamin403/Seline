-- Migration: Add LLM quota management and API key support
-- This enables multi-tenant LLM usage with fair resource allocation

-- Add LLM provider and quota fields to user_profiles
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS llm_provider TEXT DEFAULT 'gemini',
ADD COLUMN IF NOT EXISTS bring_own_key BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS encrypted_api_key TEXT,
ADD COLUMN IF NOT EXISTS subscription_tier TEXT DEFAULT 'free',
ADD COLUMN IF NOT EXISTS monthly_quota_tokens INTEGER DEFAULT 100000,  -- 100k tokens/month for free
ADD COLUMN IF NOT EXISTS quota_used_this_month INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS quota_reset_date TIMESTAMP DEFAULT NOW() + INTERVAL '1 month';

-- API usage tracking table (detailed logs)
CREATE TABLE IF NOT EXISTS llm_usage_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,

    -- Request details
    provider TEXT NOT NULL,  -- 'gemini', 'openai', 'claude'
    model TEXT NOT NULL,     -- 'gemini-1.5-flash', 'gpt-4o-mini', etc.
    operation_type TEXT,     -- 'search', 'email_summary', 'chat', 'quick_note'

    -- Token usage
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    total_tokens INTEGER GENERATED ALWAYS AS (input_tokens + output_tokens) STORED,

    -- Cost calculation (USD)
    input_cost DECIMAL(10, 8),
    output_cost DECIMAL(10, 8),
    total_cost DECIMAL(10, 8) GENERATED ALWAYS AS (input_cost + output_cost) STORED,

    -- Performance metrics
    latency_ms INTEGER,
    api_key_used TEXT,  -- Which key from the pool was used (hashed)

    -- Metadata
    created_at TIMESTAMP DEFAULT NOW(),
    request_metadata JSONB  -- Store additional context
);

-- Indexes for fast queries
CREATE INDEX idx_llm_usage_user_date ON llm_usage_logs(user_id, created_at DESC);
CREATE INDEX idx_llm_usage_provider ON llm_usage_logs(provider, created_at DESC);
CREATE INDEX idx_llm_usage_operation ON llm_usage_logs(operation_type, created_at DESC);

-- RLS policies
ALTER TABLE llm_usage_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own usage logs"
    ON llm_usage_logs FOR SELECT
    USING (auth.uid() = user_id);

-- Function to check if user has quota remaining
CREATE OR REPLACE FUNCTION check_user_quota(p_user_id UUID, p_tokens_needed INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    v_profile RECORD;
    v_has_quota BOOLEAN;
BEGIN
    -- Get user profile
    SELECT * INTO v_profile
    FROM user_profiles
    WHERE id = p_user_id;

    -- If user brings own key, always allow
    IF v_profile.bring_own_key THEN
        RETURN TRUE;
    END IF;

    -- Check if quota reset is needed
    IF v_profile.quota_reset_date < NOW() THEN
        -- Reset quota for new month
        UPDATE user_profiles
        SET quota_used_this_month = 0,
            quota_reset_date = NOW() + INTERVAL '1 month'
        WHERE id = p_user_id;

        v_profile.quota_used_this_month := 0;
    END IF;

    -- Check if user has enough quota
    v_has_quota := (v_profile.quota_used_this_month + p_tokens_needed) <= v_profile.monthly_quota_tokens;

    RETURN v_has_quota;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to increment user quota usage
CREATE OR REPLACE FUNCTION increment_user_quota(p_user_id UUID, p_tokens_used INTEGER)
RETURNS VOID AS $$
BEGIN
    UPDATE user_profiles
    SET quota_used_this_month = quota_used_this_month + p_tokens_used
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- View for user quota status (useful for settings UI)
CREATE OR REPLACE VIEW user_quota_status AS
SELECT
    id AS user_id,
    subscription_tier,
    monthly_quota_tokens,
    quota_used_this_month,
    monthly_quota_tokens - quota_used_this_month AS quota_remaining,
    ROUND((quota_used_this_month::DECIMAL / monthly_quota_tokens::DECIMAL) * 100, 2) AS quota_used_percent,
    quota_reset_date,
    bring_own_key
FROM user_profiles;

-- RLS for quota status view
ALTER VIEW user_quota_status SET (security_invoker = true);

-- API key pool table (server-side only, NOT accessible to clients)
CREATE TABLE IF NOT EXISTS llm_api_keys (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    provider TEXT NOT NULL,  -- 'gemini', 'openai', 'claude'
    key_hash TEXT NOT NULL,  -- Hashed version for logging
    encrypted_key TEXT NOT NULL,  -- Encrypted actual key

    -- Rate limit tracking
    current_rpm INTEGER DEFAULT 0,
    max_rpm INTEGER NOT NULL,  -- e.g., 2000 for Gemini paid tier
    last_reset TIMESTAMP DEFAULT NOW(),

    -- Health status
    is_active BOOLEAN DEFAULT true,
    is_rate_limited BOOLEAN DEFAULT false,
    rate_limit_reset_at TIMESTAMP,

    -- Metrics
    total_requests INTEGER DEFAULT 0,
    total_tokens_processed BIGINT DEFAULT 0,
    error_count INTEGER DEFAULT 0,
    last_error TIMESTAMP,

    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- NO RLS on llm_api_keys - only accessible server-side
-- This table should only be accessed by Edge Functions, never by client

CREATE INDEX idx_llm_keys_provider_active ON llm_api_keys(provider, is_active, is_rate_limited);

-- Initialize with default quotas for subscription tiers
COMMENT ON COLUMN user_profiles.monthly_quota_tokens IS 'Free: 100k, Pro: 500k, Enterprise: 5M';
COMMENT ON COLUMN user_profiles.subscription_tier IS 'Options: free, pro, enterprise, unlimited';
