-- L1 final: cutover is an operator-only workflow, never a normal client API.
revoke execute on function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb)
  from public, anon, authenticated;
revoke execute on function public.get_cutover_opening_run(uuid,text,date)
  from public, anon, authenticated;
revoke execute on function public.reconcile_cutover_opening_run(uuid)
  from public, anon, authenticated;

comment on function public.execute_cutover_opening_import(uuid,uuid,text,date,jsonb)
  is 'Operator-only certified cutover primitive. Not callable through the authenticated Data API.';
comment on function public.get_cutover_opening_run(uuid,text,date)
  is 'Operator-only cutover inspection. Not callable through the authenticated Data API.';
comment on function public.reconcile_cutover_opening_run(uuid)
  is 'Operator-only cutover reconciliation. Not callable through the authenticated Data API.';
