-- Migration: Increase daily quota from 1M to 2M tokens per day
-- This provides more capacity for email summaries and other AI operations
-- Also handles case where daily quota columns don't exist yet (if migration 017 wasn't applied)

-- Add daily quota columns if they don't exist (from migration 017)
ALTER TABLE user_profiles
ADD COLUMN IF NOT EXISTS daily_quota_tokens INTEGER DEFAULT 2000000,  -- 2M tokens per day
ADD COLUMN IF NOT EXISTS quota_used_today INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS quota_reset_time TIMESTAMP DEFAULT (DATE_TRUNC('day', NOW()) + INTERVAL '1 day');

-- Update default daily quota to 2M tokens (for new users)
ALTER TABLE user_profiles
ALTER COLUMN daily_quota_tokens SET DEFAULT 2000000;  -- 2M tokens per day

-- Update existing users to have 2M daily quota
-- If they have 1M, update to 2M. If NULL (new column), set to 2M.
UPDATE user_profiles
SET 
    daily_quota_tokens = 2000000,  -- 2M tokens per day
    quota_used_today = COALESCE(quota_used_today, 0),
    quota_reset_time = COALESCE(quota_reset_time, DATE_TRUNC('day', NOW()) + INTERVAL '1 day')
WHERE daily_quota_tokens IS NULL 
   OR daily_quota_tokens = 1000000 
   OR quota_used_today IS NULL 
   OR quota_reset_time IS NULL;

-- CRITICAL: Recreate the check_deepseek_quota function to use daily quota (not monthly)
-- The function in the database might still be using old monthly quota logic
-- First drop the old function if it exists (it might have different return type)
DROP FUNCTION IF EXISTS check_deepseek_quota(uuid, integer);

-- Now create the new function with daily quota logic
CREATE FUNCTION check_deepseek_quota(p_user_id UUID, p_tokens_needed INTEGER)
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

-- Also ensure increment_deepseek_quota function uses daily quota
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
    
    -- Increment daily usage
    UPDATE user_profiles
    SET quota_used_today = quota_used_today + p_tokens_used
    WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
