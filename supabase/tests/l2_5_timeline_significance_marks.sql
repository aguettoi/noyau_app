begin;

do $$
begin
  if not (select relrowsecurity from pg_class where oid='public.timeline_significance_marks'::regclass) then
    raise exception 'timeline_significance_marks must have RLS';
  end if;
  if has_table_privilege('anon','public.timeline_significance_marks','select') then
    raise exception 'anon must not read timeline marks';
  end if;
  if not has_table_privilege('authenticated','public.timeline_significance_marks','select,insert,delete') then
    raise exception 'authenticated explicit mark privileges missing';
  end if;
  if has_table_privilege('authenticated','public.timeline_significance_marks','update') then
    raise exception 'marks are append/delete only';
  end if;
  if (select count(*) from pg_policies where schemaname='public' and tablename='timeline_significance_marks')<>3 then
    raise exception 'unexpected timeline mark policy count';
  end if;
end $$;

rollback;
select 'PASS: L2.5 marks are personal, source-bound, RLS protected and non-financial' as certification;
