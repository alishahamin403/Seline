ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS location text;

COMMENT ON COLUMN public.tasks.location IS
'Optional event/task location entered by the user or synced from calendars.';
