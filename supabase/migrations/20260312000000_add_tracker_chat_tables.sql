create table if not exists public.tracker_threads (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null,
    status text not null default 'active' check (status in ('active', 'archived')),
    rule_json jsonb not null,
    summary_text text,
    subtitle text,
    created_at timestamptz not null default timezone('utc', now()),
    updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.tracker_messages (
    id uuid primary key default gen_random_uuid(),
    tracker_thread_id uuid not null references public.tracker_threads(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    is_user boolean not null,
    text text not null,
    draft_json jsonb,
    created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.tracker_ledger_entries (
    id uuid primary key default gen_random_uuid(),
    tracker_thread_id uuid not null references public.tracker_threads(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    entry_type text not null check (entry_type in ('expense', 'adjustment', 'transfer')),
    actor_id uuid,
    target_participant_id uuid,
    amount double precision not null,
    note text,
    occurred_at timestamptz not null,
    created_at timestamptz not null default timezone('utc', now()),
    source_message_id uuid
);

create index if not exists idx_tracker_threads_user_updated_at
    on public.tracker_threads(user_id, updated_at desc);

create index if not exists idx_tracker_messages_thread_created_at
    on public.tracker_messages(tracker_thread_id, created_at asc);

create index if not exists idx_tracker_messages_user_thread
    on public.tracker_messages(user_id, tracker_thread_id);

create index if not exists idx_tracker_ledger_thread_occurred_at
    on public.tracker_ledger_entries(tracker_thread_id, occurred_at asc);

create index if not exists idx_tracker_ledger_user_thread
    on public.tracker_ledger_entries(user_id, tracker_thread_id);

alter table public.tracker_threads enable row level security;
alter table public.tracker_messages enable row level security;
alter table public.tracker_ledger_entries enable row level security;

drop policy if exists "Users can read own tracker threads" on public.tracker_threads;
create policy "Users can read own tracker threads" on public.tracker_threads
    for select using (user_id = auth.uid());

drop policy if exists "Users can insert own tracker threads" on public.tracker_threads;
create policy "Users can insert own tracker threads" on public.tracker_threads
    for insert with check (user_id = auth.uid());

drop policy if exists "Users can update own tracker threads" on public.tracker_threads;
create policy "Users can update own tracker threads" on public.tracker_threads
    for update using (user_id = auth.uid());

drop policy if exists "Users can delete own tracker threads" on public.tracker_threads;
create policy "Users can delete own tracker threads" on public.tracker_threads
    for delete using (user_id = auth.uid());

drop policy if exists "Users can read own tracker messages" on public.tracker_messages;
create policy "Users can read own tracker messages" on public.tracker_messages
    for select using (user_id = auth.uid());

drop policy if exists "Users can insert own tracker messages" on public.tracker_messages;
create policy "Users can insert own tracker messages" on public.tracker_messages
    for insert with check (user_id = auth.uid());

drop policy if exists "Users can update own tracker messages" on public.tracker_messages;
create policy "Users can update own tracker messages" on public.tracker_messages
    for update using (user_id = auth.uid());

drop policy if exists "Users can delete own tracker messages" on public.tracker_messages;
create policy "Users can delete own tracker messages" on public.tracker_messages
    for delete using (user_id = auth.uid());

drop policy if exists "Users can read own tracker ledger entries" on public.tracker_ledger_entries;
create policy "Users can read own tracker ledger entries" on public.tracker_ledger_entries
    for select using (user_id = auth.uid());

drop policy if exists "Users can insert own tracker ledger entries" on public.tracker_ledger_entries;
create policy "Users can insert own tracker ledger entries" on public.tracker_ledger_entries
    for insert with check (user_id = auth.uid());

drop policy if exists "Users can update own tracker ledger entries" on public.tracker_ledger_entries;
create policy "Users can update own tracker ledger entries" on public.tracker_ledger_entries
    for update using (user_id = auth.uid());

drop policy if exists "Users can delete own tracker ledger entries" on public.tracker_ledger_entries;
create policy "Users can delete own tracker ledger entries" on public.tracker_ledger_entries
    for delete using (user_id = auth.uid());
