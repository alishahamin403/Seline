-- ============================================
-- Fix Duplicate Function Versions
-- ============================================
-- Issue: Multiple versions of functions exist with different signatures
-- Some have search_path set, others don't
-- This migration adds search_path to all versions

-- Fix all versions of increment_deepseek_quota
-- Version 1: (p_user_id uuid, p_tokens_used integer)
CREATE OR REPLACE FUNCTION public.increment_deepseek_quota(p_user_id uuid, p_tokens_used integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE user_profiles
  SET deepseek_quota_used = COALESCE(deepseek_quota_used, 0) + p_tokens_used
  WHERE id = p_user_id;
END;
$$;

-- Version 2: (tokens integer)
CREATE OR REPLACE FUNCTION public.increment_deepseek_quota(tokens integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE user_profiles
  SET deepseek_quota_used = COALESCE(deepseek_quota_used, 0) + tokens
  WHERE id = auth.uid();
END;
$$;

-- Fix all versions of check_deepseek_quota
-- Version 1: () - no parameters
CREATE OR REPLACE FUNCTION public.check_deepseek_quota()
RETURNS TABLE(quota_used numeric, quota_limit numeric, can_use boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(deepseek_quota_used, 0) as quota_used,
    COALESCE(deepseek_quota_limit, 100) as quota_limit,
    COALESCE(deepseek_quota_used, 0) < COALESCE(deepseek_quota_limit, 100) as can_use
  FROM user_profiles
  WHERE id = auth.uid();
END;
$$;

-- Version 2: (p_user_id uuid, p_tokens_needed integer)
CREATE OR REPLACE FUNCTION public.check_deepseek_quota(p_user_id uuid, p_tokens_needed integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quota_used numeric;
  v_quota_limit numeric;
BEGIN
  SELECT
    COALESCE(deepseek_quota_used, 0),
    COALESCE(deepseek_quota_limit, 100)
  INTO v_quota_used, v_quota_limit
  FROM user_profiles
  WHERE id = p_user_id;

  RETURN (v_quota_used + p_tokens_needed) <= v_quota_limit;
END;
$$;

-- Force recreate visit_health_check view to clear any cached metadata
DROP VIEW IF EXISTS public.visit_health_check CASCADE;
CREATE OR REPLACE VIEW public.visit_health_check
WITH (security_invoker=true)
AS
  SELECT
    user_id,
    COUNT(*) as total_visits,
    COUNT(*) FILTER (WHERE exit_time IS NULL) as active_visits,
    MAX(created_at) as last_visit
  FROM public.location_visits
  GROUP BY user_id;

COMMENT ON VIEW public.visit_health_check IS 'Health check view for location visits - uses security invoker';
