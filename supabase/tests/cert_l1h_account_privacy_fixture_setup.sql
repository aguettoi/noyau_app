-- CERT-L1H synthetic, reversible Sandbox fixtures.
-- Values are deliberately zero: these rows certify privacy, not finance.
begin;

do $$
declare
  v_household constant uuid := '51cfd7c6-8edc-4c42-94db-1be78289fe81';
  v_a constant uuid := '2e06922c-dc19-4715-9f78-7152aaf3dfcc';
  v_b constant uuid := '8645c7b4-c9d8-4cf7-9090-6f404a418391';
begin
  if not exists (
    select 1 from public.household_members
    where household_id = v_household and user_id = v_a and inactive_at is null
  ) or not exists (
    select 1 from public.household_members
    where household_id = v_household and user_id = v_b and inactive_at is null
  ) then
    raise exception 'CERT-L1H fixture requires the established A/B household';
  end if;

  if exists (
    select 1 from public.accounts
    where id in (
      'c3111000-0000-4000-8000-000000000001',
      'c3111000-0000-4000-8000-000000000002',
      'c3111000-0000-4000-8000-000000000003',
      'c3111000-0000-4000-8000-000000000004'
    ) and (household_id <> v_household or name not like 'CERT-L1H %')
  ) then
    raise exception 'CERT-L1H deterministic fixture id collision';
  end if;
end $$;

insert into public.accounts(
  id, household_id, name, kind, currency_code, opening_balance,
  ownership_type, is_system
) values
  ('c3111000-0000-4000-8000-000000000001', '51cfd7c6-8edc-4c42-94db-1be78289fe81', 'CERT-L1H Visible partagé', 'bank', 'MAD', 0, 'shared', false),
  ('c3111000-0000-4000-8000-000000000002', '51cfd7c6-8edc-4c42-94db-1be78289fe81', 'CERT-L1H Solde masqué A', 'bank', 'MAD', 0, 'individual', false),
  ('c3111000-0000-4000-8000-000000000003', '51cfd7c6-8edc-4c42-94db-1be78289fe81', 'CERT-L1H Privé A', 'bank', 'MAD', 0, 'individual', false),
  ('c3111000-0000-4000-8000-000000000004', '51cfd7c6-8edc-4c42-94db-1be78289fe81', 'CERT-L1H Consentement partagé', 'bank', 'MAD', 0, 'shared', false)
on conflict (id) do nothing;

insert into public.account_holders(account_id, household_id, user_id) values
  ('c3111000-0000-4000-8000-000000000001', '51cfd7c6-8edc-4c42-94db-1be78289fe81', '2e06922c-dc19-4715-9f78-7152aaf3dfcc'),
  ('c3111000-0000-4000-8000-000000000001', '51cfd7c6-8edc-4c42-94db-1be78289fe81', '8645c7b4-c9d8-4cf7-9090-6f404a418391'),
  ('c3111000-0000-4000-8000-000000000002', '51cfd7c6-8edc-4c42-94db-1be78289fe81', '2e06922c-dc19-4715-9f78-7152aaf3dfcc'),
  ('c3111000-0000-4000-8000-000000000003', '51cfd7c6-8edc-4c42-94db-1be78289fe81', '2e06922c-dc19-4715-9f78-7152aaf3dfcc'),
  ('c3111000-0000-4000-8000-000000000004', '51cfd7c6-8edc-4c42-94db-1be78289fe81', '2e06922c-dc19-4715-9f78-7152aaf3dfcc'),
  ('c3111000-0000-4000-8000-000000000004', '51cfd7c6-8edc-4c42-94db-1be78289fe81', '8645c7b4-c9d8-4cf7-9090-6f404a418391')
on conflict (account_id, user_id) do nothing;

insert into public.account_privacy_settings(
  account_id, household_id, visibility, changed_by
) values
  ('c3111000-0000-4000-8000-000000000001', '51cfd7c6-8edc-4c42-94db-1be78289fe81', 'visible', '2e06922c-dc19-4715-9f78-7152aaf3dfcc'),
  ('c3111000-0000-4000-8000-000000000002', '51cfd7c6-8edc-4c42-94db-1be78289fe81', 'balance_hidden', '2e06922c-dc19-4715-9f78-7152aaf3dfcc'),
  ('c3111000-0000-4000-8000-000000000003', '51cfd7c6-8edc-4c42-94db-1be78289fe81', 'private', '2e06922c-dc19-4715-9f78-7152aaf3dfcc'),
  ('c3111000-0000-4000-8000-000000000004', '51cfd7c6-8edc-4c42-94db-1be78289fe81', 'visible', '2e06922c-dc19-4715-9f78-7152aaf3dfcc')
on conflict (account_id) do update set
  visibility = excluded.visibility,
  changed_by = excluded.changed_by,
  changed_at = now();

commit;
