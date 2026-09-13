-- Read-only Sandbox receipt for the technical-household context classification.
-- Run after the migration and after the explicitly authorized classification of
-- the GL-E2E fixture. No financial or membership data is written by this file.

with classification_constraint as (
  select exists (
    select 1
    from pg_constraint
    where conrelid = 'public.households'::regclass
      and conname = 'households_classification_check'
      and pg_get_constraintdef(oid) like '%operational%'
      and pg_get_constraintdef(oid) like '%technical%'
  ) as present
), membership_authorization as (
  select pg_get_functiondef(p.oid) not ilike '%classification%' as unchanged
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'is_household_member'
    and p.prokind = 'f'
)
select
  (select present from classification_constraint) as classification_constraint_present,
  coalesce((select unchanged from membership_authorization), false)
    as membership_authorization_unchanged;
