select procedures.proname, pg_get_function_identity_arguments(procedures.oid) as arguments,
       procedures.prosecdef as security_definer, procedures.proconfig
from pg_proc procedures join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
where namespaces.nspname = 'public' and procedures.proname = 'import_household_envelopes';

select privileges.grantee, privileges.privilege_type
from information_schema.routine_privileges privileges
where privileges.routine_schema = 'public' and privileges.routine_name = 'import_household_envelopes';
