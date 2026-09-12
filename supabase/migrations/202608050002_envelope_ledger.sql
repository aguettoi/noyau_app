-- Sprint 2.2, lot 1: immutable envelope ledger.
-- This migration is additive and must be applied manually after Sprint 2.1.

begin;

alter table public.envelopes
  add column if not exists is_system boolean not null default false,
  add column if not exists system_code text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.envelopes'::regclass
      and conname = 'envelopes_id_household_unique'
  ) then
    alter table public.envelopes
      add constraint envelopes_id_household_unique unique (id, household_id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.envelopes'::regclass
      and conname = 'envelopes_system_code_check'
  ) then
    alter table public.envelopes
      add constraint envelopes_system_code_check check (
        (is_system and system_code is not null)
        or (not is_system and system_code is null)
      );
  end if;
end;
$$;

create unique index if not exists envelopes_household_system_code_unique
  on public.envelopes(household_id, system_code)
  where system_code is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.financial_transactions'::regclass
      and conname = 'financial_transactions_id_household_unique'
  ) then
    alter table public.financial_transactions
      add constraint financial_transactions_id_household_unique
      unique (id, household_id);
  end if;
end;
$$;

create table if not exists public.envelope_movements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  envelope_id uuid not null,
  financial_transaction_id uuid,
  movement_group_id uuid not null,
  movement_type text not null check (movement_type in (
    'allocation', 'consumption', 'transfer_out', 'transfer_in', 'refund',
    'adjustment', 'reversal'
  )),
  direction text not null check (direction in ('inflow', 'outflow')),
  amount numeric(14, 2) not null check (amount > 0),
  occurred_at timestamptz not null,
  description text not null check (char_length(trim(description)) between 1 and 280),
  reversal_of uuid,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  constraint envelope_movements_envelope_household_fk
    foreign key (envelope_id, household_id)
    references public.envelopes(id, household_id) on delete restrict,
  constraint envelope_movements_transaction_household_fk
    foreign key (financial_transaction_id, household_id)
    references public.financial_transactions(id, household_id) on delete restrict,
  constraint envelope_movements_creator_household_fk
    foreign key (household_id, created_by)
    references public.household_members(household_id, user_id) on delete restrict,
  constraint envelope_movements_reversal_household_fk
    foreign key (reversal_of, household_id)
    references public.envelope_movements(id, household_id) on delete restrict,
  constraint envelope_movements_id_household_unique unique (id, household_id),
  constraint envelope_movements_type_direction_check check (
    (movement_type in ('allocation', 'transfer_in', 'refund') and direction = 'inflow')
    or (movement_type in ('consumption', 'transfer_out') and direction = 'outflow')
    or movement_type in ('adjustment', 'reversal')
  ),
  constraint envelope_movements_reversal_check check (
    (movement_type = 'reversal' and reversal_of is not null)
    or (movement_type <> 'reversal' and reversal_of is null)
  )
);

create index if not exists envelope_movements_household_occurred_idx
  on public.envelope_movements(household_id, occurred_at desc, created_at desc);
create index if not exists envelope_movements_envelope_occurred_idx
  on public.envelope_movements(envelope_id, occurred_at desc, created_at desc);
create index if not exists envelope_movements_transaction_idx
  on public.envelope_movements(financial_transaction_id)
  where financial_transaction_id is not null;
create index if not exists envelope_movements_group_idx
  on public.envelope_movements(movement_group_id);
create unique index if not exists envelope_movements_single_reversal_idx
  on public.envelope_movements(reversal_of)
  where reversal_of is not null;

alter table public.envelope_movements enable row level security;

revoke all on table public.envelope_movements from public, anon;
revoke insert, update, delete, truncate on table public.envelope_movements
  from authenticated;
grant select on table public.envelope_movements to authenticated;

drop policy if exists "members read envelope movements" on public.envelope_movements;
create policy "members read envelope movements"
  on public.envelope_movements for select
  using (public.is_household_member(household_id));

create or replace function public.prevent_envelope_movement_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Envelope movements are immutable; create a reversal instead';
end;
$$;

drop trigger if exists envelope_movements_immutable on public.envelope_movements;
create trigger envelope_movements_immutable
before update or delete on public.envelope_movements
for each row execute function public.prevent_envelope_movement_mutation();

create or replace function public.protect_system_envelope()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' and old.is_system then
    raise exception 'System envelopes cannot be deleted';
  end if;
  if old.is_system and (
    new.is_system is distinct from old.is_system
    or new.system_code is distinct from old.system_code
    or new.name is distinct from old.name
    or new.household_id is distinct from old.household_id
    or new.archived_at is not null
  ) then
    raise exception 'System envelopes cannot be renamed, archived or deleted';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists envelopes_protect_system on public.envelopes;
create trigger envelopes_protect_system
before update or delete on public.envelopes
for each row execute function public.protect_system_envelope();

create or replace function public.ensure_household_system_envelope(
  p_household_id uuid,
  p_system_code text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_envelope_id uuid;
  v_name text := case p_system_code
    when 'to_allocate' then 'À répartir'
    else null
  end;
begin
  if v_name is null then
    raise exception 'Unsupported system envelope code';
  end if;

  select id into v_envelope_id
  from public.envelopes
  where household_id = p_household_id and system_code = p_system_code;
  if found then
    return v_envelope_id;
  end if;

  insert into public.envelopes(household_id, name, is_system, system_code)
  values (p_household_id, v_name, true, p_system_code)
  returning id into v_envelope_id;
  return v_envelope_id;
end;
$$;

create or replace function public.assert_envelope_movement_group(
  p_movement_group_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_household_id uuid;
  v_count integer;
  v_type text;
  v_transaction_id uuid;
  v_transaction_type text;
  v_transaction_amount numeric(14, 2);
  v_total numeric(14, 2);
  v_inflow numeric(14, 2);
  v_outflow numeric(14, 2);
  v_all_to_allocate boolean;
begin
  select household_id, count(*), min(movement_type)
  into v_household_id, v_count, v_type
  from public.envelope_movements
  where movement_group_id = p_movement_group_id
  group by household_id;
  if not found then
    return;
  end if;
  if exists (
    select 1
    from public.envelope_movements
    where movement_group_id = p_movement_group_id
      and household_id <> v_household_id
  ) then
    raise exception 'An envelope movement group cannot span households';
  end if;

  select financial_transaction_id into v_transaction_id
  from public.envelope_movements
  where movement_group_id = p_movement_group_id
  limit 1;
  if exists (
    select 1
    from public.envelope_movements
    where movement_group_id = p_movement_group_id
      and financial_transaction_id is distinct from v_transaction_id
  ) then
    raise exception 'Envelope movement group must reference one financial transaction';
  end if;

  if v_type in ('consumption', 'allocation', 'refund', 'adjustment', 'reversal') and exists (
    select 1
    from public.envelope_movements
    where movement_group_id = p_movement_group_id
      and movement_type <> v_type
  ) then
    raise exception 'Envelope movement group contains incompatible types';
  end if;

  if v_type = 'consumption' then
    select type, amount into v_transaction_type, v_transaction_amount
    from public.financial_transactions
    where id = v_transaction_id and household_id = v_household_id;
    select sum(amount) into v_total
    from public.envelope_movements
    where movement_group_id = p_movement_group_id;
    if v_transaction_id is null or v_transaction_type <> 'expense'
       or v_total <> v_transaction_amount then
      raise exception 'Expense envelope allocations must equal the expense amount';
    end if;
  elsif v_type = 'allocation' then
    select type, amount into v_transaction_type, v_transaction_amount
    from public.financial_transactions
    where id = v_transaction_id and household_id = v_household_id;
    select sum(movements.amount), bool_and(envelopes.system_code = 'to_allocate')
    into v_total, v_all_to_allocate
    from public.envelope_movements movements
    join public.envelopes on envelopes.id = movements.envelope_id
    where movements.movement_group_id = p_movement_group_id;
    if v_count <> 1 or v_transaction_id is null or v_transaction_type <> 'income'
       or v_total <> v_transaction_amount or not coalesce(v_all_to_allocate, false) then
      raise exception 'Income must allocate its full amount to À répartir';
    end if;
  elsif v_type in ('transfer_in', 'transfer_out') then
    select count(*), sum(case when direction = 'inflow' then amount else 0 end),
      sum(case when direction = 'outflow' then amount else 0 end)
    into v_count, v_inflow, v_outflow
    from public.envelope_movements
    where movement_group_id = p_movement_group_id;
    if v_count <> 2 or v_inflow <> v_outflow or exists (
      select 1
      from public.envelope_movements
      where movement_group_id = p_movement_group_id
        and financial_transaction_id is not null
    ) or (select count(*) from public.envelope_movements
      where movement_group_id = p_movement_group_id
        and movement_type = 'transfer_in') <> 1
    or (select count(*) from public.envelope_movements
      where movement_group_id = p_movement_group_id
        and movement_type = 'transfer_out') <> 1
    or (select count(distinct envelope_id)
      from public.envelope_movements
      where movement_group_id = p_movement_group_id) <> 2 then
      raise exception 'Envelope transfer must have two balanced distinct envelopes';
    end if;
  elsif v_type = 'reversal' then
    if exists (
      select 1
      from public.envelope_movements reversals
      join public.envelope_movements originals on originals.id = reversals.reversal_of
      where reversals.movement_group_id = p_movement_group_id
        and (
          originals.household_id <> reversals.household_id
          or originals.amount <> reversals.amount
          or originals.direction = reversals.direction
        )
    ) then
      raise exception 'Envelope reversal must invert one original movement exactly';
    end if;
  end if;
end;
$$;

create or replace function public.assert_envelope_movement_group_trigger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.assert_envelope_movement_group(new.movement_group_id);
  return null;
end;
$$;

drop trigger if exists envelope_movements_group_valid on public.envelope_movements;
create constraint trigger envelope_movements_group_valid
after insert on public.envelope_movements
deferrable initially deferred
for each row execute function public.assert_envelope_movement_group_trigger();

create or replace view public.envelope_ledger_balances
with (security_invoker = true)
as
select
  envelopes.household_id,
  envelopes.id as envelope_id,
  envelopes.name as envelope_name,
  envelopes.is_system,
  envelopes.system_code,
  coalesce(sum(case when movements.direction = 'inflow' then movements.amount else 0 end), 0)
    ::numeric(14, 2) as inflows,
  coalesce(sum(case when movements.direction = 'outflow' then movements.amount else 0 end), 0)
    ::numeric(14, 2) as outflows,
  coalesce(sum(case when movements.direction = 'inflow' then movements.amount else -movements.amount end), 0)
    ::numeric(14, 2) as balance,
  max(movements.occurred_at) as last_movement_at
from public.envelopes
left join public.envelope_movements movements on movements.envelope_id = envelopes.id
group by envelopes.household_id, envelopes.id, envelopes.name,
  envelopes.is_system, envelopes.system_code;

create or replace function public.create_envelope_transfer(
  p_household_id uuid,
  p_source_envelope_id uuid,
  p_destination_envelope_id uuid,
  p_amount numeric,
  p_occurred_at timestamptz,
  p_description text
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid := gen_random_uuid();
begin
  if auth.uid() is null or not public.is_household_member(p_household_id) then
    raise exception 'Household access denied';
  end if;
  if p_source_envelope_id is null or p_destination_envelope_id is null
     or p_source_envelope_id = p_destination_envelope_id then
    raise exception 'Two different envelopes are required';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'A strictly positive amount is required';
  end if;
  if char_length(trim(coalesce(p_description, ''))) not between 1 and 280 then
    raise exception 'A description between 1 and 280 characters is required';
  end if;
  if not exists (
    select 1 from public.envelopes
    where id = p_source_envelope_id and household_id = p_household_id
      and archived_at is null
  ) or not exists (
    select 1 from public.envelopes
    where id = p_destination_envelope_id and household_id = p_household_id
      and archived_at is null
  ) then
    raise exception 'Envelope does not belong to household or is archived';
  end if;

  insert into public.envelope_movements(
    household_id, envelope_id, movement_group_id, movement_type, direction,
    amount, occurred_at, description, created_by
  ) values
    (p_household_id, p_source_envelope_id, v_group_id, 'transfer_out', 'outflow',
      p_amount, coalesce(p_occurred_at, now()), trim(p_description), auth.uid()),
    (p_household_id, p_destination_envelope_id, v_group_id, 'transfer_in', 'inflow',
      p_amount, coalesce(p_occurred_at, now()), trim(p_description), auth.uid());

  return v_group_id;
end;
$$;

grant select on public.envelope_ledger_balances to authenticated;
revoke all on function public.ensure_household_system_envelope(uuid, text)
  from public, anon;
revoke all on function public.create_envelope_transfer(uuid, uuid, uuid, numeric, timestamptz, text)
  from public, anon;
grant execute on function public.create_envelope_transfer(uuid, uuid, uuid, numeric, timestamptz, text)
  to authenticated;

commit;
