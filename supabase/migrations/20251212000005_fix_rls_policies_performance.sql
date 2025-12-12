-- Fix RLS policies to use (select auth.uid()) instead of auth.uid()
-- This prevents re-evaluation for each row and significantly improves query performance
-- See: https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select

-- USER_PROFILES table policies
DROP POLICY IF EXISTS "Users can view own profile" ON public.user_profiles;
CREATE POLICY "Users can view own profile" ON public.user_profiles
    FOR SELECT USING (id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert own profile" ON public.user_profiles;
CREATE POLICY "Users can insert own profile" ON public.user_profiles
    FOR INSERT WITH CHECK (id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
CREATE POLICY "Users can update own profile" ON public.user_profiles
    FOR UPDATE USING (id = (select auth.uid()));

-- TASKS table policies
DROP POLICY IF EXISTS "Users can view own tasks" ON public.tasks;
CREATE POLICY "Users can view own tasks" ON public.tasks
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert own tasks" ON public.tasks;
CREATE POLICY "Users can insert own tasks" ON public.tasks
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update own tasks" ON public.tasks;
CREATE POLICY "Users can update own tasks" ON public.tasks
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete own tasks" ON public.tasks;
CREATE POLICY "Users can delete own tasks" ON public.tasks
    FOR DELETE USING (user_id = (select auth.uid()));

-- NOTES table policies
DROP POLICY IF EXISTS "Users can view their own notes" ON public.notes;
CREATE POLICY "Users can view their own notes" ON public.notes
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own notes" ON public.notes;
CREATE POLICY "Users can insert their own notes" ON public.notes
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own notes" ON public.notes;
CREATE POLICY "Users can update their own notes" ON public.notes
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own notes" ON public.notes;
CREATE POLICY "Users can delete their own notes" ON public.notes
    FOR DELETE USING (user_id = (select auth.uid()));

-- FOLDERS table policies
DROP POLICY IF EXISTS "Users can view their own folders" ON public.folders;
CREATE POLICY "Users can view their own folders" ON public.folders
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own folders" ON public.folders;
CREATE POLICY "Users can insert their own folders" ON public.folders
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own folders" ON public.folders;
CREATE POLICY "Users can update their own folders" ON public.folders
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own folders" ON public.folders;
CREATE POLICY "Users can delete their own folders" ON public.folders
    FOR DELETE USING (user_id = (select auth.uid()));

-- SAVED_PLACES table policies
DROP POLICY IF EXISTS "Users can view own saved places" ON public.saved_places;
CREATE POLICY "Users can view own saved places" ON public.saved_places
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert own saved places" ON public.saved_places;
CREATE POLICY "Users can insert own saved places" ON public.saved_places
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update own saved places" ON public.saved_places;
CREATE POLICY "Users can update own saved places" ON public.saved_places
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete own saved places" ON public.saved_places;
CREATE POLICY "Users can delete own saved places" ON public.saved_places
    FOR DELETE USING (user_id = (select auth.uid()));

-- DELETED_NOTES table policies
DROP POLICY IF EXISTS "Users can view their own deleted notes" ON public.deleted_notes;
CREATE POLICY "Users can view their own deleted notes" ON public.deleted_notes
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own deleted notes" ON public.deleted_notes;
CREATE POLICY "Users can insert their own deleted notes" ON public.deleted_notes
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own deleted notes" ON public.deleted_notes;
CREATE POLICY "Users can delete their own deleted notes" ON public.deleted_notes
    FOR DELETE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own deleted notes" ON public.deleted_notes;
CREATE POLICY "Users can update their own deleted notes" ON public.deleted_notes
    FOR UPDATE USING (user_id = (select auth.uid()));

-- DELETED_FOLDERS table policies
DROP POLICY IF EXISTS "Users can view their own deleted folders" ON public.deleted_folders;
CREATE POLICY "Users can view their own deleted folders" ON public.deleted_folders
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own deleted folders" ON public.deleted_folders;
CREATE POLICY "Users can insert their own deleted folders" ON public.deleted_folders
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own deleted folders" ON public.deleted_folders;
CREATE POLICY "Users can delete their own deleted folders" ON public.deleted_folders
    FOR DELETE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own deleted folders" ON public.deleted_folders;
CREATE POLICY "Users can update their own deleted folders" ON public.deleted_folders
    FOR UPDATE USING (user_id = (select auth.uid()));

-- CONVERSATIONS table policies
DROP POLICY IF EXISTS "Users can view their own conversations" ON public.conversations;
CREATE POLICY "Users can view their own conversations" ON public.conversations
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own conversations" ON public.conversations;
CREATE POLICY "Users can insert their own conversations" ON public.conversations
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own conversations" ON public.conversations;
CREATE POLICY "Users can update their own conversations" ON public.conversations
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own conversations" ON public.conversations;
CREATE POLICY "Users can delete their own conversations" ON public.conversations
    FOR DELETE USING (user_id = (select auth.uid()));

-- CONTENT_RELATIONSHIPS table policies
DROP POLICY IF EXISTS "Users can view their own relationships" ON public.content_relationships;
CREATE POLICY "Users can view their own relationships" ON public.content_relationships
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can create their own relationships" ON public.content_relationships;
CREATE POLICY "Users can create their own relationships" ON public.content_relationships
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own relationships" ON public.content_relationships;
CREATE POLICY "Users can update their own relationships" ON public.content_relationships
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own relationships" ON public.content_relationships;
CREATE POLICY "Users can delete their own relationships" ON public.content_relationships
    FOR DELETE USING (user_id = (select auth.uid()));

-- SEARCH_HISTORY table policies
DROP POLICY IF EXISTS "Users can view their own search history" ON public.search_history;
CREATE POLICY "Users can view their own search history" ON public.search_history
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can create their own search history" ON public.search_history;
CREATE POLICY "Users can create their own search history" ON public.search_history
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own search history" ON public.search_history;
CREATE POLICY "Users can delete their own search history" ON public.search_history
    FOR DELETE USING (user_id = (select auth.uid()));

-- SEARCH_CONTEXTS table policies
DROP POLICY IF EXISTS "Users can view their own context" ON public.search_contexts;
CREATE POLICY "Users can view their own context" ON public.search_contexts
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own context" ON public.search_contexts;
CREATE POLICY "Users can update their own context" ON public.search_contexts
    FOR UPDATE USING (user_id = (select auth.uid()));

-- SUGGESTIONS table policies
DROP POLICY IF EXISTS "Users can view their own suggestions" ON public.suggestions;
CREATE POLICY "Users can view their own suggestions" ON public.suggestions
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can create their own suggestions" ON public.suggestions;
CREATE POLICY "Users can create their own suggestions" ON public.suggestions
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own suggestions" ON public.suggestions;
CREATE POLICY "Users can update their own suggestions" ON public.suggestions
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own suggestions" ON public.suggestions;
CREATE POLICY "Users can delete their own suggestions" ON public.suggestions
    FOR DELETE USING (user_id = (select auth.uid()));

-- ATTACHMENTS table policies
DROP POLICY IF EXISTS "Allow insert if note belongs to user" ON public.attachments;
CREATE POLICY "Allow insert if note belongs to user" ON public.attachments
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM notes
            WHERE notes.id = note_id
            AND notes.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Allow select if note belongs to user" ON public.attachments;
CREATE POLICY "Allow select if note belongs to user" ON public.attachments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM notes
            WHERE notes.id = note_id
            AND notes.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Allow update if note belongs to user" ON public.attachments;
CREATE POLICY "Allow update if note belongs to user" ON public.attachments
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM notes
            WHERE notes.id = note_id
            AND notes.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can select their own attachments" ON public.attachments;
CREATE POLICY "Users can select their own attachments" ON public.attachments
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own attachments" ON public.attachments;
CREATE POLICY "Users can update their own attachments" ON public.attachments
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Allow delete if note belongs to user" ON public.attachments;
CREATE POLICY "Allow delete if note belongs to user" ON public.attachments
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM notes
            WHERE notes.id = note_id
            AND notes.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can delete their own attachments" ON public.attachments;
CREATE POLICY "Users can delete their own attachments" ON public.attachments
    FOR DELETE USING (user_id = (select auth.uid()));

-- EXTRACTED_DATA table policies
DROP POLICY IF EXISTS "Allow insert extracted data" ON public.extracted_data;
CREATE POLICY "Allow insert extracted data" ON public.extracted_data
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Allow select extracted data" ON public.extracted_data;
CREATE POLICY "Allow select extracted data" ON public.extracted_data
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Allow update extracted data" ON public.extracted_data;
CREATE POLICY "Allow update extracted data" ON public.extracted_data
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Allow delete extracted data" ON public.extracted_data;
CREATE POLICY "Allow delete extracted data" ON public.extracted_data
    FOR DELETE USING (user_id = (select auth.uid()));

-- TAGS table policies
DROP POLICY IF EXISTS "Users can view own tags" ON public.tags;
CREATE POLICY "Users can view own tags" ON public.tags
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert own tags" ON public.tags;
CREATE POLICY "Users can insert own tags" ON public.tags
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update own tags" ON public.tags;
CREATE POLICY "Users can update own tags" ON public.tags
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete own tags" ON public.tags;
CREATE POLICY "Users can delete own tags" ON public.tags
    FOR DELETE USING (user_id = (select auth.uid()));

-- RECEIPT_CATEGORIES table policies
DROP POLICY IF EXISTS "Users can view own categories" ON public.receipt_categories;
CREATE POLICY "Users can view own categories" ON public.receipt_categories
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert own categories" ON public.receipt_categories;
CREATE POLICY "Users can insert own categories" ON public.receipt_categories
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update own categories" ON public.receipt_categories;
CREATE POLICY "Users can update own categories" ON public.receipt_categories
    FOR UPDATE USING (user_id = (select auth.uid()));

-- EMAIL_FOLDERS table policies
DROP POLICY IF EXISTS "Users can view their own folders" ON public.email_folders;
CREATE POLICY "Users can view their own folders" ON public.email_folders
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can create their own folders" ON public.email_folders;
CREATE POLICY "Users can create their own folders" ON public.email_folders
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own folders" ON public.email_folders;
CREATE POLICY "Users can update their own folders" ON public.email_folders
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own folders" ON public.email_folders;
CREATE POLICY "Users can delete their own folders" ON public.email_folders
    FOR DELETE USING (user_id = (select auth.uid()));

-- SAVED_EMAILS table policies
DROP POLICY IF EXISTS "Users can view their own saved emails" ON public.saved_emails;
CREATE POLICY "Users can view their own saved emails" ON public.saved_emails
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can create their own saved emails" ON public.saved_emails;
CREATE POLICY "Users can create their own saved emails" ON public.saved_emails
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own saved emails" ON public.saved_emails;
CREATE POLICY "Users can update their own saved emails" ON public.saved_emails
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own saved emails" ON public.saved_emails;
CREATE POLICY "Users can delete their own saved emails" ON public.saved_emails
    FOR DELETE USING (user_id = (select auth.uid()));

-- SAVED_EMAIL_ATTACHMENTS table policies
DROP POLICY IF EXISTS "Users can view attachments for their own emails" ON public.saved_email_attachments;
CREATE POLICY "Users can view attachments for their own emails" ON public.saved_email_attachments
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM saved_emails
            WHERE saved_emails.id = saved_email_id
            AND saved_emails.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can create attachments for their own emails" ON public.saved_email_attachments;
CREATE POLICY "Users can create attachments for their own emails" ON public.saved_email_attachments
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM saved_emails
            WHERE saved_emails.id = saved_email_id
            AND saved_emails.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can update attachments for their own emails" ON public.saved_email_attachments;
CREATE POLICY "Users can update attachments for their own emails" ON public.saved_email_attachments
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM saved_emails
            WHERE saved_emails.id = saved_email_id
            AND saved_emails.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can delete attachments for their own emails" ON public.saved_email_attachments;
CREATE POLICY "Users can delete attachments for their own emails" ON public.saved_email_attachments
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM saved_emails
            WHERE saved_emails.id = saved_email_id
            AND saved_emails.user_id = (select auth.uid())
        )
    );

-- EMAIL_LABEL_MAPPINGS table policies
DROP POLICY IF EXISTS "Users can view their own label mappings" ON public.email_label_mappings;
CREATE POLICY "Users can view their own label mappings" ON public.email_label_mappings
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can create their own label mappings" ON public.email_label_mappings;
CREATE POLICY "Users can create their own label mappings" ON public.email_label_mappings
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own label mappings" ON public.email_label_mappings;
CREATE POLICY "Users can update their own label mappings" ON public.email_label_mappings
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own label mappings" ON public.email_label_mappings;
CREATE POLICY "Users can delete their own label mappings" ON public.email_label_mappings
    FOR DELETE USING (user_id = (select auth.uid()));

-- RECURRING_EXPENSES table policies
DROP POLICY IF EXISTS "Users can create recurring expenses" ON public.recurring_expenses;
CREATE POLICY "Users can create recurring expenses" ON public.recurring_expenses
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can view their own recurring expenses" ON public.recurring_expenses;
CREATE POLICY "Users can view their own recurring expenses" ON public.recurring_expenses
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can create their own recurring expenses" ON public.recurring_expenses;
CREATE POLICY "Users can create their own recurring expenses" ON public.recurring_expenses
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own recurring expenses" ON public.recurring_expenses;
CREATE POLICY "Users can update their own recurring expenses" ON public.recurring_expenses
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own recurring expenses" ON public.recurring_expenses;
CREATE POLICY "Users can delete their own recurring expenses" ON public.recurring_expenses
    FOR DELETE USING (user_id = (select auth.uid()));

-- RECURRING_INSTANCES table policies
DROP POLICY IF EXISTS "Users can view their recurring instances" ON public.recurring_instances;
CREATE POLICY "Users can view their recurring instances" ON public.recurring_instances
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM recurring_expenses
            WHERE recurring_expenses.id = recurring_expense_id
            AND recurring_expenses.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can create recurring instances" ON public.recurring_instances;
CREATE POLICY "Users can create recurring instances" ON public.recurring_instances
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM recurring_expenses
            WHERE recurring_expenses.id = recurring_expense_id
            AND recurring_expenses.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can update recurring instances" ON public.recurring_instances;
CREATE POLICY "Users can update recurring instances" ON public.recurring_instances
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM recurring_expenses
            WHERE recurring_expenses.id = recurring_expense_id
            AND recurring_expenses.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can delete recurring instances" ON public.recurring_instances;
CREATE POLICY "Users can delete recurring instances" ON public.recurring_instances
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM recurring_expenses
            WHERE recurring_expenses.id = recurring_expense_id
            AND recurring_expenses.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can view instances of their recurring expenses" ON public.recurring_instances;
CREATE POLICY "Users can view instances of their recurring expenses" ON public.recurring_instances
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM recurring_expenses
            WHERE recurring_expenses.id = recurring_expense_id
            AND recurring_expenses.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can create instances for their recurring expenses" ON public.recurring_instances;
CREATE POLICY "Users can create instances for their recurring expenses" ON public.recurring_instances
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM recurring_expenses
            WHERE recurring_expenses.id = recurring_expense_id
            AND recurring_expenses.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can update instances of their recurring expenses" ON public.recurring_instances;
CREATE POLICY "Users can update instances of their recurring expenses" ON public.recurring_instances
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM recurring_expenses
            WHERE recurring_expenses.id = recurring_expense_id
            AND recurring_expenses.user_id = (select auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can delete instances of their recurring expenses" ON public.recurring_instances;
CREATE POLICY "Users can delete instances of their recurring expenses" ON public.recurring_instances
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM recurring_expenses
            WHERE recurring_expenses.id = recurring_expense_id
            AND recurring_expenses.user_id = (select auth.uid())
        )
    );

-- LOCATION_VISITS table policies
DROP POLICY IF EXISTS "Users can view their own visits" ON public.location_visits;
CREATE POLICY "Users can view their own visits" ON public.location_visits
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own visits" ON public.location_visits;
CREATE POLICY "Users can insert their own visits" ON public.location_visits
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own visits" ON public.location_visits;
CREATE POLICY "Users can update their own visits" ON public.location_visits
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own visits" ON public.location_visits;
CREATE POLICY "Users can delete their own visits" ON public.location_visits
    FOR DELETE USING (user_id = (select auth.uid()));

-- QUICK_NOTES table policies
DROP POLICY IF EXISTS "Users can view their own quick notes" ON public.quick_notes;
CREATE POLICY "Users can view their own quick notes" ON public.quick_notes
    FOR SELECT USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can insert their own quick notes" ON public.quick_notes;
CREATE POLICY "Users can insert their own quick notes" ON public.quick_notes
    FOR INSERT WITH CHECK (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can update their own quick notes" ON public.quick_notes;
CREATE POLICY "Users can update their own quick notes" ON public.quick_notes
    FOR UPDATE USING (user_id = (select auth.uid()));

DROP POLICY IF EXISTS "Users can delete their own quick notes" ON public.quick_notes;
CREATE POLICY "Users can delete their own quick notes" ON public.quick_notes
    FOR DELETE USING (user_id = (select auth.uid()));
