-- Run only after the human CERT-L1H account-privacy matrix is complete.
-- Deletes exclusively the deterministic synthetic fixtures created by setup.
begin;

delete from public.accounts
where id in (
  'c3111000-0000-4000-8000-000000000001',
  'c3111000-0000-4000-8000-000000000002',
  'c3111000-0000-4000-8000-000000000003',
  'c3111000-0000-4000-8000-000000000004'
) and name like 'CERT-L1H %';

commit;
