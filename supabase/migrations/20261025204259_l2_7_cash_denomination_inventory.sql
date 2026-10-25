-- L2.7 ACC-12/HIS-03: optional cash denomination evidence on the canonical observation.
create table if not exists public.cash_denominations (
  currency_code text not null,
  value_minor bigint not null check (value_minor > 0),
  kind text not null check (kind in ('banknote','coin')),
  label text not null,
  active boolean not null default true,
  primary key (currency_code,value_minor)
);

alter table public.cash_denominations enable row level security;
revoke all on table public.cash_denominations from public,anon,authenticated;

insert into public.cash_denominations(currency_code,value_minor,kind,label) values
  ('MAD',20000,'banknote','200 MAD'),
  ('MAD',10000,'banknote','100 MAD'),
  ('MAD',5000,'banknote','50 MAD'),
  ('MAD',2000,'banknote','20 MAD'),
  ('MAD',1000,'coin','10 MAD'),
  ('MAD',500,'coin','5 MAD'),
  ('MAD',200,'coin','2 MAD'),
  ('MAD',100,'coin','1 MAD'),
  ('MAD',50,'coin','0,50 MAD'),
  ('MAD',20,'coin','0,20 MAD'),
  ('MAD',10,'coin','0,10 MAD')
on conflict (currency_code,value_minor) do update
set kind=excluded.kind,label=excluded.label,active=true;

alter table public.account_balance_observations
  add column if not exists input_mode text not null default 'direct'
    check (input_mode in ('direct','denominations')),
  add column if not exists denomination_detail jsonb,
  add column if not exists observation_provenance text not null default 'manual_inventory',
  add column if not exists idempotency_key uuid;

create unique index if not exists account_balance_observations_idempotency_idx
  on public.account_balance_observations(household_id,created_by,idempotency_key)
  where idempotency_key is not null;

create or replace function public.record_cash_inventory_observation(
  p_account_id uuid,
  p_observed_at timestamptz,
  p_input_mode text,
  p_actual_balance numeric,
  p_denomination_detail jsonb,
  p_reason text,
  p_idempotency_key uuid
) returns uuid
language plpgsql security definer set search_path='' as $$
declare
  v_household_id uuid;
  v_kind text;
  v_currency text;
  v_theoretical numeric(14,2);
  v_total_minor bigint;
  v_observation_id uuid;
begin
  if (select auth.uid()) is null or p_idempotency_key is null then
    raise exception 'Authenticated idempotent inventory required';
  end if;
  select household_id,kind,currency_code into v_household_id,v_kind,v_currency
  from public.accounts where id=p_account_id and archived_at is null for update;
  if v_household_id is null or v_kind <> 'cash'
     or not public.is_household_member(v_household_id)
     or not private.can_discover_account(p_account_id,(select auth.uid()))
     or not private.can_read_account_balance(p_account_id,(select auth.uid())) then
    raise exception 'Cash position access denied';
  end if;
  if p_input_mode not in ('direct','denominations') or p_actual_balance is null or p_actual_balance < 0 then
    raise exception 'Invalid cash inventory';
  end if;
  if char_length(trim(coalesce(p_reason,''))) not between 1 and 280 then
    raise exception 'A reason between 1 and 280 characters is required';
  end if;
  if p_input_mode='denominations' then
    if jsonb_typeof(p_denomination_detail)<>'array' or jsonb_array_length(p_denomination_detail)=0 then
      raise exception 'Denomination detail is required';
    end if;
    if exists(select 1 from jsonb_array_elements(p_denomination_detail) x
      where x->>'currency_code'<>v_currency
         or (x->>'kind') not in ('banknote','coin')
         or (x->>'quantity')!~'^\d+$'
         or (x->>'value_minor')!~'^\d+$'
         or (x->>'quantity')::bigint<0 or (x->>'value_minor')::bigint<=0) then
      raise exception 'Invalid denomination detail';
    end if;
    if exists(
      select 1
      from jsonb_array_elements(p_denomination_detail) x
      left join public.cash_denominations d
        on d.currency_code=x->>'currency_code'
       and d.value_minor=(x->>'value_minor')::bigint
       and d.kind=x->>'kind'
       and d.active
      where d.currency_code is null
    ) then
      raise exception 'Unknown denomination for account currency';
    end if;
    select coalesce(sum((x->>'value_minor')::bigint*(x->>'quantity')::bigint),0)
      into v_total_minor from jsonb_array_elements(p_denomination_detail) x;
    if v_total_minor <> round(p_actual_balance*100)::bigint then
      raise exception 'Denomination total differs from observed balance';
    end if;
  elsif p_denomination_detail is not null then
    raise exception 'Direct inventory cannot contain denominations';
  end if;
  select id into v_observation_id from public.account_balance_observations
   where household_id=v_household_id and created_by=(select auth.uid())
     and idempotency_key=p_idempotency_key;
  if v_observation_id is not null then return v_observation_id; end if;
  select theoretical_balance into v_theoretical from public.account_ledger_balances
   where household_id=v_household_id and account_id=p_account_id;
  if v_theoretical is null then raise exception 'Theoretical balance unavailable'; end if;
  insert into public.account_balance_observations(
    household_id,account_id,observed_at,actual_balance,reason,created_by,
    theoretical_balance_snapshot,difference_snapshot,snapshot_version,
    input_mode,denomination_detail,observation_provenance,idempotency_key
  ) values (
    v_household_id,p_account_id,coalesce(p_observed_at,now()),p_actual_balance,
    trim(p_reason),(select auth.uid()),v_theoretical,p_actual_balance-v_theoretical,1,
    p_input_mode,case when p_input_mode='denominations' then p_denomination_detail else null end,
    'manual_cash_inventory',p_idempotency_key
  ) returning id into v_observation_id;
  return v_observation_id;
end;
$$;

revoke all on function public.record_cash_inventory_observation(uuid,timestamptz,text,numeric,jsonb,text,uuid) from public,anon;
grant execute on function public.record_cash_inventory_observation(uuid,timestamptz,text,numeric,jsonb,text,uuid) to authenticated;
