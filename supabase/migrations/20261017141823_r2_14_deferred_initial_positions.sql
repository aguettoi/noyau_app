-- R2.14: persist envelopes whose opening account location is intentionally
-- deferred. This is analytical workflow state only: no account, envelope,
-- FinancialEvent, GL posting or envelope movement is created.
begin;

create table public.envelope_account_initial_position_unknowns (
  household_id uuid not null references public.households(id) on delete cascade,
  envelope_id uuid not null references public.envelopes(id) on delete cascade,
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (household_id,envelope_id)
);

alter table public.envelope_account_initial_position_unknowns enable row level security;
revoke all on public.envelope_account_initial_position_unknowns from public,anon,authenticated;
grant select on public.envelope_account_initial_position_unknowns to authenticated;

create policy envelope_account_initial_position_unknowns_read
  on public.envelope_account_initial_position_unknowns
  for select to authenticated
  using (public.is_household_member(household_id));

create or replace function public.envelope_account_initial_position_unknowns(
  p_household_id uuid
) returns jsonb
language plpgsql security definer set search_path=public,auth as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  select coalesce(jsonb_agg(envelope_id order by envelope_id),'[]'::jsonb)
  into v_result
  from public.envelope_account_initial_position_unknowns
  where household_id=p_household_id;
  return v_result;
end $$;

create or replace function public.save_envelope_account_initial_position_unknowns(
  p_household_id uuid,
  p_envelope_ids jsonb
) returns integer
language plpgsql security definer set search_path=public,auth as $$
declare v_envelope uuid; v_count integer;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_envelope_ids is null or jsonb_typeof(p_envelope_ids)<>'array' then
    raise exception 'Envelope ids must be an array';
  end if;
  if exists(
    select 1 from public.envelope_account_position_batches
    where household_id=p_household_id and batch_kind='explicit_snapshot'
  ) then
    raise exception 'The initial position matrix already exists';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('r2-initial-position-draft:'||p_household_id::text,0)
  );
  create temporary table if not exists pg_temp.r214_unknowns(
    envelope_id uuid primary key
  ) on commit drop;
  truncate pg_temp.r214_unknowns;
  for v_envelope in
    select value::uuid from jsonb_array_elements_text(p_envelope_ids)
  loop
    if not exists(
      select 1 from public.envelopes
      where id=v_envelope and household_id=p_household_id and archived_at is null
    ) then raise exception 'Invalid envelope'; end if;
    insert into pg_temp.r214_unknowns values(v_envelope) on conflict do nothing;
  end loop;

  delete from public.envelope_account_initial_position_unknowns
  where household_id=p_household_id;
  insert into public.envelope_account_initial_position_unknowns(
    household_id,envelope_id,updated_by
  )
  select p_household_id,envelope_id,auth.uid() from pg_temp.r214_unknowns;
  get diagnostics v_count=row_count;
  return v_count;
end $$;

revoke all on function public.envelope_account_initial_position_unknowns(uuid)
  from public,anon;
grant execute on function public.envelope_account_initial_position_unknowns(uuid)
  to authenticated;
revoke all on function public.save_envelope_account_initial_position_unknowns(uuid,jsonb)
  from public,anon;
grant execute on function public.save_envelope_account_initial_position_unknowns(uuid,jsonb)
  to authenticated;

comment on table public.envelope_account_initial_position_unknowns is
  'R2.14 deferred opening-location questions. Never represents a known position or financial movement.';

commit;
