-- Enable leaked password protection in Supabase Auth
-- This feature checks passwords against the HaveIBeenPwned database to prevent
-- users from using compromised passwords

-- Note: This setting is typically configured through the Supabase Dashboard
-- under Authentication > Providers > Email > Password Protection
-- or via the Supabase CLI / Management API

-- This migration serves as documentation that this setting should be enabled.
-- To enable it, run:
-- 1. Go to your Supabase Dashboard
-- 2. Navigate to Authentication > Providers > Email
-- 3. Scroll to "Password Protection"
-- 4. Enable "Leaked Password Protection"

-- Alternatively, use the Supabase Management API to enable this programmatically
-- See: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
