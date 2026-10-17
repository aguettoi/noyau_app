-- R2.13.1: one shared, restart-safe draft for the opening account x envelope
-- inventory. This table is analytical working state only. It never creates a
-- FinancialEvent, GL posting, envelope movement or final position batch.
begin;

create table public.envelope_account_initial_position_drafts (
  household_id uuid not null references public.households(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete restrict,
  envelope_id uuid not null references public.envelopes(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  provenance text not null check (
    provenance in ('human_confirmation','opening_inventory_arbitration')
  ),
  provenance_reference text not null check (length(trim(provenance_reference)) > 0),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (household_id,account_id,envelope_id)
);

create index envelope_account_initial_position_drafts_account_idx
  on public.envelope_account_initial_position_drafts(account_id);
create index envelope_account_initial_position_drafts_envelope_idx
  on public.envelope_account_initial_position_drafts(envelope_id);

alter table public.envelope_account_initial_position_drafts enable row level security;
revoke all on public.envelope_account_initial_position_drafts from public,anon,authenticated;
grant select on public.envelope_account_initial_position_drafts to authenticated;

create policy envelope_account_initial_position_drafts_read
  on public.envelope_account_initial_position_drafts
  for select to authenticated
  using (public.is_household_member(household_id));

create or replace function public.envelope_account_initial_position_draft(
  p_household_id uuid
) returns jsonb
language plpgsql security definer set search_path=public,auth as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'account_id',account_id,
    'envelope_id',envelope_id,
    'amount',amount,
    'provenance',provenance,
    'provenance_reference',provenance_reference,
    'updated_by',updated_by,
    'updated_at',updated_at
  ) order by envelope_id,account_id),'[]'::jsonb)
  into v_result
  from public.envelope_account_initial_position_drafts
  where household_id=p_household_id;
  return v_result;
end $$;

create or replace function public.save_envelope_account_initial_position_draft(
  p_household_id uuid,
  p_positions jsonb
) returns integer
language plpgsql security definer set search_path=public,auth as $$
declare
  v_item jsonb;
  v_account uuid;
  v_envelope uuid;
  v_amount numeric(14,2);
  v_provenance text;
  v_reference text;
  v_count integer;
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_positions is null or jsonb_typeof(p_positions)<>'array' then
    raise exception 'Positions must be an array';
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
  create temporary table if not exists pg_temp.r2131_draft(
    account_id uuid,
    envelope_id uuid,
    amount numeric(14,2),
    provenance text,
    provenance_reference text,
    primary key(account_id,envelope_id)
  ) on commit drop;
  truncate pg_temp.r2131_draft;

  for v_item in select value from jsonb_array_elements(p_positions) loop
    v_account := (v_item->>'account_id')::uuid;
    v_envelope := (v_item->>'envelope_id')::uuid;
    v_amount := (v_item->>'amount')::numeric;
    v_provenance := case v_item->>'provenance'
      when 'humanConfirmation' then 'human_confirmation'
      when 'human_confirmation' then 'human_confirmation'
      when 'openingInventoryArbitration' then 'opening_inventory_arbitration'
      when 'opening_inventory_arbitration' then 'opening_inventory_arbitration'
      else null end;
    v_reference := nullif(trim(v_item->>'provenance_reference'),'');
    if v_amount<=0 then raise exception 'Draft amount must be positive'; end if;
    if v_provenance is null then raise exception 'Invalid draft provenance'; end if;
    if v_reference is null then raise exception 'Draft provenance reference is required'; end if;
    if not exists(
      select 1 from public.accounts
      where id=v_account and household_id=p_household_id
        and archived_at is null and not is_system
    ) then raise exception 'Invalid account'; end if;
    if not exists(
      select 1 from public.envelopes
      where id=v_envelope and household_id=p_household_id and archived_at is null
    ) then raise exception 'Invalid envelope'; end if;
    insert into pg_temp.r2131_draft
      values(v_account,v_envelope,v_amount,v_provenance,v_reference);
  end loop;

  delete from public.envelope_account_initial_position_drafts
  where household_id=p_household_id;
  insert into public.envelope_account_initial_position_drafts(
    household_id,account_id,envelope_id,amount,provenance,
    provenance_reference,updated_by
  )
  select p_household_id,account_id,envelope_id,amount,provenance,
         provenance_reference,auth.uid()
  from pg_temp.r2131_draft;
  get diagnostics v_count=row_count;
  return v_count;
end $$;

revoke all on function public.envelope_account_initial_position_draft(uuid)
  from public,anon;
grant execute on function public.envelope_account_initial_position_draft(uuid)
  to authenticated;
revoke all on function public.save_envelope_account_initial_position_draft(uuid,jsonb)
  from public,anon;
grant execute on function public.save_envelope_account_initial_position_draft(uuid,jsonb)
  to authenticated;

comment on table public.envelope_account_initial_position_drafts is
  'R2.13.1 shared analytical draft. Separate from evidence and final position batches; creates no financial write.';

commit;
