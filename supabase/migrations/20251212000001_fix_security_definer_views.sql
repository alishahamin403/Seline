-- Fix security definer views by recreating them without SECURITY DEFINER
-- This allows RLS policies to work properly and resolves security warnings

-- Drop and recreate deepseek_quota_status view
DROP VIEW IF EXISTS public.deepseek_quota_status;

CREATE VIEW public.deepseek_quota_status AS
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

-- Drop and recreate deepseek_cost_analytics view
DROP VIEW IF EXISTS public.deepseek_cost_analytics;

CREATE VIEW public.deepseek_cost_analytics AS
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
