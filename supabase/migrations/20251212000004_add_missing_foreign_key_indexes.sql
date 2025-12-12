-- Add indexes for foreign keys to improve query performance
-- These indexes help with JOIN operations and foreign key constraint checks

-- Index for attachments.user_id
CREATE INDEX IF NOT EXISTS idx_attachments_user_id ON public.attachments(user_id);

-- Index for extracted_data.user_id
CREATE INDEX IF NOT EXISTS idx_extracted_data_user_id ON public.extracted_data(user_id);

-- Index for recurring_expenses.user_id
CREATE INDEX IF NOT EXISTS idx_recurring_expenses_user_id ON public.recurring_expenses(user_id);

-- Index for recurring_instances.recurring_expense_id
CREATE INDEX IF NOT EXISTS idx_recurring_instances_recurring_expense_id ON public.recurring_instances(recurring_expense_id);

-- Additional helpful indexes for commonly queried foreign keys
CREATE INDEX IF NOT EXISTS idx_notes_folder_id ON public.notes(folder_id);
CREATE INDEX IF NOT EXISTS idx_notes_user_id ON public.notes(user_id);
CREATE INDEX IF NOT EXISTS idx_tasks_user_id ON public.tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_places_user_id ON public.saved_places(user_id);
CREATE INDEX IF NOT EXISTS idx_location_visits_user_id ON public.location_visits(user_id);
CREATE INDEX IF NOT EXISTS idx_location_visits_saved_place_id ON public.location_visits(saved_place_id);
CREATE INDEX IF NOT EXISTS idx_saved_emails_user_id ON public.saved_emails(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_emails_email_folder_id ON public.saved_emails(email_folder_id);
