-- Deny-by-default reconstruction probe; all temporary objects rollback.
begin;
do $$ begin
  if exists (
    select 1 from pg_default_acl d
    join pg_namespace n on n.oid=d.defaclnamespace
    where n.nspname='public' and d.defaclrole='postgres'::regrole
      and d.defaclobjtype in ('r','S','f')
      and (d.defaclacl::text like '%anon=%'
        or d.defaclacl::text like '%authenticated=%'
        or d.defaclacl::text like '%service_role=%')
  ) then raise exception 'L1: implicit public API grant remains'; end if;
  if has_table_privilege('anon','public.account_privacy_settings','SELECT')
    or has_table_privilege('service_role','public.account_privacy_settings','SELECT')
    or has_table_privilege('authenticated','public.account_privacy_settings','INSERT')
    or not has_table_privilege('authenticated','public.account_privacy_settings','SELECT')
    or has_table_privilege('anon','public.sensitive_member_records','SELECT')
    or has_table_privilege('authenticated','public.sensitive_member_records','DELETE')
    or not has_table_privilege('authenticated','public.sensitive_member_records','SELECT')
    or not has_table_privilege('authenticated','public.sensitive_member_records','INSERT')
    or not has_table_privilege('authenticated','public.sensitive_member_records','UPDATE') then
    raise exception 'L1: account/sensitive table grants are not least privilege';
  end if;
  if has_function_privilege('anon','public.list_account_privacy_summaries_v2(uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.list_account_privacy_summaries_v2(uuid)','EXECUTE')
    or has_function_privilege('authenticated','public.request_account_privacy_change(uuid,text)','EXECUTE')
    or has_function_privilege('service_role','public.request_account_privacy_change(uuid,text)','EXECUTE') then
    raise exception 'L1: RPC grants or privacy activation gate changed';
  end if;
end $$;
create table public.l1_acl_rebuild_probe(id int);
create function public.l1_acl_rebuild_probe() returns int
  language sql as $$ select 1 $$;
do $$ begin
  if has_table_privilege('anon','public.l1_acl_rebuild_probe','SELECT')
    or has_table_privilege('authenticated','public.l1_acl_rebuild_probe','SELECT')
    or has_table_privilege('service_role','public.l1_acl_rebuild_probe','SELECT')
    or has_function_privilege('anon','public.l1_acl_rebuild_probe()','EXECUTE')
    or has_function_privilege('authenticated','public.l1_acl_rebuild_probe()','EXECUTE')
    or has_function_privilege('service_role','public.l1_acl_rebuild_probe()','EXECUTE') then
    raise exception 'L1: clean new objects are automatically exposed';
  end if;
end $$;
rollback;
