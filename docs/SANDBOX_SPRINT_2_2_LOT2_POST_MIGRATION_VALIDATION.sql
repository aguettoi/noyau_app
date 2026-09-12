-- Sprint 2.2 / Lot 2. Read-only post-application validation.
-- This script deliberately contains SELECT statements only.
select procedures.proname as function_name,
       pg_get_function_identity_arguments(procedures.oid) as identity_arguments,
       pg_get_function_result(procedures.oid) as result_type,
       procedures.prosecdef as security_definer,
       coalesce(array_to_string(procedures.proconfig, ', '), '') as configuration
from pg_proc procedures
join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
where namespaces.nspname = 'public'
  and procedures.proname = 'create_financial_transaction_with_envelopes';

select privileges.grantee, privileges.privilege_type
from information_schema.routine_privileges privileges
where privileges.routine_schema = 'public'
  and privileges.routine_name = 'create_financial_transaction_with_envelopes'
order by privileges.grantee, privileges.privilege_type;

select financial.id as transaction_id,
       financial.type,
       financial.amount,
       count(movements.id) as envelope_movement_count,
       coalesce(sum(movements.amount), 0) as envelope_total
from public.financial_transactions financial
left join public.envelope_movements movements
  on movements.financial_transaction_id = financial.id
where financial.type in ('expense', 'income', 'transfer', 'adjustment')
group by financial.id, financial.type, financial.amount
having (financial.type = 'expense' and coalesce(sum(movements.amount), 0) <> financial.amount)
    or (financial.type = 'income' and coalesce(sum(movements.amount), 0) <> financial.amount)
    or (financial.type in ('transfer', 'adjustment') and count(movements.id) <> 0)
order by financial.id;

select movements.movement_group_id,
       count(distinct movements.household_id) as household_count,
       count(*) as line_count,
       min(movements.amount) as minimum_amount
from public.envelope_movements movements
group by movements.movement_group_id
having count(distinct movements.household_id) <> 1
    or min(movements.amount) <= 0
order by movements.movement_group_id;

select classes.relname as relation_name, classes.relrowsecurity as rls_enabled
from pg_class classes
join pg_namespace namespaces on namespaces.oid = classes.relnamespace
where namespaces.nspname = 'public'
  and classes.relname in ('financial_transactions', 'financial_transaction_lines', 'envelope_movements', 'accounts', 'envelopes')
order by classes.relname;
