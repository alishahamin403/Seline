-- Migration: Change from monthly to daily quota (1M tokens per day)
-- This provides more generous daily limits with daily resets

-- Add daily quota columns
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS daily_quota_tokens INTEGER DEFAULT 1000000,  -- 1M tokens per day
ADD COLUMN IF NOT EXISTS quota_used_today INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS quota_reset_time TIMESTAMP DEFAULT (DATE_TRUNC('day', NOW()) + INTERVAL '1 day');

-- Update existing users to have daily quota
UPDATE user_profiles
SET 
    daily_quota_tokens = 1000000,  -- 1M tokens per day
    quota_used_today = 0,
    quota_reset_time = DATE_TRUNC('day', NOW()) + INTERVAL '1 day'
WHERE daily_quota_tokens IS NULL OR quota_used_today IS NULL;

-- Function to check if user has daily quota remaining (returns has_quota and reset_time)
CREATE OR REPLACE FUNCTION check_deepseek_quota(p_user_id UUID, p_tokens_needed INTEGER)
RETURNS TABLE(has_quota BOOLEAN, reset_time TIMESTAMP) AS $$
DECLARE
    v_profile RECORD;
    v_has_quota BOOLEAN;
    v_reset_time TIMESTAMP;
BEGIN
    SELECT * INTO v_profile
    FROM user_profiles
    WHERE id = p_user_id;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NOW()::TIMESTAMP;
        RETURN;
    END IF;

    -- Check if daily quota reset is needed (reset at midnight)
    v_reset_time = DATE_TRUNC('day', NOW()) + INTERVAL '1 day';
    
    IF v_profile.quota_reset_time IS NULL OR v_profile.quota_reset_time < NOW() THEN
        -- Reset daily quota
        UPDATE user_profiles
        SET 
            quota_used_today = 0,
            quota_reset_time = v_reset_time
        WHERE id = p_user_id;
        v_profile.quota_used_today := 0;
    ELSE
        v_reset_time := v_profile.quota_reset_time;
    END IF;

    -- Use daily_quota_tokens if available, fallback to monthly_quota_tokens for backward compatibility
    v_has_quota := (v_profile.quota_used_today + p_tokens_needed) <= COALESCE(v_profile.daily_quota_tokens, v_profile.monthly_quota_tokens);
    
    RETURN QUERY SELECT v_has_quota, v_reset_time;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to increment daily quota usage
CREATE OR REPLACE FUNCTION increment_deepseek_quota(p_user_id UUID, p_tokens_used INTEGER)
RETURNS VOID AS $$
BEGIN
    -- Check if reset is needed first
    UPDATE user_profiles
    SET 
        quota_used_today = 0,
        quota_reset_time = DATE_TRUNC('day', NOW()) + INTERVAL '1 day'
    WHERE id = p_user_id 
      AND (quota_reset_time IS NULL OR quota_reset_time < NOW());
    
    -- Increment usage
    UPDATE user_profiles
    SET quota_used_today = quota_used_today + p_tokens_used
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update quota status view to show daily quota
CREATE OR REPLACE VIEW deepseek_quota_status AS
SELECT
    id AS user_id,
    subscription_tier,
    llm_provider,
    COALESCE(daily_quota_tokens, monthly_quota_tokens) AS quota_tokens,
    COALESCE(quota_used_today, quota_used_this_month) AS quota_used,
    COALESCE(daily_quota_tokens, monthly_quota_tokens) - COALESCE(quota_used_today, quota_used_this_month) AS quota_remaining,
    ROUND((COALESCE(quota_used_today, quota_used_this_month)::DECIMAL / COALESCE(daily_quota_tokens, monthly_quota_tokens)::DECIMAL) * 100, 2) AS quota_used_percent,
    COALESCE(quota_reset_time, quota_reset_date) AS quota_reset_at
FROM user_profiles;

