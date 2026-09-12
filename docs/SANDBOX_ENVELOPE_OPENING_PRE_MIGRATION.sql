-- Read-only pre-flight for 202608080002_envelope_opening_and_lifecycle.sql.
-- Run as one script in the Sandbox SQL editor; it does not modify data.

with envelope_counts as (
  select
    count(*) filter (where not is_system) as ordinary_envelopes,
    count(*) filter (where is_system) as system_envelopes,
    count(*) as total_envelopes
  from public.envelopes
), movement_counts as (
  select envelope_id, count(*) as movement_count,
    count(*) filter (where movement_type = 'opening') as opening_count
  from public.envelope_movements
  group by envelope_id
), to_allocate as (
  select balances.household_id, balances.envelope_id, balances.envelope_name,
    balances.balance
  from public.envelope_ledger_balances balances
  where balances.system_code = 'to_allocate'
)
select
  counts.total_envelopes,
  counts.ordinary_envelopes,
  counts.system_envelopes,
  count(envelopes.id) filter (where coalesce(movements.movement_count, 0) = 0)
    as envelopes_without_movements,
  count(envelopes.id) filter (where coalesce(movements.opening_count, 0) > 0)
    as envelopes_with_opening,
  count(to_allocate.envelope_id) as to_allocate_envelopes,
  coalesce(jsonb_agg(jsonb_build_object(
    'household_id', to_allocate.household_id,
    'balance', to_allocate.balance
  )) filter (where to_allocate.envelope_id is not null), '[]'::jsonb) as to_allocate_balances
from envelope_counts counts
left join public.envelopes envelopes on true
left join movement_counts movements on movements.envelope_id = envelopes.id
left join to_allocate on to_allocate.envelope_id = envelopes.id
group by counts.total_envelopes, counts.ordinary_envelopes, counts.system_envelopes;

select
  envelopes.id,
  envelopes.household_id,
  envelopes.name,
  envelopes.is_system,
  envelopes.system_code,
  coalesce(movements.movement_count, 0) as movement_count,
  coalesce(movements.opening_count, 0) as opening_count,
  balances.balance
from public.envelopes envelopes
left join (
  select envelope_id, count(*) as movement_count,
    count(*) filter (where movement_type = 'opening') as opening_count
  from public.envelope_movements
  group by envelope_id
) movements on movements.envelope_id = envelopes.id
left join public.envelope_ledger_balances balances on balances.envelope_id = envelopes.id
order by envelopes.is_system desc, envelopes.name;

select
  to_regprocedure('public.import_household_envelopes(uuid,jsonb,uuid)') is not null
    as legacy_import_rpc_exists,
  to_regprocedure('public.undo_last_envelope_import(uuid)') is not null
    as lifecycle_undo_rpc_exists,
  to_regclass('public.envelope_import_sessions') is not null
    as import_session_table_exists;
