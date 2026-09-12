with required_objects(name, kind) as (values ('budget_allocation_runs','table'),('budget_allocation_run_lines','table'),('allocate_budget_event','function'))
select bool_and(case when kind = 'table' then exists(select 1 from information_schema.tables t where t.table_schema='public' and t.table_name=required_objects.name) else exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=required_objects.name) end) as pre_migration_ready,
jsonb_agg(jsonb_build_object('object',name,'kind',kind)) as checked_objects from required_objects;
