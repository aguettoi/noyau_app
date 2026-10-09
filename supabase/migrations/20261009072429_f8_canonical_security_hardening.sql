begin;

-- Public functions are not anonymous APIs. Historical migrations occasionally
-- relied on PostgreSQL's default PUBLIC EXECUTE grant; keep the authenticated
-- grants already recorded on V1 entry points and remove the inherited surface.
revoke execute on all functions in schema public from public, anon;
alter default privileges for role postgres in schema public
  revoke execute on functions from public;

-- These entry points predate the FinancialEvent orchestration. They remain in
-- place so historical migrations and records stay interpretable, but no new
-- client mutation may use them.
revoke execute on function public.create_financial_transaction(
  uuid, uuid, text, timestamptz, text, jsonb
) from authenticated;
revoke execute on function public.create_ledger_transaction(
  uuid, text, timestamptz, text, numeric, uuid, uuid, uuid, text, text
) from authenticated;
revoke execute on function public.create_financial_transaction_with_envelopes(
  uuid, text, timestamptz, text, numeric, uuid, uuid, uuid, text, text, jsonb
) from authenticated;
revoke execute on function public.create_envelope_transfer(
  uuid, uuid, uuid, numeric, timestamptz, text
) from authenticated;

-- CSV import V0 can overwrite accounts.opening_balance and create envelope
-- openings outside the certified cutover pipeline. Preview/parsing remains
-- available, while new materialisation must use the canonical cutover RPCs.
revoke execute on function public.execute_accounts_import(uuid, uuid, jsonb)
  from authenticated;
revoke execute on function public.import_household_envelopes(uuid, jsonb, uuid)
  from authenticated;

-- Trigger and orchestration helpers are implementation details, not client
-- APIs. Their owning SECURITY DEFINER functions and triggers keep working.
revoke execute on function public.assert_account_ownership(uuid),
  public.assert_account_ownership_trigger(),
  public.assert_budget_goal_envelope(uuid, uuid, uuid),
  public.assert_envelope_movement_group(uuid),
  public.assert_envelope_movement_group_trigger(),
  public.assert_envelope_opening_group(uuid),
  public.assert_envelope_opening_group_trigger(),
  public.assert_household_access(uuid),
  public.assert_obligation_adjustment_limit(),
  public.assert_obligation_adjustment_reversal_source(),
  public.assert_obligation_settlement_limit(),
  public.assert_obligation_settlement_reversal_limit(),
  public.ensure_financial_event_system_account(uuid, text),
  public.ensure_household_ledger_system_account(uuid, text),
  public.ensure_household_system_envelope(uuid, text),
  public.protect_budget_allocation_run_line_snapshot(),
  public.protect_budget_allocation_run_snapshot(),
  public.write_audit_event()
from authenticated;

create or replace function public.prevent_legacy_account_opening_balance_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT' and coalesce(new.opening_balance, 0) <> 0 then
    raise exception 'Account opening balances must be posted through a canonical opening event';
  end if;
  if tg_op = 'UPDATE'
     and new.opening_balance is distinct from old.opening_balance then
    raise exception 'Stored account opening balances are immutable legacy metadata';
  end if;
  return new;
end;
$$;

revoke execute on function public.prevent_legacy_account_opening_balance_mutation()
  from public, anon, authenticated;

drop trigger if exists accounts_opening_balance_legacy_guard on public.accounts;
create trigger accounts_opening_balance_legacy_guard
before insert or update of opening_balance on public.accounts
for each row execute function public.prevent_legacy_account_opening_balance_mutation();

-- Ledger rows and their orchestration records are written only by the
-- SECURITY DEFINER canonical APIs. RLS already denies direct writes; explicit
-- privilege revocation adds a second barrier and documents the contract.
revoke insert, update, delete on table
  public.accounts,
  public.account_holders,
  public.financial_events,
  public.financial_transactions,
  public.financial_transaction_lines,
  public.envelopes,
  public.envelope_movements,
  public.obligations,
  public.obligation_settlements,
  public.obligation_settlement_reversals,
  public.obligation_adjustments,
  public.member_compensations,
  public.member_compensation_actions,
  public.member_compensation_allocations,
  public.account_balance_observations,
  public.account_reconciliation_resolutions,
  public.reconciliation_regularization_allocations,
  public.daily_operation_reversals
from anon, authenticated;

commit;
