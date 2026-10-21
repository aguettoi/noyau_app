begin;

update public.accounts
set updated_at = updated_at
where id = '7a6c43fc-c364-4703-9f8c-f347be3f602b';

do $$
declare
  v_household uuid := '239f714f-c590-42bd-9979-40bbd3e6bf9c';
begin
  if not exists (
    select 1 from public.household_realtime_invalidations
    where household_id=v_household and topic='accounts'
  ) then
    raise exception 'Account mutation did not emit safe invalidation';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='household_realtime_invalidations'
      and column_name in ('account_id','amount','balance','member_id','source_id')
  ) then
    raise exception 'Invalidation table exposes private payload metadata';
  end if;
  if exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename <> 'household_realtime_invalidations'
  ) then
    raise exception 'Raw business table remains in Realtime publication';
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public'
      and tablename='household_realtime_invalidations'
  ) then
    raise exception 'Safe invalidation table is not published';
  end if;

end;
$$;

set local role authenticated;

do $$
declare
  v_household uuid := '239f714f-c590-42bd-9979-40bbd3e6bf9c';
  v_other_household uuid := '51cfd7c6-8edc-4c42-94db-1be78289fe81';
begin
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config(
    'request.jwt.claim.sub',
    '2e06922c-dc19-4715-9f78-7152aaf3dfcc', true
  );
  if not exists (
    select 1 from public.household_realtime_invalidations
    where household_id=v_household and topic='accounts'
  ) then
    raise exception 'Authorized member cannot read own invalidation';
  end if;
  -- This user belongs to both pilot and technical households; isolation is
  -- proven by switching to a transaction-local synthetic non-member below.
  perform set_config(
    'request.jwt.claim.sub',
    'd31226ce-4c5c-4395-8cf5-fa3f09daac77', true
  );
  if exists (
    select 1 from public.household_realtime_invalidations
    where household_id in (v_household, v_other_household)
  ) then
    raise exception 'Non-member can read household invalidations';
  end if;
end;
$$;

rollback;
