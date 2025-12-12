-- Fix duplicate functions by dropping versions without search_path

-- Drop the duplicate check_deepseek_quota without search_path
DROP FUNCTION IF EXISTS public.check_deepseek_quota(uuid, integer);

-- Drop the duplicate increment_deepseek_quota without search_path
DROP FUNCTION IF EXISTS public.increment_deepseek_quota(uuid, integer);

-- Ensure the remaining functions have proper search_path
-- (The ones with search_path set should remain from the previous migration)

-- Verify views are properly recreated without SECURITY DEFINER
-- Drop and recreate to ensure no SECURITY DEFINER property
DROP VIEW IF EXISTS public.deepseek_quota_status CASCADE;
CREATE VIEW public.deepseek_quota_status
WITH (security_invoker=true) AS
SELECT
  id AS user_id,
  subscription_tier,
  llm_provider,
  monthly_quota_tokens,
  quota_used_this_month,
  monthly_quota_tokens - quota_used_this_month AS quota_remaining,
  round(quota_used_this_month::numeric / monthly_quota_tokens::numeric * 100::numeric, 2) AS quota_used_percent,
  quota_reset_date
FROM user_profiles;

DROP VIEW IF EXISTS public.deepseek_cost_analytics CASCADE;
CREATE VIEW public.deepseek_cost_analytics
WITH (security_invoker=true) AS
SELECT
  user_id,
  operation_type,
  count(*) AS request_count,
  sum(total_tokens) AS total_tokens,
  sum(cache_hit_tokens) AS cached_tokens,
  round(sum(total_cost), 6) AS total_cost_usd,
  round(sum(cache_savings), 6) AS savings_from_cache,
  round(avg(latency_ms), 0) AS avg_latency_ms,
  date_trunc('day', created_at) AS usage_date
FROM deepseek_usage_logs
WHERE created_at > (now() - interval '30 days')
GROUP BY user_id, operation_type, date_trunc('day', created_at);
