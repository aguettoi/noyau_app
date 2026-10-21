-- Isolated Sandbox fixture: all changes rollback, including the third member.
begin;
insert into public.household_members(household_id,user_id,role)
values ('239f714f-c590-42bd-9979-40bbd3e6bf9c',
        'd31226ce-4c5c-4395-8cf5-fa3f09daac77','member');
insert into public.account_privacy_settings(
  account_id,household_id,visibility,changed_by
) values (
  '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',
  '239f714f-c590-42bd-9979-40bbd3e6bf9c',
  'private','2e06922c-dc19-4715-9f78-7152aaf3dfcc'
);
insert into public.envelope_account_initial_position_drafts(
  household_id,account_id,envelope_id,amount,provenance,
  provenance_reference,updated_by
) values (
  '239f714f-c590-42bd-9979-40bbd3e6bf9c',
  '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',
  'abab2a8c-8800-4cea-b5f0-24425567a0ba',
  123.45,'human_confirmation','L1 rollback proof',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc'
);
insert into public.envelope_account_initial_evidence(
  household_id,account_id,envelope_id,amount,evidence_kind,
  source_fingerprint,source_reference,created_by
) values (
  '239f714f-c590-42bd-9979-40bbd3e6bf9c',
  '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',
  'abab2a8c-8800-4cea-b5f0-24425567a0ba',
  456.78,'human_confirmation','l1-rollback','L1 rollback proof',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc'
);
insert into public.account_balance_observations(
  household_id,account_id,observed_at,actual_balance,reason,created_by,
  theoretical_balance_snapshot,difference_snapshot,snapshot_version
) values (
  '239f714f-c590-42bd-9979-40bbd3e6bf9c',
  '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',
  now(),100,'L1 rollback proof',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',715,-615,1
);
set local role authenticated;
select set_config('request.jwt.claim.sub',
  'd31226ce-4c5c-4395-8cf5-fa3f09daac77',true);
do $$ begin
  if exists (select 1 from public.account_reconciliation_resolutions
    where account_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d') then
    raise exception 'L1: private reconciliation resolution leaked';
  end if;
  if exists (select 1 from public.envelope_account_current_positions
    where account_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d') then
    raise exception 'L1: private position leaked';
  end if;
  if public.envelope_account_position_snapshot(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')->>'restricted' <> 'true' then
    raise exception 'L1: SECURITY DEFINER snapshot leaked private totals';
  end if;
  if public.envelope_account_initial_position_draft(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')::text like '%123.45%' then
    raise exception 'L1: SECURITY DEFINER draft bypassed account RLS';
  end if;
  if public.envelope_account_initial_position_preview(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')::text like '%456.78%' then
    raise exception 'L1: SECURITY DEFINER evidence bypassed account RLS';
  end if;
  if (public.monthly_close_snapshot(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c','2026-10-01'
    )->>'accounts_total')::int <> (
      select count(*) from public.accounts
      where household_id='239f714f-c590-42bd-9979-40bbd3e6bf9c'
    ) then
    raise exception 'L1: month-close account count bypassed account RLS';
  end if;
  if public.monthly_close_todo_items(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c','2026-10-01'
    )::text like '%1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d%' then
    raise exception 'L1: month-close todo leaked private reconciliation';
  end if;
  if exists (select 1 from public.search_household_global(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c','oo',100,0
    ) where source_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d') then
    raise exception 'L1: global search leaked private account';
  end if;
end $$;
select set_config('request.jwt.claim.sub',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
do $$ begin
  if public.envelope_account_position_snapshot(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')->>'restricted' = 'true' then
    raise exception 'L1: holder lost the canonical position snapshot';
  end if;
  if public.envelope_account_initial_position_draft(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')::text not like '%123.45%' then
    raise exception 'L1: holder lost the private draft';
  end if;
  if public.envelope_account_initial_position_preview(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')::text not like '%456.78%' then
    raise exception 'L1: holder lost the private evidence';
  end if;
  if not exists (select 1 from public.search_household_global(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c','oo',100,0
    ) where source_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d') then
    raise exception 'L1: global search hid holder account';
  end if;
end $$;
rollback;
