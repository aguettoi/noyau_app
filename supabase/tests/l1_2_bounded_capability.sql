begin;

insert into public.shopping_items (
  id, household_id, label, estimated_amount, status, created_by, updated_by
) values (
  'b3030303-0303-4303-8303-030303030303',
  '239f714f-c590-42bd-9979-40bbd3e6bf9c',
  'L1.2 capability rollback', 1, 'planned',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc'
);

set local role authenticated;

do $$
declare
  v_household uuid := '239f714f-c590-42bd-9979-40bbd3e6bf9c';
  v_owner uuid := '2e06922c-dc19-4715-9f78-7152aaf3dfcc';
  v_member uuid := '8645c7b4-c9d8-4cf7-9090-6f404a418391';
  v_account uuid := '7a6c43fc-c364-4703-9f8c-f347be3f602b';
  v_item uuid := 'b3030303-0303-4303-8303-030303030303';
  v_intent uuid;
  v_replay uuid;
  v_decision text;
  v_failed boolean;
begin
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  v_intent := public.create_private_funding_capability_intent(
    v_account, 'shopping_item', v_item, 1, now() + interval '1 day',
    'b1010101-0101-4101-8101-010101010101'
  );
  v_replay := public.create_private_funding_capability_intent(
    v_account, 'shopping_item', v_item, 1, now() + interval '1 day',
    'b1010101-0101-4101-8101-010101010101'
  );
  if v_replay <> v_intent then
    raise exception 'Capability creation is not idempotent';
  end if;

  perform set_config('request.jwt.claim.sub', v_member::text, true);
  v_decision := public.evaluate_private_funding_capability(v_intent);
  if v_decision not in ('ALLOWED', 'NOT_ALLOWED', 'REQUIRES_OWNER_ACTION') then
    raise exception 'Unbounded capability response: %', v_decision;
  end if;

  v_failed := false;
  begin
    perform * from private.private_funding_capability_intents;
  exception when insufficient_privilege then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Authenticated member can read private intent amount';
  end if;

  v_failed := false;
  begin
    perform public.create_private_funding_capability_intent(
      v_account, 'shopping_item', v_item, 2, now() + interval '1 day',
      'b2020202-0202-4202-8202-020202020202'
    );
  exception when others then
    v_failed := true;
  end;
  if not v_failed then
    raise exception 'Non-holder created a private capability oracle';
  end if;

  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in ('is_balance_greater_than', 'available_amount', 'maximum_possible')
  ) then
    raise exception 'Generic balance oracle exists';
  end if;
end;
$$;

do $$
declare
  v_names text[] := array[
    'is_active_household_member', 'create_shopping_item',
    'update_shopping_item', 'execute_monthly_account_reallocation',
    'list_account_privacy_summaries', 'save_budget_allocation_run'
  ];
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname=any(v_names)
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) then
    raise exception 'Internal/obsolete function remains client executable';
  end if;
end;
$$;

rollback;
