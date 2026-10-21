-- Opt in early to Supabase's deny-by-default Data API contract for objects
-- created by our postgres-owned migrations. Existing object ACLs are
-- unchanged by ALTER DEFAULT PRIVILEGES; no legacy grant is restored.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated, service_role;
-- PostgreSQL itself otherwise grants EXECUTE on new functions to PUBLIC.
alter default privileges for role postgres
  revoke execute on functions from public;

-- Server-owned policy state. Client reads are holder-scoped by RLS.
-- Every write is reserved to audited SECURITY DEFINER RPCs.
revoke all on public.account_privacy_settings,
  public.account_privacy_requests, public.account_privacy_consents,
  public.account_privacy_audit,
  public.sensitive_member_records, public.sensitive_member_record_shares,
  public.sensitive_member_record_audit
  from public, anon, authenticated, service_role;
grant select on public.account_privacy_settings,
  public.account_privacy_requests, public.account_privacy_consents,
  public.account_privacy_audit to authenticated;
grant select, insert, update on public.sensitive_member_records
  to authenticated;
grant select on public.sensitive_member_record_shares,
  public.sensitive_member_record_audit to authenticated;

-- Identity sequences are used only by owner-executed audit triggers/RPCs.
revoke all on sequence public.account_privacy_audit_id_seq,
  public.sensitive_member_record_audit_id_seq
  from public, anon, authenticated, service_role;

-- Existing read contracts must work after a clean reconstruction whose
-- platform no longer supplies implicit EXECUTE grants.
revoke all on function public.list_account_privacy_summaries(uuid),
  public.list_account_privacy_summaries_v2(uuid),
  public.set_sensitive_member_record_share(uuid,uuid,boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.list_account_privacy_summaries(uuid),
  public.list_account_privacy_summaries_v2(uuid),
  public.set_sensitive_member_record_share(uuid,uuid,boolean)
  to authenticated;

-- Activation remains closed until all indirect disclosures are certified.
revoke all on function public.request_account_privacy_change(uuid,text),
  public.decide_account_privacy_change(uuid,text),
  public.cancel_account_privacy_change(uuid)
  from public, anon, authenticated, service_role;

-- Private helpers are callable by policies, not Data API RPC endpoints.
revoke all on function private.account_is_holder(uuid,uuid),
  private.account_visibility(uuid),
  private.can_discover_account(uuid,uuid),
  private.can_read_account_balance(uuid,uuid),
  private.can_read_financial_line(uuid,uuid),
  private.can_read_financial_transaction(uuid,uuid),
  private.can_read_financial_event(uuid,uuid),
  private.has_unreadable_household_account(uuid,uuid),
  private.audit_sensitive_member_record()
  from public, anon, authenticated, service_role;
grant execute on function private.account_is_holder(uuid,uuid),
  private.can_discover_account(uuid,uuid),
  private.can_read_account_balance(uuid,uuid),
  private.can_read_financial_line(uuid,uuid),
  private.can_read_financial_transaction(uuid,uuid),
  private.can_read_financial_event(uuid,uuid),
  private.has_unreadable_household_account(uuid,uuid)
  to authenticated;

-- Historical canonical RPC: explicit authenticated grant for clean replay.
grant execute on function public.envelope_account_position_snapshot(uuid)
  to authenticated;
