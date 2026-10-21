-- Reconciliation observation is personal to an authorized account viewer.
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
set local role authenticated;
select set_config('request.jwt.claim.sub',
  'd31226ce-4c5c-4395-8cf5-fa3f09daac77',true);
do $$
declare blocked boolean := false;
begin
  begin
    perform public.record_account_balance_observation(
      '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',now(),1,
      'L1 hostile private observation'
    );
  exception when others then
    if sqlerrm like '%Account access denied%' then
      blocked := true;
    else
      raise;
    end if;
  end;
  if not blocked then
    raise exception 'L1 private observation accepted from non-holder';
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
set local role authenticated;
select public.record_account_balance_observation(
  '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',now(),1,
  'L1 authorized holder observation'
);
rollback;
