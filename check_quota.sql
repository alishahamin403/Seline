-- Check current quota usage
SELECT
  id as user_id,
  subscription_tier,
  daily_quota_tokens,
  quota_used_today,
  monthly_quota_tokens,
  quota_used_this_month,
  daily_quota_reset_date,
  quota_reset_date
FROM user_profiles;

-- Check recent usage logs to see actual usage
SELECT
  created_at,
  operation_type,
  input_tokens,
  output_tokens,
  total_tokens,
  total_cost
FROM deepseek_usage_logs
ORDER BY created_at DESC
LIMIT 20;

-- Sum total usage today
SELECT
  DATE(created_at) as date,
  COUNT(*) as request_count,
  SUM(total_tokens) as total_tokens_used,
  SUM(total_cost) as total_cost_usd
FROM deepseek_usage_logs
WHERE created_at >= CURRENT_DATE
GROUP BY DATE(created_at);

-- OPTIONAL: Reset quota if stuck (uncomment to use)
-- UPDATE user_profiles
-- SET quota_used_today = 0,
--     daily_quota_reset_date = CURRENT_DATE + INTERVAL '1 day'
-- WHERE id = 'YOUR_USER_ID_HERE';
