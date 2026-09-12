-- Sandbox-only, one-time, auditable regularization for the historical fixture
-- "TEST REVERSAL DETTE".  It preserves the original settlement and three
-- reversal records.  It creates no settlement, reversal, obligation adjustment,
-- account-envelope movement, or budget object.
--
-- The original reversal postings (20 + 10 + 70) incorrectly repeated the
-- settlement side.  This script creates one explicit compensating ledger
-- transaction: debit TESTOJ / credit Système — Dettes for 100.00 MAD.
--
-- The fixed idempotency key makes reruns safe.  It is intentionally limited to
-- the one named Sandbox fixture and aborts if its expected history differs.

begin;

do $regularization$
declare
  v_household_id uuid;
  v_actor_id uuid;
  v_obligation_id uuid;
  v_settlement_id uuid;
  v_original_tx_id uuid;
  v_testoj_id uuid;
  v_debt_system_id uuid;
  v_event_id uuid;
  v_tx_id uuid;
  v_existing_event uuid;
  v_reversal_total numeric(14,2);
  v_historical_bad_side_total numeric(14,2);
  v_idempotency_key constant uuid := 'ed77317d-2eed-48d7-bc60-c4c4a684dec0';
  v_reason constant text :=
    'REGULARISATION TECHNIQUE REVERSALS HISTORIQUES PRE-CORRECTIF';
  v_notes constant text :=
    'Sandbox fixture TEST REVERSAL DETTE. Compense uniquement les trois postings '
    || 'historiques erronés des reversals 20 + 10 + 70; settlement, reversals, '
    || 'obligation et enveloppes restent inchangés.';
begin
  select o.household_id, o.created_by, o.id
    into v_household_id, v_actor_id, v_obligation_id
  from public.obligations o
  where o.description = 'TEST REVERSAL DETTE'
  order by o.created_at asc
  limit 1
  for update;

  if not found then
    raise exception 'Historical fixture TEST REVERSAL DETTE not found';
  end if;

  if (select count(*) from public.obligations where description = 'TEST REVERSAL DETTE') <> 1 then
    raise exception 'Historical fixture TEST REVERSAL DETTE is not unique';
  end if;

  select s.id, s.financial_transaction_id
    into v_settlement_id, v_original_tx_id
  from public.obligation_settlements s
  where s.obligation_id = v_obligation_id
  for update;

  if not found or (select count(*) from public.obligation_settlements where obligation_id = v_obligation_id) <> 1 then
    raise exception 'Expected exactly one settlement for the historical fixture';
  end if;

  select coalesce(sum(r.amount), 0)
    into v_reversal_total
  from public.obligation_settlement_reversals r
  where r.source_settlement_id = v_settlement_id;

  if v_reversal_total <> 100.00 then
    raise exception 'Expected historical reversal total of 100.00, found %', v_reversal_total;
  end if;

  select ft.source_account_id into v_testoj_id
  from public.financial_transactions ft
  where ft.id = v_original_tx_id;

  select l.account_id into v_debt_system_id
  from public.financial_transaction_lines l
  where l.transaction_id = v_original_tx_id
    and l.debit = 100.00;

  if v_testoj_id is null or v_debt_system_id is null then
    raise exception 'Expected TESTOJ and Système — Dettes postings are missing';
  end if;

  select coalesce(sum(l.debit), 0)
    into v_historical_bad_side_total
  from public.obligation_settlement_reversals r
  join public.financial_transaction_lines l
    on l.transaction_id = r.financial_transaction_id
  where r.source_settlement_id = v_settlement_id
    and l.account_id = v_debt_system_id;

  if v_historical_bad_side_total <> 100.00 then
    raise exception 'Expected 100.00 erroneous debit on Système — Dettes, found %', v_historical_bad_side_total;
  end if;

  select fe.id into v_existing_event
  from public.financial_events fe
  where fe.household_id = v_household_id
    and fe.idempotency_key = v_idempotency_key;

  if v_existing_event is not null then
    return;
  end if;

  insert into public.financial_events(
    household_id, event_type, description, occurred_at, notes,
    idempotency_key, created_by
  ) values (
    v_household_id, 'debt_settlement_reversal', v_reason, now(), v_notes,
    v_idempotency_key, v_actor_id
  ) returning id into v_event_id;

  insert into public.financial_transactions(
    household_id, event_id, type, occurred_at, reason, description, amount,
    currency_code, source_account_id, destination_account_id, notes,
    created_by, validated_at
  ) values (
    v_household_id, v_event_id, 'correction', now(), v_reason, v_reason, 100.00,
    'MAD', v_testoj_id, null, v_notes, v_actor_id, now()
  ) returning id into v_tx_id;

  insert into public.financial_transaction_lines(
    transaction_id, account_id, amount, debit, credit, occurred_at
  ) values
    (v_tx_id, v_testoj_id, 100.00, 100.00, 0, now()),
    (v_tx_id, v_debt_system_id, -100.00, 0, 100.00, now());

  insert into public.financial_audit_events(
    household_id, transaction_id, action, reason, actor_id
  ) values (
    v_household_id, v_tx_id, 'created', v_reason, v_actor_id
  );
end;
$regularization$;

commit;
