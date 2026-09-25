-- A Shopping item remains an intention.  This migration only records the
-- explicit, auditable link to an existing canonical cash-expense event.
-- It never creates accounting rows itself.
begin;

alter table public.shopping_item_history
  drop constraint if exists shopping_item_history_action_check,
  add constraint shopping_item_history_action_check
    check (action in (
      'created', 'updated', 'member_priority_set', 'member_priority_cleared',
      'cancelled', 'archived', 'purchased'
    ));

create unique index shopping_items_purchased_financial_event_unique_idx
  on public.shopping_items(purchased_financial_event_id)
  where purchased_financial_event_id is not null;

create or replace function public.purchase_shopping_item_with_expense(
  p_household_id uuid,
  p_item_id uuid,
  p_financial_event_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_item public.shopping_items%rowtype;
  v_event public.financial_events%rowtype;
  v_transaction public.financial_transactions%rowtype;
begin
  if v_actor_id is null or not public.is_household_member(p_household_id) then
    raise exception 'Accès non autorisé au foyer.';
  end if;

  select * into v_item
  from public.shopping_items
  where id = p_item_id and household_id = p_household_id
  for update;
  if not found then raise exception 'Article introuvable.'; end if;
  if v_item.status <> 'planned' then
    raise exception 'Seul un article prévu peut être marqué comme acheté.';
  end if;

  select * into v_event
  from public.financial_events
  where id = p_financial_event_id and household_id = p_household_id
  for key share;
  if not found or v_event.event_type <> 'cash_expense' then
    raise exception 'L''opération sélectionnée doit être une dépense canonique du foyer.';
  end if;

  select * into v_transaction
  from public.financial_transactions
  where event_id = p_financial_event_id
    and household_id = p_household_id
    and type = 'expense'
    and archived_at is null
  for key share;
  if not found then
    raise exception 'La dépense sélectionnée ne possède pas de transaction active.';
  end if;

  if exists (
    select 1 from public.shopping_items
    where purchased_financial_event_id = p_financial_event_id
  ) then
    raise exception 'Cette dépense est déjà rattachée à un autre achat.';
  end if;

  update public.shopping_items
  set status = 'purchased',
      purchased_financial_event_id = p_financial_event_id,
      updated_by = v_actor_id,
      updated_at = now()
  where id = p_item_id and household_id = p_household_id;

  insert into public.shopping_item_history(
    household_id, shopping_item_id, action, changes, actor_id
  ) values (
    p_household_id,
    p_item_id,
    'purchased',
    jsonb_build_object(
      'financial_event_id', p_financial_event_id,
      'financial_transaction_id', v_transaction.id,
      'actual_amount', v_transaction.amount,
      'occurred_at', v_transaction.occurred_at
    ),
    v_actor_id
  );

  return jsonb_build_object(
    'financial_event_id', p_financial_event_id,
    'financial_transaction_id', v_transaction.id,
    'actual_amount', v_transaction.amount,
    'occurred_at', v_transaction.occurred_at
  );
end;
$$;

revoke all on function public.purchase_shopping_item_with_expense(uuid, uuid, uuid)
  from public, anon;
grant execute on function public.purchase_shopping_item_with_expense(uuid, uuid, uuid)
  to authenticated;

commit;
