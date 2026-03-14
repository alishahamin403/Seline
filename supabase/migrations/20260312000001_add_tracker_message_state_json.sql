alter table public.tracker_messages
    add column if not exists state_json jsonb;
