-- Owner-only enrichment of the existing L3B cycle domain. Predictions are
-- computed by the client from owner-visible observations and are never stored
-- as medical facts. The existing shared projection remains dates/phases only.
create table public.member_cycle_private_entries (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  owner_user_id uuid not null,
  occurred_on date not null,
  category text not null check (category in (
    'symptom','mood','sleep','energy','stress','libido','skin','appetite',
    'digestion','discharge','temperature','weight','spotting',
    'contraception','intimacy'
  )),
  payload jsonb not null default '{}'::jsonb,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  foreign key (household_id, owner_user_id)
    references public.household_members(household_id, user_id),
  check (jsonb_typeof(payload) = 'object')
);

create index member_cycle_private_entries_owner_idx
  on public.member_cycle_private_entries(
    household_id, owner_user_id, occurred_on desc
  ) where archived_at is null;

alter table public.member_cycle_private_entries enable row level security;

create policy member_cycle_private_entries_owner_read
  on public.member_cycle_private_entries for select to authenticated
  using (owner_user_id = (select auth.uid()));

create policy member_cycle_private_entries_owner_create
  on public.member_cycle_private_entries for insert to authenticated
  with check (
    owner_user_id = (select auth.uid())
    and public.is_household_member(household_id)
  );

create policy member_cycle_private_entries_owner_update
  on public.member_cycle_private_entries for update to authenticated
  using (owner_user_id = (select auth.uid()))
  with check (owner_user_id = (select auth.uid()));

create policy member_cycle_private_entries_owner_delete
  on public.member_cycle_private_entries for delete to authenticated
  using (owner_user_id = (select auth.uid()));

revoke all on public.member_cycle_private_entries from public, anon;
grant select, insert, update, delete
  on public.member_cycle_private_entries to authenticated;

comment on table public.member_cycle_private_entries is
  'Strictly owner-only cycle journal. Never included in household projections, exports, assistant context, search, notifications or raw Realtime.';
