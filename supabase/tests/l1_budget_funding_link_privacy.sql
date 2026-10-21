-- Rollback-only three-member technical fixture.
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
do $$ begin
  if exists(select 1 from public.budget_funding_links
      where source_account_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d') then
    raise exception 'L1: private account reference leaked via budget funding';
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
set local role authenticated;
do $$ begin
  if not exists(select 1 from public.budget_funding_links
      where source_account_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d') then
    raise exception 'L1: holder lost budget funding history';
  end if;
end $$;
rollback;
