-- Sandbox-only, audited historical correction.
-- Neutralises only the seven erroneous transfer_out movements from the system
-- envelope À répartir created by direct account-funded budget allocations.
-- It never updates/deletes immutable history, and it never changes accounts,
-- ordinary destination envelopes, financial_events, GL transactions, funding
-- lines or budget runs. Each compensating inflow points to its original row.
begin;

do $$
declare
  v_target_count integer;
  v_target_total numeric(14, 2);
  v_inserted_count integer;
  v_inserted_total numeric(14, 2);
  v_target_ids uuid[] := array[
    '043af9c8-c5b2-4a2c-acea-7f1b72703c51'::uuid,
    '9bbe011d-e839-4e9d-a1ad-8175455ae128'::uuid,
    'fa4fd62d-1348-4bf1-ac3b-017e09b59818'::uuid,
    '18d6d1f2-68e9-4cc7-bb59-62e699cc52d3'::uuid,
    '5020f3de-c051-4719-87fc-899b53a5c7cf'::uuid,
    '6cc42a2a-eec9-4cd3-807a-6804cee03e0b'::uuid,
    '76032113-1978-48ad-9e8f-0ee824a7b3f7'::uuid
  ];
begin
  with expected(original_id, event_id, expected_amount) as (
    values
      ('043af9c8-c5b2-4a2c-acea-7f1b72703c51'::uuid, '37f20ffc-5a3c-410c-abc6-89e2222e4f26'::uuid, 800.00::numeric),
      ('9bbe011d-e839-4e9d-a1ad-8175455ae128'::uuid, 'e848c6d0-1ed0-489e-bc44-63ddc02b08fe'::uuid, 7200.00::numeric),
      ('fa4fd62d-1348-4bf1-ac3b-017e09b59818'::uuid, 'e51330dc-5c61-4686-b3c3-4a2bb1e4b03d'::uuid, 2000.00::numeric),
      ('18d6d1f2-68e9-4cc7-bb59-62e699cc52d3'::uuid, '522312d7-3409-46a9-a1ef-a166ec6c3c43'::uuid, 7200.00::numeric),
      ('5020f3de-c051-4719-87fc-899b53a5c7cf'::uuid, 'faed7902-40aa-4422-8fda-38782768c4d3'::uuid, 800.00::numeric),
      ('6cc42a2a-eec9-4cd3-807a-6804cee03e0b'::uuid, '67cb5391-4718-4a95-b542-a4e2d78a6579'::uuid, 1200.00::numeric),
      ('76032113-1978-48ad-9e8f-0ee824a7b3f7'::uuid, 'b8b28a6a-4c49-436d-9f93-219af66d22a3'::uuid, 800.00::numeric)
  ), valid_targets as (
    select movements.*
    from expected
    join public.envelope_movements movements on movements.id = expected.original_id
    join public.envelopes envelopes on envelopes.id = movements.envelope_id
    join public.financial_events events on events.id = movements.event_id
    where movements.event_id = expected.event_id
      and movements.amount = expected.expected_amount
      and movements.movement_type = 'transfer_out'
      and movements.direction = 'outflow'
      and envelopes.system_code = 'to_allocate'
      and events.event_type = 'budget_allocation'
      and not exists (
        select 1 from public.envelope_movements reversal
        where reversal.reversal_of = movements.id
      )
      and exists (
        select 1 from public.household_members members
        where members.household_id = movements.household_id
          and members.user_id = movements.created_by
      )
  )
  select count(*), coalesce(sum(amount), 0)
  into v_target_count, v_target_total
  from valid_targets;

  if v_target_count <> 7 or v_target_total <> 20000 then
    raise exception 'Historical correction scope changed: expected 7 unreversed rows totalling 20000, found % rows totalling %',
      v_target_count, v_target_total;
  end if;

  insert into public.envelope_movements(
    household_id, envelope_id, financial_transaction_id, movement_group_id,
    movement_type, direction, amount, occurred_at, description, reversal_of,
    created_by, event_id
  )
  select
    movements.household_id,
    movements.envelope_id,
    null,
    gen_random_uuid(),
    'reversal',
    'inflow',
    movements.amount,
    now(),
    'Correction auditée : neutralisation allocation budgétaire directe erronée (' || movements.id::text || ')',
    movements.id,
    movements.created_by,
    null
  from public.envelope_movements movements
  where movements.id = any(v_target_ids);

  set constraints all immediate;

  select count(*), coalesce(sum(amount), 0)
  into v_inserted_count, v_inserted_total
  from public.envelope_movements
  where reversal_of = any(v_target_ids);
  if v_inserted_count <> 7 or v_inserted_total <> 20000 then
    raise exception 'Historical correction verification failed: % reversals totalling %',
      v_inserted_count, v_inserted_total;
  end if;
end;
$$;

commit;

with to_allocate as (
  select id, household_id
  from public.envelopes
  where system_code = 'to_allocate'
)
select
  coalesce(sum(movements.amount) filter (where movements.direction = 'inflow'), 0) as to_allocate_inflows,
  coalesce(sum(movements.amount) filter (where movements.direction = 'outflow'), 0) as to_allocate_outflows,
  coalesce(sum(movements.amount * case when movements.direction = 'inflow' then 1 else -1 end), 0) as to_allocate_balance,
  (select count(*) from public.envelope_movements where reversal_of is not null
    and description like 'Correction auditée : neutralisation allocation budgétaire directe erronée%') as corrective_movement_count
from public.envelope_movements movements
join to_allocate on to_allocate.id = movements.envelope_id
  and to_allocate.household_id = movements.household_id;
