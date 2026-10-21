-- Three-member technical fixture; no pilot data or durable writes.
begin;
insert into public.household_members(household_id,user_id,role)
values ('239f714f-c590-42bd-9979-40bbd3e6bf9c',
        'd31226ce-4c5c-4395-8cf5-fa3f09daac77','member');
update public.envelopes
  set recommended_account_id='1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d'
  where id='abab2a8c-8800-4cea-b5f0-24425567a0ba';
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
  if has_column_privilege('authenticated','public.envelopes',
      'recommended_account_id','SELECT')
    or has_column_privilege('authenticated','public.envelopes',
      'recommended_payment_method_id','SELECT')
    or has_column_privilege('authenticated','public.envelopes',
      'recommendation_definition','SELECT') then
    raise exception 'L1: raw envelope recommendation remains readable';
  end if;
  if has_table_privilege('authenticated',
      'public.envelope_recommendation_events','SELECT') then
    raise exception 'L1: raw envelope recommendation audit remains readable';
  end if;
  if has_function_privilege('authenticated',
      'public.set_envelope_recommendation(uuid,uuid,uuid)','EXECUTE') then
    raise exception 'L1: raw-returning recommendation mutator exposed';
  end if;
  if not exists (select 1 from public.envelopes
      where id='abab2a8c-8800-4cea-b5f0-24425567a0ba') then
    raise exception 'L1: shared envelope disappeared';
  end if;
  if exists (select 1 from public.list_household_envelopes_safe(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c') x
      where x->>'id'='abab2a8c-8800-4cea-b5f0-24425567a0ba'
        and x->>'recommended_account_id' is not null) then
    raise exception 'L1: safe envelope RPC leaked private account';
  end if;
  begin
    perform public.set_envelope_recommendation_safe(
      'abab2a8c-8800-4cea-b5f0-24425567a0ba',
      '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',null
    );
    raise exception 'L1: non-holder changed private recommendation';
  exception when others then
    if SQLERRM='L1: non-holder changed private recommendation' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claim.sub',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
select public.set_envelope_recommendation_safe(
  'abab2a8c-8800-4cea-b5f0-24425567a0ba',
  '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d',null
);
do $$ begin
  if not exists (select 1 from public.list_household_envelopes_safe(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c') x
      where x->>'id'='abab2a8c-8800-4cea-b5f0-24425567a0ba'
        and x->>'recommended_account_id'=
          '1bc06cfd-5e16-4d92-9e3b-ba1bca53a64d') then
    raise exception 'L1: holder lost recommended account';
  end if;
end $$;
select set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000001',true);
do $$ begin
  if exists (select 1 from public.list_household_envelopes_safe(
      '239f714f-c590-42bd-9979-40bbd3e6bf9c')) then
    raise exception 'L1: cross-household envelope projection exposed';
  end if;
end $$;
rollback;
