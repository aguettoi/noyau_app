select procedures.proname, pg_get_function_identity_arguments(procedures.oid) as arguments
from pg_proc procedures join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
where namespaces.nspname = 'public' and procedures.proname = 'import_household_envelopes';

select classes.relname, classes.relrowsecurity
from pg_class classes join pg_namespace namespaces on namespaces.oid = classes.relnamespace
where namespaces.nspname = 'public' and classes.relname in ('envelopes', 'import_operation_journal', 'import_sheet_runs');
