-- R2.14: publish the shared non-financial opening draft through the existing
-- centralized household Realtime coordinator.
begin;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public'
      and tablename='envelope_account_initial_position_drafts'
  ) then
    alter publication supabase_realtime
      add table public.envelope_account_initial_position_drafts;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public'
      and tablename='envelope_account_initial_position_unknowns'
  ) then
    alter publication supabase_realtime
      add table public.envelope_account_initial_position_unknowns;
  end if;
end $$;

commit;
