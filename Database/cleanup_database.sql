-- Clean up database - Drop all custom tables except auth system
-- This will give you a fresh start with only user authentication

-- Drop all custom tables in the correct order (respecting foreign key constraints)
DROP TABLE IF EXISTS search_analytics CASCADE;
DROP TABLE IF EXISTS email_attachments CASCADE;
DROP TABLE IF EXISTS emails CASCADE;
DROP TABLE IF EXISTS sync_status CASCADE;
DROP TABLE IF EXISTS todo_items CASCADE;
DROP TABLE IF EXISTS notes CASCADE;
DROP TABLE IF EXISTS folders CASCADE;
DROP TABLE IF EXISTS calendar_events CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Keep user_profiles if it exists, or we'll recreate it
-- DROP TABLE IF EXISTS user_profiles CASCADE;

-- Show remaining tables (should only be auth system tables + user_profiles)
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;