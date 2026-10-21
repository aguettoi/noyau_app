begin;
do $$
declare
  signature text;
begin
  foreach signature in array array[
    'public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb)',
    'public.get_cutover_opening_run(uuid,text,date)',
    'public.reconcile_cutover_opening_run(uuid)'
  ] loop
    if has_function_privilege('authenticated',signature,'execute')
      or has_function_privilege('anon',signature,'execute') then
      raise exception 'L1 final: cutover RPC still client executable: %',signature;
    end if;
  end loop;
end $$;
rollback;
