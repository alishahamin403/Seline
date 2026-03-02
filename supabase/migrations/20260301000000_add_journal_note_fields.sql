alter table public.notes
    add column if not exists kind text,
    add column if not exists journal_date timestamptz,
    add column if not exists journal_week_start_date timestamptz;

create index if not exists notes_kind_idx
    on public.notes (kind);

create index if not exists notes_journal_date_idx
    on public.notes (journal_date);

create index if not exists notes_journal_week_start_date_idx
    on public.notes (journal_week_start_date);
