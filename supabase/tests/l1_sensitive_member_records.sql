-- Owner-only by default; explicit grant and revocation. Technical Auth users.
-- The private JSON fixture exists only inside this transaction.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
with created as (
  insert into public.sensitive_member_records(
    household_id,owner_user_id,category,payload,created_by
  ) values (
    '239f714f-c590-42bd-9979-40bbd3e6bf9c',
    '2e06922c-dc19-4715-9f78-7152aaf3dfcc',
    'l1_security_test','{"private":true}'::jsonb,
    '2e06922c-dc19-4715-9f78-7152aaf3dfcc'
  ) returning id
) select set_config('l1.record_id',(select id::text from created),true);

select set_config('request.jwt.claim.sub',
  '8645c7b4-c9d8-4cf7-9090-6f404a418391',true);
do $$ begin
  if exists (select 1 from public.sensitive_member_records
    where id=current_setting('l1.record_id')::uuid) then
    raise exception 'L1: same-household member read private record';
  end if;
end $$;

select set_config('request.jwt.claim.sub',
  '0afc572b-cf8b-47e2-9ab9-45c416dc96e2',true);
do $$ begin
  if exists (select 1 from public.sensitive_member_records
    where id=current_setting('l1.record_id')::uuid) then
    raise exception 'L1: cross-household member read private record';
  end if;
end $$;

select set_config('request.jwt.claim.sub',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
select public.set_sensitive_member_record_share(
  current_setting('l1.record_id')::uuid,
  '8645c7b4-c9d8-4cf7-9090-6f404a418391',true);
select set_config('request.jwt.claim.sub',
  '8645c7b4-c9d8-4cf7-9090-6f404a418391',true);
do $$ begin
  if not exists (select 1 from public.sensitive_member_records
    where id=current_setting('l1.record_id')::uuid) then
    raise exception 'L1: explicit share not visible';
  end if;
end $$;

select set_config('request.jwt.claim.sub',
  '2e06922c-dc19-4715-9f78-7152aaf3dfcc',true);
select public.set_sensitive_member_record_share(
  current_setting('l1.record_id')::uuid,
  '8645c7b4-c9d8-4cf7-9090-6f404a418391',false);
select set_config('request.jwt.claim.sub',
  '8645c7b4-c9d8-4cf7-9090-6f404a418391',true);
do $$ begin
  if exists (select 1 from public.sensitive_member_records
    where id=current_setting('l1.record_id')::uuid) then
    raise exception 'L1: revoked share remains visible';
  end if;
end $$;
rollback;
