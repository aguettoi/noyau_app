begin;

revoke execute on function public.set_monthly_envelope_account_target(
  uuid,
  date,
  uuid,
  uuid,
  numeric,
  uuid
) from public, anon, authenticated;

comment on function public.set_monthly_envelope_account_target(
  uuid,
  date,
  uuid,
  uuid,
  numeric,
  uuid
) is
  'Deprecated by R2.3. Use refresh_monthly_automatic_targets for canonical targets or set_monthly_envelope_account_target_override for an OWNER-audited override.';

commit;
