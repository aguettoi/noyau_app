-- Phase 1: generic audit trail for modular workbook imports.
-- Business modules write their reversible commands through the same session;
-- the tables contain no workbook-specific column and do not couple importers.
create table public.import_sessions (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  source_file_name text not null check (char_length(trim(source_file_name)) between 1 and 255),
  source_fingerprint text not null check (char_length(trim(source_fingerprint)) between 1 and 128),
  status text not null default 'analysed' check (status in ('analysed', 'confirmed', 'completed', 'cancelled', 'undone', 'failed')),
  created_by uuid not null references auth.users(id),
  confirmed_by uuid references auth.users(id),
  confirmed_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  created_at timestamptz not null default now()
);

create table public.import_sheet_runs (
  id uuid primary key default gen_random_uuid(),
  import_session_id uuid not null references public.import_sessions(id) on delete cascade,
  importer_id text not null check (char_length(trim(importer_id)) between 1 and 80),
  source_sheet_name text not null check (char_length(trim(source_sheet_name)) between 1 and 120),
  status text not null check (status in ('analysed', 'ready', 'completed', 'failed', 'undone')),
  detected_records integer not null default 0 check (detected_records >= 0),
  preview jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (import_session_id, importer_id)
);

create table public.import_operation_journal (
  id uuid primary key default gen_random_uuid(),
  import_sheet_run_id uuid not null references public.import_sheet_runs(id) on delete cascade,
  operation_index integer not null check (operation_index >= 0),
  entity_type text not null,
  operation text not null check (operation in ('insert', 'update', 'archive')),
  forward_payload jsonb not null,
  undo_payload jsonb not null,
  applied_at timestamptz,
  undone_at timestamptz,
  unique (import_sheet_run_id, operation_index)
);

create table public.import_source_sheets (
  id uuid primary key default gen_random_uuid(),
  import_sheet_run_id uuid not null unique references public.import_sheet_runs(id) on delete cascade,
  source_sheet_name text not null,
  content jsonb not null,
  archived_at timestamptz,
  created_at timestamptz not null default now()
);

create index import_sessions_household_created_idx on public.import_sessions(household_id, created_at desc);
create index import_sheet_runs_session_idx on public.import_sheet_runs(import_session_id);
create index import_operation_journal_run_idx on public.import_operation_journal(import_sheet_run_id, operation_index);
create index import_source_sheets_run_idx on public.import_source_sheets(import_sheet_run_id) where archived_at is null;

alter table public.import_sessions enable row level security;
alter table public.import_sheet_runs enable row level security;
alter table public.import_operation_journal enable row level security;
alter table public.import_source_sheets enable row level security;

create policy "members read import sessions" on public.import_sessions for select
using (public.is_household_member(household_id));
create policy "members read import sheet runs" on public.import_sheet_runs for select
using (exists (
  select 1 from public.import_sessions sessions
  where sessions.id = import_session_id
    and public.is_household_member(sessions.household_id)
));
create policy "members read import operations" on public.import_operation_journal for select
using (exists (
  select 1 from public.import_sheet_runs runs
  join public.import_sessions sessions on sessions.id = runs.import_session_id
  where runs.id = import_sheet_run_id
    and public.is_household_member(sessions.household_id)
));
create policy "members read import source sheets" on public.import_source_sheets for select
using (exists (
  select 1 from public.import_sheet_runs runs
  join public.import_sessions sessions on sessions.id = runs.import_session_id
  where runs.id = import_sheet_run_id
    and public.is_household_member(sessions.household_id)
));

-- Archives all analysed source sheets in one transaction. A sheet-specific
-- importer may later materialise business entities from this immutable source;
-- the source itself remains auditable and reversible without altering it.
create or replace function public.archive_workbook_import(
  p_household_id uuid,
  p_source_file_name text,
  p_source_fingerprint text,
  p_sheets jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
  v_sheet jsonb;
  v_sheet_run_id uuid;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if char_length(trim(coalesce(p_source_file_name, ''))) not between 1 and 255 then
    raise exception 'A source file name is required';
  end if;
  if char_length(trim(coalesce(p_source_fingerprint, ''))) <> 64 then
    raise exception 'A SHA-256 fingerprint is required';
  end if;
  if jsonb_typeof(p_sheets) <> 'array' or jsonb_array_length(p_sheets) = 0 then
    raise exception 'At least one source sheet is required';
  end if;

  insert into public.import_sessions (
    household_id, source_file_name, source_fingerprint, status, created_by, confirmed_by, confirmed_at, completed_at
  ) values (
    p_household_id, trim(p_source_file_name), p_source_fingerprint, 'completed', auth.uid(), auth.uid(), now(), now()
  ) returning id into v_session_id;

  for v_sheet in select value from jsonb_array_elements(p_sheets)
  loop
    if coalesce(v_sheet ->> 'importer_id', '') = ''
       or coalesce(v_sheet ->> 'source_sheet_name', '') = ''
       or jsonb_typeof(v_sheet -> 'snapshot') <> 'object' then
      raise exception 'Invalid source sheet payload';
    end if;

    insert into public.import_sheet_runs (
      import_session_id, importer_id, source_sheet_name, status, detected_records, preview
    ) values (
      v_session_id,
      v_sheet ->> 'importer_id',
      v_sheet ->> 'source_sheet_name',
      'completed',
      coalesce((v_sheet ->> 'detected_records')::integer, 0),
      coalesce(v_sheet -> 'preview', '{}'::jsonb)
    ) returning id into v_sheet_run_id;

    insert into public.import_source_sheets (import_sheet_run_id, source_sheet_name, content)
    values (v_sheet_run_id, v_sheet ->> 'source_sheet_name', v_sheet -> 'snapshot');

    insert into public.import_operation_journal (
      import_sheet_run_id, operation_index, entity_type, operation, forward_payload, undo_payload, applied_at
    ) values (
      v_sheet_run_id, 0, 'import_source_sheets', 'insert', v_sheet -> 'snapshot',
      jsonb_build_object('archive_import_sheet_run_id', v_sheet_run_id), now()
    );
  end loop;

  return v_session_id;
end;
$$;

create or replace function public.undo_workbook_import(
  p_import_session_id uuid,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
begin
  select household_id into v_household_id
  from public.import_sessions
  where id = p_import_session_id and status = 'completed';
  if v_household_id is null or auth.uid() is null or not public.is_household_member(v_household_id) then
    raise exception 'Import session unavailable';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) not between 1 and 280 then
    raise exception 'An undo reason between 1 and 280 characters is required';
  end if;

  update public.import_source_sheets sheets
  set archived_at = now()
  from public.import_sheet_runs runs
  where sheets.import_sheet_run_id = runs.id
    and runs.import_session_id = p_import_session_id
    and sheets.archived_at is null;
  update public.import_operation_journal operations
  set undone_at = now()
  from public.import_sheet_runs runs
  where operations.import_sheet_run_id = runs.id
    and runs.import_session_id = p_import_session_id
    and operations.undone_at is null;
  update public.import_sheet_runs
  set status = 'undone'
  where import_session_id = p_import_session_id;
  update public.import_sessions
  set status = 'undone', cancelled_at = now(), cancellation_reason = trim(p_reason)
  where id = p_import_session_id;
end;
$$;

grant execute on function public.archive_workbook_import(uuid, text, text, jsonb) to authenticated;
grant execute on function public.undo_workbook_import(uuid, text) to authenticated;
