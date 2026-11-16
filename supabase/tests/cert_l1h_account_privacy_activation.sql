begin;

do $$
begin
  if not has_function_privilege(
      'authenticated','public.request_account_privacy_change(uuid,text)','execute'
    ) or not has_function_privilege(
      'authenticated','public.decide_account_privacy_change(uuid,text)','execute'
    ) or not has_function_privilege(
      'authenticated','public.cancel_account_privacy_change(uuid)','execute'
    ) then
    raise exception 'CERT-L1H authenticated workflow is not active';
  end if;
  if has_function_privilege(
      'anon','public.request_account_privacy_change(uuid,text)','execute'
    ) or has_function_privilege(
      'anon','public.decide_account_privacy_change(uuid,text)','execute'
    ) or has_function_privilege(
      'anon','public.cancel_account_privacy_change(uuid)','execute'
    ) or has_function_privilege(
      'service_role','public.request_account_privacy_change(uuid,text)','execute'
    ) then
    raise exception 'CERT-L1H workflow audience is too broad';
  end if;
  if has_table_privilege('authenticated','public.account_privacy_settings','insert')
     or has_table_privilege('authenticated','public.account_privacy_settings','update')
     or has_table_privilege('authenticated','public.account_privacy_requests','insert')
     or has_table_privilege('authenticated','public.account_privacy_consents','insert') then
    raise exception 'CERT-L1H direct writes are exposed';
  end if;
end $$;

-- A holder can request; a same-household non-holder and another household
-- cannot mutate the account. The transaction is rolled back.
select set_config('request.jwt.claim.role','authenticated',true);
select set_config(
  'request.jwt.claim.sub','2e06922c-dc19-4715-9f78-7152aaf3dfcc',true
);

do $$
declare
  v_household uuid := '51cfd7c6-8edc-4c42-94db-1be78289fe81';
  v_account uuid := '10000000-0000-4000-8000-000000001501';
  v_request uuid;
begin
  insert into public.accounts(
    id, household_id, name, kind, opening_balance, ownership_type
  ) values (v_account, v_household, 'CERT-L1H activation rollback',
            'bank', 0, 'individual');
  insert into public.account_holders(account_id,household_id,user_id)
  values (v_account,v_household,'2e06922c-dc19-4715-9f78-7152aaf3dfcc');
  v_request := public.request_account_privacy_change(v_account,'private');
  if not exists (
    select 1 from public.account_privacy_requests
    where id=v_request and status='applied'
  ) then
    raise exception 'single-holder privacy request was not applied';
  end if;
end $$;

select set_config(
  'request.jwt.claim.sub','8645c7b4-c9d8-4cf7-9090-6f404a418391',true
);
do $$
begin
  begin
    perform public.request_account_privacy_change(
      '10000000-0000-4000-8000-000000001501','visible'
    );
    raise exception 'same-household non-holder mutation unexpectedly succeeded';
  exception when others then
    if sqlerrm <> 'Account privacy change denied' then raise; end if;
  end;
end $$;

select set_config(
  'request.jwt.claim.sub','d31226ce-4c5c-4395-8cf5-fa3f09daac77',true
);
do $$
begin
  begin
    perform public.request_account_privacy_change(
      '10000000-0000-4000-8000-000000001501','visible'
    );
    raise exception 'cross-household mutation unexpectedly succeeded';
  exception when others then
    if sqlerrm <> 'Account privacy change denied' then raise; end if;
  end;
end $$;

-- A household owner must not bypass a member-owned private account.
select set_config(
  'request.jwt.claim.sub','8645c7b4-c9d8-4cf7-9090-6f404a418391',true
);
do $$
declare
  v_household uuid := '51cfd7c6-8edc-4c42-94db-1be78289fe81';
  v_account uuid := '10000000-0000-4000-8000-000000001502';
begin
  insert into public.accounts(
    id, household_id, name, kind, opening_balance, ownership_type
  ) values (v_account, v_household, 'CERT-L1H owner bypass rollback',
            'bank', 0, 'individual');
  insert into public.account_holders(account_id,household_id,user_id)
  values (v_account,v_household,'8645c7b4-c9d8-4cf7-9090-6f404a418391');
  perform public.request_account_privacy_change(v_account,'private');
end $$;

select set_config(
  'request.jwt.claim.sub','2e06922c-dc19-4715-9f78-7152aaf3dfcc',true
);
do $$
declare
  v_account uuid := '10000000-0000-4000-8000-000000001502';
begin
  if private.can_discover_account(
    v_account,
    '2e06922c-dc19-4715-9f78-7152aaf3dfcc'
  ) or private.can_read_account_balance(
    v_account,
    '2e06922c-dc19-4715-9f78-7152aaf3dfcc'
  ) then
    raise exception 'household owner bypassed member account privacy';
  end if;
  begin
    perform public.request_account_privacy_change(v_account,'visible');
    raise exception 'household owner changed member account privacy';
  exception when others then
    if sqlerrm <> 'Account privacy change denied' then raise; end if;
  end;
end $$;

rollback;
