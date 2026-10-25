-- L2.5: personal, auditable significance metadata. Canonical source rows are
-- never copied and marking never broadens their audience.
begin;

create table public.timeline_significance_marks (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  source_kind text not null check (source_kind in ('financial_event','historical_analytic_line')),
  source_id uuid not null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  unique (household_id,user_id,source_kind,source_id),
  foreign key (household_id,user_id)
    references public.household_members(household_id,user_id) on delete cascade,
  foreign key (household_id,created_by)
    references public.household_members(household_id,user_id) on delete restrict
);

create index timeline_significance_marks_period_lookup
  on public.timeline_significance_marks(household_id,user_id,source_kind,source_id);

alter table public.timeline_significance_marks enable row level security;
revoke all on public.timeline_significance_marks from public,anon,authenticated;
grant select,insert,delete on public.timeline_significance_marks to authenticated;

create policy timeline_significance_marks_read_own
  on public.timeline_significance_marks for select to authenticated
  using (
    user_id=(select auth.uid())
    and public.is_household_member(household_id)
  );

create policy timeline_significance_marks_insert_visible_source
  on public.timeline_significance_marks for insert to authenticated
  with check (
    user_id=(select auth.uid())
    and created_by=(select auth.uid())
    and public.is_household_member(household_id)
    and (
      (source_kind='financial_event' and exists (
        select 1 from public.financial_events e
        where e.id=source_id and e.household_id=household_id
      ))
      or
      (source_kind='historical_analytic_line' and exists (
        select 1 from public.historical_analytic_lines l
        where l.id=source_id and l.household_id=household_id
      ))
    )
  );

create policy timeline_significance_marks_delete_own
  on public.timeline_significance_marks for delete to authenticated
  using (
    user_id=(select auth.uid())
    and created_by=(select auth.uid())
    and public.is_household_member(household_id)
  );

alter table public.timeline_significance_marks replica identity full;

comment on table public.timeline_significance_marks is
  'L2.5 personal significance metadata. A mark never copies a source event and never changes source visibility.';

commit;
