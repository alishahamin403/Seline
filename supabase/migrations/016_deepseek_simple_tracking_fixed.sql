-- Migration: Simple DeepSeek usage tracking
-- No rate limiting needed (DeepSeek has no rate limits!)
-- Just quota management and cost tracking

-- Add DeepSeek-specific fields to user_profiles
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS llm_provider TEXT DEFAULT 'deepseek',
ADD COLUMN IF NOT EXISTS subscription_tier TEXT DEFAULT 'free',
ADD COLUMN IF NOT EXISTS monthly_quota_tokens INTEGER DEFAULT 100000,
ADD COLUMN IF NOT EXISTS quota_used_this_month INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS quota_reset_date TIMESTAMP DEFAULT NOW() + INTERVAL '1 month';

-- Simple usage tracking table
CREATE TABLE IF NOT EXISTS deepseek_usage_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    model TEXT NOT NULL DEFAULT 'deepseek-chat',
    operation_type TEXT,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    total_tokens INTEGER GENERATED ALWAYS AS (input_tokens + output_tokens) STORED,
    cache_hit_tokens INTEGER DEFAULT 0,
    cache_miss_tokens INTEGER DEFAULT 0,
    input_cost DECIMAL(10, 8),
    output_cost DECIMAL(10, 8),
    cache_savings DECIMAL(10, 8) DEFAULT 0,
    total_cost DECIMAL(10, 8) GENERATED ALWAYS AS (input_cost + output_cost) STORED,
    latency_ms INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    request_metadata JSONB
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_deepseek_usage_user_date ON deepseek_usage_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_deepseek_usage_operation ON deepseek_usage_logs(operation_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_deepseek_usage_cost ON deepseek_usage_logs(total_cost DESC);

-- RLS policies
ALTER TABLE deepseek_usage_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own usage logs" ON deepseek_usage_logs;
CREATE POLICY "Users can view their own usage logs"
    ON deepseek_usage_logs FOR SELECT
    USING (auth.uid() = user_id);

-- Function to check if user has quota remaining
CREATE OR REPLACE FUNCTION check_deepseek_quota(p_user_id UUID, p_tokens_needed INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    v_profile RECORD;
    v_has_quota BOOLEAN;
BEGIN
    SELECT * INTO v_profile
    FROM user_profiles
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    IF v_profile.quota_reset_date < NOW() THEN
        UPDATE user_profiles
        SET quota_used_this_month = 0,
            quota_reset_date = NOW() + INTERVAL '1 month'
        WHERE id = p_user_id;
        v_profile.quota_used_this_month := 0;
    END IF;

    v_has_quota := (v_profile.quota_used_this_month + p_tokens_needed) <= v_profile.monthly_quota_tokens;
    RETURN v_has_quota;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to increment user quota usage
CREATE OR REPLACE FUNCTION increment_deepseek_quota(p_user_id UUID, p_tokens_used INTEGER)
RETURNS VOID AS $$
BEGIN
    UPDATE user_profiles
    SET quota_used_this_month = quota_used_this_month + p_tokens_used
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- View for user quota status
CREATE OR REPLACE VIEW deepseek_quota_status AS
SELECT
    id AS user_id,
    subscription_tier,
    llm_provider,
    monthly_quota_tokens,
    quota_used_this_month,
    monthly_quota_tokens - quota_used_this_month AS quota_remaining,
    ROUND((quota_used_this_month::DECIMAL / monthly_quota_tokens::DECIMAL) * 100, 2) AS quota_used_percent,
    quota_reset_date
FROM user_profiles;

-- View for cost analytics
CREATE OR REPLACE VIEW deepseek_cost_analytics AS
SELECT
    user_id,
    operation_type,
    COUNT(*) AS request_count,
    SUM(total_tokens) AS total_tokens,
    SUM(cache_hit_tokens) AS cached_tokens,
    ROUND(SUM(total_cost)::numeric, 6) AS total_cost_usd,
    ROUND(SUM(cache_savings)::numeric, 6) AS savings_from_cache,
    ROUND(AVG(latency_ms)::numeric, 0) AS avg_latency_ms,
    DATE_TRUNC('day', created_at) AS usage_date
FROM deepseek_usage_logs
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY user_id, operation_type, DATE_TRUNC('day', created_at);

-- Grant permissions
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON deepseek_quota_status TO authenticated;
GRANT SELECT ON deepseek_cost_analytics TO authenticated;
