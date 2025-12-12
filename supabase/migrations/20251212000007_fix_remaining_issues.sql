-- Fix remaining security and performance issues

-- ==========================================
-- 1. Fix deepseek_usage_logs RLS policy
-- ==========================================
DROP POLICY IF EXISTS "Users can view their own usage logs" ON public.deepseek_usage_logs;
CREATE POLICY "Users can view their own usage logs" ON public.deepseek_usage_logs
    FOR SELECT USING (user_id = (select auth.uid()));

-- ==========================================
-- 2. Remove duplicate RLS policies
-- ==========================================

-- ATTACHMENTS table - keep the more descriptive policies
DROP POLICY IF EXISTS "Allow authenticated users to insert attachments" ON public.attachments;
DROP POLICY IF EXISTS "Users can select their own attachments" ON public.attachments;
DROP POLICY IF EXISTS "Users can update their own attachments" ON public.attachments;
DROP POLICY IF EXISTS "Users can delete their own attachments" ON public.attachments;

-- Keep only these policies for attachments:
-- - "Allow insert if note belongs to user"
-- - "Allow select if note belongs to user"
-- - "Allow update if note belongs to user"
-- - "Allow delete if note belongs to user"

-- RECURRING_EXPENSES table - remove duplicate
DROP POLICY IF EXISTS "Users can create recurring expenses" ON public.recurring_expenses;

-- Keep only:
-- - "Users can view their own recurring expenses"
-- - "Users can create their own recurring expenses"
-- - "Users can update their own recurring expenses"
-- - "Users can delete their own recurring expenses"

-- RECURRING_INSTANCES table - remove duplicates
DROP POLICY IF EXISTS "Users can view their recurring instances" ON public.recurring_instances;
DROP POLICY IF EXISTS "Users can create recurring instances" ON public.recurring_instances;
DROP POLICY IF EXISTS "Users can update recurring instances" ON public.recurring_instances;
DROP POLICY IF EXISTS "Users can delete recurring instances" ON public.recurring_instances;

-- Keep only:
-- - "Users can view instances of their recurring expenses"
-- - "Users can create instances for their recurring expenses"
-- - "Users can update instances of their recurring expenses"
-- - "Users can delete instances of their recurring expenses"

-- ==========================================
-- 3. Remove duplicate indexes
-- ==========================================

-- Notes table duplicates
DROP INDEX IF EXISTS public.notes_folder_id_idx;  -- Keep idx_notes_folder_id
DROP INDEX IF EXISTS public.notes_user_id_idx;    -- Keep idx_notes_user_id

-- Saved emails table duplicates
DROP INDEX IF EXISTS public.saved_emails_folder_id_idx;  -- Keep idx_saved_emails_email_folder_id
DROP INDEX IF EXISTS public.saved_emails_user_id_idx;    -- Keep idx_saved_emails_user_id
