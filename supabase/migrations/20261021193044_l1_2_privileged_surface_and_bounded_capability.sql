-- L1.2: reduce the client privileged surface and expose a bounded,
-- business-intent capability decision. No arbitrary threshold RPC exists.

revoke execute on function public.is_active_household_member(uuid, uuid)
  from authenticated;
revoke execute on function public.create_shopping_item(
  uuid, text, numeric, text, date, uuid, uuid, integer
) from authenticated;
revoke execute on function public.update_shopping_item(
  uuid, uuid, text, numeric, text, date, uuid, uuid, integer
) from authenticated;
revoke execute on function public.execute_monthly_account_reallocation(
  uuid, date, text, jsonb, uuid
) from authenticated;
revoke execute on function public.list_account_privacy_summaries(uuid)
  from authenticated;
revoke execute on function public.save_budget_allocation_run(
  uuid, uuid, uuid, uuid, numeric, numeric, numeric, jsonb
) from authenticated;

create table if not exists private.private_funding_capability_intents (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  account_id uuid not null references public.accounts(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  purpose_kind text not null,
  purpose_id uuid not null,
  requested_amount numeric(18,2) not null check (requested_amount > 0),
  expires_at timestamptz not null,
  idempotency_key uuid not null,
  created_at timestamptz not null default now(),
  last_evaluated_at timestamptz,
  evaluation_count integer not null default 0,
  unique (owner_user_id, idempotency_key),
  check (purpose_kind in ('shopping_item', 'budget_goal', 'priority_plan')),
  check (expires_at > created_at),
  check (expires_at <= created_at + interval '30 days')
);

alter table private.private_funding_capability_intents enable row level security;
revoke all on table private.private_funding_capability_intents
  from public, anon, authenticated;

create table if not exists private.private_funding_capability_audit (
  id uuid primary key default gen_random_uuid(),
  intent_id uuid not null references private.private_funding_capability_intents(id)
    on delete cascade,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  decision text not null check (
    decision in ('ALLOWED', 'NOT_ALLOWED', 'REQUIRES_OWNER_ACTION')
  ),
  evaluated_at timestamptz not null default now()
);

alter table private.private_funding_capability_audit enable row level security;
revoke all on table private.private_funding_capability_audit
  from public, anon, authenticated;

create or replace function public.create_private_funding_capability_intent(
  p_account_id uuid,
  p_purpose_kind text,
  p_purpose_id uuid,
  p_requested_amount numeric,
  p_expires_at timestamptz,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_household_id uuid;
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;
  if p_requested_amount is null or p_requested_amount <= 0 then
    raise exception 'A positive business amount is required';
  end if;
  if p_expires_at <= now() or p_expires_at > now() + interval '30 days' then
    raise exception 'Capability intent expiry must be future and within 30 days';
  end if;
  if p_purpose_kind not in ('shopping_item', 'budget_goal', 'priority_plan') then
    raise exception 'Unsupported capability purpose';
  end if;

  select a.household_id into v_household_id
  from public.accounts a
  where a.id = p_account_id;
  if v_household_id is null
     or not private.account_is_holder(p_account_id, v_actor) then
    raise exception 'Only an account holder can authorize a capability intent';
  end if;

  if (p_purpose_kind = 'shopping_item' and not exists (
        select 1 from public.shopping_items x
        where x.id = p_purpose_id and x.household_id = v_household_id
      ))
     or (p_purpose_kind = 'budget_goal' and not exists (
        select 1 from public.budget_goals x
        where x.id = p_purpose_id and x.household_id = v_household_id
      ))
     or (p_purpose_kind = 'priority_plan' and not exists (
        select 1 from public.priority_plans x
        where x.id = p_purpose_id and x.household_id = v_household_id
      )) then
    raise exception 'Business purpose is not in the account household';
  end if;

  insert into private.private_funding_capability_intents (
    household_id, account_id, owner_user_id, purpose_kind, purpose_id,
    requested_amount, expires_at, idempotency_key
  ) values (
    v_household_id, p_account_id, v_actor, p_purpose_kind, p_purpose_id,
    round(p_requested_amount, 2), p_expires_at, p_idempotency_key
  )
  on conflict (owner_user_id, idempotency_key) do update
    set idempotency_key = excluded.idempotency_key
  returning id into v_id;

  if not exists (
    select 1 from private.private_funding_capability_intents i
    where i.id = v_id
      and i.account_id = p_account_id
      and i.purpose_kind = p_purpose_kind
      and i.purpose_id = p_purpose_id
      and i.requested_amount = round(p_requested_amount, 2)
  ) then
    raise exception 'Idempotency key already used for another intent';
  end if;
  return v_id;
end;
$$;

create or replace function public.evaluate_private_funding_capability(
  p_intent_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := auth.uid();
  v_intent private.private_funding_capability_intents%rowtype;
  v_balance numeric;
  v_decision text;
begin
  if v_actor is null then
    raise exception 'Authentication required';
  end if;
  select * into v_intent
  from private.private_funding_capability_intents
  where id = p_intent_id
  for update;
  if not found then
    raise exception 'Capability intent not found';
  end if;
  if not public.is_household_member(v_intent.household_id) then
    raise exception 'Household access denied';
  end if;

  if v_intent.expires_at <= now() then
    v_decision := 'REQUIRES_OWNER_ACTION';
  else
    select b.theoretical_balance into v_balance
    from public.account_ledger_balances b
    where b.account_id = v_intent.account_id;
    v_decision := case
      when coalesce(v_balance, 0) >= v_intent.requested_amount then 'ALLOWED'
      else 'NOT_ALLOWED'
    end;
  end if;

  update private.private_funding_capability_intents
  set last_evaluated_at = now(), evaluation_count = evaluation_count + 1
  where id = v_intent.id;
  insert into private.private_funding_capability_audit (
    intent_id, actor_user_id, decision
  ) values (v_intent.id, v_actor, v_decision);
  return v_decision;
end;
$$;

revoke all on function public.create_private_funding_capability_intent(
  uuid, text, uuid, numeric, timestamptz, uuid
) from public, anon;
grant execute on function public.create_private_funding_capability_intent(
  uuid, text, uuid, numeric, timestamptz, uuid
) to authenticated;
revoke all on function public.evaluate_private_funding_capability(uuid)
  from public, anon;
grant execute on function public.evaluate_private_funding_capability(uuid)
  to authenticated;
