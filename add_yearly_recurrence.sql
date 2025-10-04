-- Migration to add 'yearly' to recurrence_frequency constraint
-- Run this in your Supabase SQL Editor

-- Drop the existing check constraint
ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_recurrence_frequency_check;

-- Add new check constraint with 'yearly' included
ALTER TABLE public.tasks ADD CONSTRAINT tasks_recurrence_frequency_check
CHECK (recurrence_frequency IN ('daily', 'weekly', 'biweekly', 'monthly', 'yearly'));
