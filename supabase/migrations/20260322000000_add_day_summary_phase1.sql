create table if not exists public.day_summaries (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    summary_date date not null,
    title text not null default '',
    summary_text text not null default '',
    mood text,
    highlights_json jsonb not null default '[]'::jsonb,
    open_loops_json jsonb not null default '[]'::jsonb,
    anomalies_json jsonb not null default '[]'::jsonb,
    source_refs_json jsonb not null default '[]'::jsonb,
    metadata_json jsonb not null default '{}'::jsonb,
    embedding_text text not null default '',
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

alter table public.day_summaries add column if not exists title text not null default '';
alter table public.day_summaries add column if not exists summary_text text not null default '';
alter table public.day_summaries add column if not exists mood text;
alter table public.day_summaries add column if not exists highlights_json jsonb not null default '[]'::jsonb;
alter table public.day_summaries add column if not exists open_loops_json jsonb not null default '[]'::jsonb;
alter table public.day_summaries add column if not exists anomalies_json jsonb not null default '[]'::jsonb;
alter table public.day_summaries add column if not exists source_refs_json jsonb not null default '[]'::jsonb;
alter table public.day_summaries add column if not exists metadata_json jsonb not null default '{}'::jsonb;
alter table public.day_summaries add column if not exists embedding_text text not null default '';
alter table public.day_summaries add column if not exists created_at timestamptz not null default timezone('utc', now());
alter table public.day_summaries add column if not exists updated_at timestamptz not null default timezone('utc', now());

create unique index if not exists idx_day_summaries_user_day
    on public.day_summaries (user_id, summary_date);

create index if not exists idx_day_summaries_user_updated
    on public.day_summaries (user_id, updated_at desc);

alter table public.day_summaries enable row level security;

do $$
begin
    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'day_summaries'
          and policyname = 'Users can view their own day summaries'
    ) then
        create policy "Users can view their own day summaries"
            on public.day_summaries
            for select
            using (auth.uid() = user_id);
    end if;

    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'day_summaries'
          and policyname = 'Users can insert their own day summaries'
    ) then
        create policy "Users can insert their own day summaries"
            on public.day_summaries
            for insert
            with check (auth.uid() = user_id);
    end if;

    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'day_summaries'
          and policyname = 'Users can update their own day summaries'
    ) then
        create policy "Users can update their own day summaries"
            on public.day_summaries
            for update
            using (auth.uid() = user_id)
            with check (auth.uid() = user_id);
    end if;

    if not exists (
        select 1
        from pg_policies
        where schemaname = 'public'
          and tablename = 'day_summaries'
          and policyname = 'Users can delete their own day summaries'
    ) then
        create policy "Users can delete their own day summaries"
            on public.day_summaries
            for delete
            using (auth.uid() = user_id);
    end if;
end
$$;
