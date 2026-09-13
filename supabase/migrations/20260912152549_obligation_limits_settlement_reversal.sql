begin;

-- Phase 1 obligation invariant:
--   remaining = initial - (gross settlements - settlement reversals)
--                       - write-offs.
-- Settlement reversals are immutable compensations of a settlement, not a
-- second settlement.  They must therefore be deducted by both deferred
-- guards, just as they already are by obligation_balances.
--
-- adjustment_kind = 'reversal' is deliberately excluded here.  No Phase 1
-- RPC creates it: write-off reversal has its own future design and must not
-- acquire an implicit accounting meaning through this migration.
create or replace function public.assert_obligation_settlement_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_initial numeric(14, 2);
  v_gross_settlements numeric(14, 2);
  v_settlement_reversals numeric(14, 2);
  v_writeoffs numeric(14, 2);
begin
  select initial_amount
    into v_initial
  from public.obligations
  where id = new.obligation_id
    and household_id = new.household_id;

  select coalesce(sum(amount), 0)
    into v_gross_settlements
  from public.obligation_settlements
  where obligation_id = new.obligation_id
    and household_id = new.household_id;

  select coalesce(sum(amount), 0)
    into v_settlement_reversals
  from public.obligation_settlement_reversals
  where obligation_id = new.obligation_id
    and household_id = new.household_id;

  select coalesce(sum(amount) filter (where adjustment_kind = 'writeoff'), 0)
    into v_writeoffs
  from public.obligation_adjustments
  where obligation_id = new.obligation_id
    and household_id = new.household_id;

  if v_initial is null
     or v_gross_settlements - v_settlement_reversals + v_writeoffs > v_initial then
    raise exception 'An obligation cannot be settled above its remaining amount';
  end if;

  return null;
end;
$$;

create or replace function public.assert_obligation_adjustment_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_initial numeric(14, 2);
  v_gross_settlements numeric(14, 2);
  v_settlement_reversals numeric(14, 2);
  v_writeoffs numeric(14, 2);
begin
  select initial_amount
    into v_initial
  from public.obligations
  where id = new.obligation_id
    and household_id = new.household_id;

  select coalesce(sum(amount), 0)
    into v_gross_settlements
  from public.obligation_settlements
  where obligation_id = new.obligation_id
    and household_id = new.household_id;

  select coalesce(sum(amount), 0)
    into v_settlement_reversals
  from public.obligation_settlement_reversals
  where obligation_id = new.obligation_id
    and household_id = new.household_id;

  select coalesce(sum(amount) filter (where adjustment_kind = 'writeoff'), 0)
    into v_writeoffs
  from public.obligation_adjustments
  where obligation_id = new.obligation_id
    and household_id = new.household_id;

  if v_initial is null
     or v_gross_settlements - v_settlement_reversals + v_writeoffs > v_initial then
    raise exception 'An obligation cannot exceed its initial amount through settlements and adjustments';
  end if;

  return null;
end;
$$;

commit;
