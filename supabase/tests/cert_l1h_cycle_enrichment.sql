begin;

do $$
begin
  if not (select relrowsecurity from pg_class
    where oid = 'public.member_cycle_private_entries'::regclass) then
    raise exception 'cycle private entries must enforce RLS';
  end if;
  if has_table_privilege('anon', 'public.member_cycle_private_entries', 'select') then
    raise exception 'anon must not read cycle private entries';
  end if;
  if not has_table_privilege(
    'authenticated', 'public.member_cycle_private_entries', 'select'
  ) then
    raise exception 'authenticated owner access grant is missing';
  end if;
  if not has_table_privilege(
    'authenticated', 'public.member_cycle_calendar_shares', 'update'
  ) then
    raise exception 'Cycle share upsert requires UPDATE';
  end if;
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'member_cycle_private_entries'
  ) then
    raise exception 'raw private cycle entries must not be in Realtime';
  end if;
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'member_cycle_private_entries'
      and policyname = 'member_cycle_private_entries_owner_read'
      and qual like '%auth.uid()%'
  ) then
    raise exception 'owner-only read policy is missing';
  end if;
end $$;

select 'PASS: owner-only enriched Cycle journal boundary' as certification;
rollback;
