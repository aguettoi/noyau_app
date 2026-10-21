-- Hostile canonical-transfer test: a private account must not be usable by a
-- same-household non-holder. All writes are rolled back.
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
    perform public.create_account_transfer_event(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c', now(),
      'L1 private-account hostile transfer', 1,
      '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',
      '29fcbdd4-eefd-434f-919b-d1a3235eb395', null,
      'f1111111-1111-4111-8111-111111111111'
    );
  exception when others then
    if sqlerrm like '%Account is not available%' then
      blocked := true;
    else
      raise;
    end if;
  end;
  if not blocked then
    raise exception 'L1 non-holder transferred from private account';
  end if;
end $$;
do $$
declare blocked boolean := false;
begin
  begin
    perform public.create_cash_income_event(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c', now(),
      'L1 private-account hostile income', 1,
      '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d', '[]', null,
      'f3333333-3333-4333-8333-333333333333'
    );
  exception when others then
    if sqlerrm like '%Account is not available%' then
      blocked := true;
    else
      raise;
    end if;
  end;
  if not blocked then
    raise exception 'L1 non-holder posted income to private account';
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
set local role authenticated;
select public.create_account_transfer_event(
  '239f714f-c590-42bd-9979-40bbd3e6bf9c', now(),
  'L1 holder private-account transfer', 1,
  '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',
  '29fcbdd4-eefd-434f-919b-d1a3235eb395', null,
  'f2222222-2222-4222-8222-222222222222'
);
select public.create_cash_income_event(
  '239f714f-c590-42bd-9979-40bbd3e6bf9c', now(),
  'L1 holder private-account income', 1,
  '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d', '[]', null,
  'f4444444-4444-4444-8444-444444444444'
);
rollback;
