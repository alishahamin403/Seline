-- Fix mutable search_path issues in functions by setting search_path explicitly
-- This prevents potential security vulnerabilities from search_path manipulation

-- Fix delete_old_trash_items
CREATE OR REPLACE FUNCTION public.delete_old_trash_items()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
    -- Delete notes older than 30 days
    DELETE FROM deleted_notes
    WHERE deleted_at < NOW() - INTERVAL '30 days';

    -- Delete folders older than 30 days
    DELETE FROM deleted_folders
    WHERE deleted_at < NOW() - INTERVAL '30 days';
END;
$function$;

-- Fix update_tags_timestamp
CREATE OR REPLACE FUNCTION public.update_tags_timestamp()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;

-- Fix handle_updated_at
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;

-- Fix handle_new_user
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
    INSERT INTO public.user_profiles (id, email, full_name, avatar_url)
    VALUES (
        NEW.id,
        NEW.email,
        NEW.raw_user_meta_data->>'full_name',
        NEW.raw_user_meta_data->>'avatar_url'
    );
    RETURN NEW;
END;
$function$;

-- Fix update_notes_updated_at
CREATE OR REPLACE FUNCTION public.update_notes_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.updated_at = NOW();
    NEW.date_modified = NOW();
    RETURN NEW;
END;
$function$;

-- Fix update_saved_places_updated_at
CREATE OR REPLACE FUNCTION public.update_saved_places_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.updated_at = NOW();
    NEW.date_modified = NOW();
    RETURN NEW;
END;
$function$;

-- Fix check_deepseek_quota
CREATE OR REPLACE FUNCTION public.check_deepseek_quota()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    user_quota integer;
    user_used integer;
BEGIN
    SELECT monthly_quota_tokens, quota_used_this_month
    INTO user_quota, user_used
    FROM user_profiles
    WHERE id = auth.uid();

    RETURN user_used < user_quota;
END;
$function$;

-- Fix increment_deepseek_quota
CREATE OR REPLACE FUNCTION public.increment_deepseek_quota(tokens integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
    UPDATE user_profiles
    SET quota_used_this_month = quota_used_this_month + tokens
    WHERE id = auth.uid();
END;
$function$;

-- Fix update_folders_updated_at
CREATE OR REPLACE FUNCTION public.update_folders_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;

-- Fix update_email_search_vector
CREATE OR REPLACE FUNCTION public.update_email_search_vector()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', coalesce(NEW.subject, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.sender_name, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.body, '')), 'C');
    RETURN NEW;
END;
$function$;

-- Fix update_calendar_search_vector
CREATE OR REPLACE FUNCTION public.update_calendar_search_vector()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B');
    RETURN NEW;
END;
$function$;

-- Fix update_note_search_vector
CREATE OR REPLACE FUNCTION public.update_note_search_vector()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.content, '')), 'B');
    RETURN NEW;
END;
$function$;

-- Fix update_todo_search_vector
CREATE OR REPLACE FUNCTION public.update_todo_search_vector()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.search_vector :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.description, '')), 'B');
    RETURN NEW;
END;
$function$;

-- Fix update_updated_at_column
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;

-- Fix update_folder_note_count
CREATE OR REPLACE FUNCTION public.update_folder_note_count()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
DECLARE
    folder_uuid uuid;
BEGIN
    -- Get folder_id from either NEW or OLD record
    folder_uuid := COALESCE(NEW.folder_id, OLD.folder_id);

    IF folder_uuid IS NOT NULL THEN
        UPDATE folders
        SET note_count = (
            SELECT COUNT(*)
            FROM notes
            WHERE folder_id = folder_uuid
        )
        WHERE id = folder_uuid;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$function$;
