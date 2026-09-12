with rpc_checks as (select p.proname, pg_get_function_identity_arguments(p.oid) as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('approve_budget_allocation_run','apply_budget_allocation_run'))
select count(*) = 2 as post_migration_ready, jsonb_agg(jsonb_build_object('rpc',proname,'signature',signature)) as rpcs from rpc_checks;
