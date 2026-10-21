-- Technical-only L1 proof. Every fixture and temporary grant is rolled back.
-- Uses the isolated Sandbox household created by the authenticated test matrix;
-- never run against the pilot household.
begin;

-- Simulate the not-yet-exposed balance-hidden state without a durable switch.
insert into public.account_privacy_settings(
  account_id,household_id,visibility,changed_by
) values (
  '7a6c43fc-c364-4703-9f8c-f347be3f602b',
  '239f714f-c590-42bd-9979-40bbd3e6bf9c',
  'balance_hidden','2e06922c-dc19-4715-9f78-7152aaf3dfcc'
);
set local role authenticated;
select set_config('request.jwt.claim.sub',
  '8645c7b4-c9d8-4cf7-9090-6f404a418391',true);
do $$ begin
  if exists (select 1 from public.accounts
    where id='7a6c43fc-c364-4703-9f8c-f347be3f602b') then
    raise exception 'L1: raw balance leaked';
  end if;
  if exists (select 1 from public.account_ledger_balances
    where account_id='7a6c43fc-c364-4703-9f8c-f347be3f602b') then
    raise exception 'L1: ledger balance leaked';
  end if;
  if not exists (select 1 from public.list_account_privacy_summaries_v2(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')
    where id='7a6c43fc-c364-4703-9f8c-f347be3f602b'
      and visibility='balance_hidden' and not can_read_balance) then
    raise exception 'L1: sanitized metadata unavailable';
  end if;
  if not exists (select 1 from public.list_account_privacy_summaries_v2(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')
    where id='7a6c43fc-c364-4703-9f8c-f347be3f602b'
      and opening_balance is null and not can_read_balance) then
    raise exception 'L1: Flutter projection exposes hidden amount';
  end if;
end $$;

reset role;
update public.account_privacy_settings set visibility='private'
  where account_id='7a6c43fc-c364-4703-9f8c-f347be3f602b';
set local role authenticated;
do $$ begin
  if exists (select 1 from public.accounts
    where id='7a6c43fc-c364-4703-9f8c-f347be3f602b')
    or exists (select 1 from public.account_holders
    where account_id='7a6c43fc-c364-4703-9f8c-f347be3f602b')
    or exists (select 1 from public.list_account_privacy_summaries_v2(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')
    where id='7a6c43fc-c364-4703-9f8c-f347be3f602b') then
    raise exception 'L1: private account discoverable';
  end if;
end $$;
select set_config('request.jwt.claim.sub',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
do $$ begin
  if not exists (select 1 from public.accounts
    where id='7a6c43fc-c364-4703-9f8c-f347be3f602b') then
    raise exception 'L1: holder cannot read own private account';
  end if;
end $$;

-- The production gate is deliberately closed until indirect channels are
-- certified; temporarily open it only inside this rollbacked transaction.
reset role;
grant execute on function public.request_account_privacy_change(uuid,text),
  public.decide_account_privacy_change(uuid,text) to authenticated;
set local role authenticated;
select public.request_account_privacy_change(
  '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d','private');
reset role;
do $$ begin
  if exists (select 1 from public.account_privacy_settings
    where account_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d') then
    raise exception 'L1: shared account restricted without unanimous consent';
  end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',
  '8645c7b4-c9d8-4cf7-9090-6f404a418391',true);
select public.decide_account_privacy_change(
  (select id from public.account_privacy_requests
    where account_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d'
      and status='pending'),'approve');
reset role;
do $$ begin
  if not exists (select 1 from public.account_privacy_settings
    where account_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d'
      and visibility='private') then
    raise exception 'L1: unanimous consent did not activate restriction';
  end if;
end $$;

rollback;

-- 1/2/N: a third active technical member sees only sanitized metadata.
begin;
insert into public.household_members(household_id,user_id,role)
  values ('239f714f-c590-42bd-9979-40bbd3e6bf9c',
          'd31226ce-4c5c-4395-8cf5-fa3f09daac77','member');
insert into public.account_privacy_settings(
  account_id,household_id,visibility,changed_by
) values (
  '7a6c43fc-c364-4703-9f8c-f347be3f602b',
  '239f714f-c590-42bd-9979-40bbd3e6bf9c',
  'balance_hidden','2e06922c-dc19-4715-9f78-7152aaf3dfcc'
);
set local role authenticated;
select set_config('request.jwt.claim.sub',
  'd31226ce-4c5c-4395-8cf5-fa3f09daac77',true);
do $$ begin
  if exists (select 1 from public.accounts
    where id='7a6c43fc-c364-4703-9f8c-f347be3f602b') then
    raise exception 'L1: third member read raw account';
  end if;
  if not exists (select 1 from public.list_account_privacy_summaries_v2(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')
    where id='7a6c43fc-c364-4703-9f8c-f347be3f602b'
      and opening_balance is null) then
    raise exception 'L1: third member lacks sanitized summary';
  end if;
end $$;
rollback;

-- A separate technical account has existing GL history. Before L1's
-- restrictive policy, another member could read all 39 of its lines.
begin;
insert into public.account_privacy_settings(
  account_id,household_id,visibility,changed_by
) values (
  'a0e1a7ed-5827-4da5-945b-bbd157bb0f00',
  '239f714f-c590-42bd-9979-40bbd3e6bf9c',
  'private','2e06922c-dc19-4715-9f78-7152aaf3dfcc'
);
select set_config('l1.tx_id',(
  select transaction_id::text from public.financial_transaction_lines
  where account_id='a0e1a7ed-5827-4da5-945b-bbd157bb0f00' limit 1
),true);
set local role authenticated;
select set_config('request.jwt.claim.sub',
  '8645c7b4-c9d8-4cf7-9090-6f404a418391',true);
do $$ begin
  if exists (select 1 from public.financial_transaction_lines
    where account_id='a0e1a7ed-5827-4da5-945b-bbd157bb0f00') then
    raise exception 'L1: private GL line leaked';
  end if;
  if exists (select 1 from public.financial_transactions
    where id=current_setting('l1.tx_id')::uuid) then
    raise exception 'L1: private GL transaction leaked';
  end if;
end $$;
rollback;
