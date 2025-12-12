-- Fix DeepSeek quota check function to return proper structure
-- The edge function expects has_quota and reset_time fields

-- Add daily quota tracking (in addition to monthly)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS daily_quota_tokens INTEGER DEFAULT 2000000, -- 2M tokens per day
ADD COLUMN IF NOT EXISTS quota_used_today INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS daily_quota_reset_date TIMESTAMP DEFAULT date_trunc('day', NOW()) + INTERVAL '1 day';

-- Drop the old function
DROP FUNCTION IF EXISTS check_deepseek_quota(UUID, INTEGER);

-- Create new function that returns a table with has_quota and reset_time
CREATE OR REPLACE FUNCTION check_deepseek_quota(p_user_id UUID, p_tokens_needed INTEGER)
RETURNS TABLE(has_quota BOOLEAN, reset_time TIMESTAMP) AS $$
DECLARE
    v_profile RECORD;
    v_has_quota BOOLEAN;
    v_reset_time TIMESTAMP;
BEGIN
    -- Get user profile
    SELECT * INTO v_profile
    FROM user_profiles
    WHERE id = p_user_id;

    -- If no profile found, return false
    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NOW() + INTERVAL '1 day';
        RETURN;
    END IF;

    -- Check if we need to reset daily quota
    IF v_profile.daily_quota_reset_date IS NULL OR v_profile.daily_quota_reset_date < NOW() THEN
        -- Reset daily quota
        UPDATE user_profiles
        SET quota_used_today = 0,
            daily_quota_reset_date = date_trunc('day', NOW()) + INTERVAL '1 day'
        WHERE id = p_user_id;

        v_profile.quota_used_today := 0;
        v_profile.daily_quota_reset_date := date_trunc('day', NOW()) + INTERVAL '1 day';
    END IF;

    -- Check if we need to reset monthly quota
    IF v_profile.quota_reset_date IS NULL OR v_profile.quota_reset_date < NOW() THEN
        UPDATE user_profiles
        SET quota_used_this_month = 0,
            quota_reset_date = NOW() + INTERVAL '1 month'
        WHERE id = p_user_id;

        v_profile.quota_used_this_month := 0;
    END IF;

    -- Check both daily and monthly quotas
    v_has_quota := (v_profile.quota_used_today + p_tokens_needed) <= v_profile.daily_quota_tokens
                   AND (v_profile.quota_used_this_month + p_tokens_needed) <= v_profile.monthly_quota_tokens;

    v_reset_time := v_profile.daily_quota_reset_date;

    -- Return result as table
    RETURN QUERY SELECT v_has_quota, v_reset_time;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update increment function to track both daily and monthly usage
DROP FUNCTION IF EXISTS increment_deepseek_quota(UUID, INTEGER);

CREATE OR REPLACE FUNCTION increment_deepseek_quota(p_user_id UUID, p_tokens_used INTEGER)
RETURNS VOID AS $$
BEGIN
    UPDATE user_profiles
    SET quota_used_today = quota_used_today + p_tokens_used,
        quota_used_this_month = quota_used_this_month + p_tokens_used
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update the quota status view to include daily quotas
DROP VIEW IF EXISTS deepseek_quota_status;

CREATE OR REPLACE VIEW deepseek_quota_status AS
SELECT
    id AS user_id,
    subscription_tier,
    llm_provider,
    -- Monthly quota (backward compatibility)
    monthly_quota_tokens,
    quota_used_this_month,
    monthly_quota_tokens - quota_used_this_month AS monthly_quota_remaining,
    -- Daily quota (new)
    daily_quota_tokens AS quota_tokens,
    quota_used_today AS quota_used,
    daily_quota_tokens - quota_used_today AS quota_remaining,
    ROUND((quota_used_today::DECIMAL / daily_quota_tokens::DECIMAL) * 100, 2) AS quota_used_percent,
    daily_quota_reset_date AS quota_reset_at,
    -- Keep monthly fields for backward compatibility
    quota_reset_date
FROM user_profiles;

-- Grant permissions
GRANT SELECT ON deepseek_quota_status TO authenticated;
