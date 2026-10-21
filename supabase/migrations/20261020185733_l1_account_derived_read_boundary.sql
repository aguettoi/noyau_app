-- Account-linked derived reads must not reconstruct a private balance or
-- reveal private account activity to another household member.
create policy "l1 private reconciliation resolution" on public.account_reconciliation_resolutions
  as restrictive for select to authenticated
  using (private.can_read_financial_line(account_id,(select auth.uid())));

create policy "l1 private initial evidence" on public.envelope_account_initial_evidence
  as restrictive for select to authenticated
  using (private.can_read_financial_line(account_id,(select auth.uid())));
create policy "l1 private initial drafts" on public.envelope_account_initial_position_drafts
  as restrictive for select to authenticated
  using (private.can_read_financial_line(account_id,(select auth.uid())));
create policy "l1 private position entries" on public.envelope_account_position_entries
  as restrictive for select to authenticated
  using (private.can_read_financial_line(account_id,(select auth.uid())));
create policy "l1 private physical transfers" on public.envelope_account_physical_transfers
  as restrictive for select to authenticated
  using (private.can_read_financial_line(from_account_id,(select auth.uid()))
    and private.can_read_financial_line(to_account_id,(select auth.uid())));
create policy "l1 private reallocation justifications" on public.envelope_account_reallocation_justifications
  as restrictive for select to authenticated
  using (private.can_read_financial_line(from_account_id,(select auth.uid()))
    and private.can_read_financial_line(to_account_id,(select auth.uid())));

create policy "l1 private recommendation events" on public.envelope_recommendation_events
  as restrictive for select to authenticated
  using (private.can_read_financial_line(account_id,(select auth.uid()))
    and private.can_read_financial_line(previous_account_id,(select auth.uid())));
create policy "l1 private monthly targets" on public.monthly_envelope_account_targets
  as restrictive for select to authenticated
  using (private.can_read_financial_line(account_id,(select auth.uid())));
create policy "l1 private monthly target events" on public.monthly_envelope_account_target_events
  as restrictive for select to authenticated
  using (private.can_read_financial_line(account_id,(select auth.uid())));

create policy "l1 private legacy transactions" on public.transactions
  as restrictive for select to authenticated
  using (private.can_read_financial_line(account_id,(select auth.uid())));
create policy "l1 private budget funding links" on public.budget_funding_links
  as restrictive for select to authenticated
  using (private.can_read_financial_line(source_account_id,(select auth.uid())));
create policy "l1 private budget funding lines" on public.budget_allocation_run_funding_lines
  as restrictive for select to authenticated
  using (private.can_read_financial_line(source_account_id,(select auth.uid())));

create policy "l1 private recurring intentions" on public.recurring_financial_intentions
  as restrictive for select to authenticated
  using (private.can_read_financial_line(source_account_id,(select auth.uid()))
    and private.can_read_financial_line(destination_account_id,(select auth.uid())));
create policy "l1 private expected occurrences" on public.expected_financial_occurrences
  as restrictive for select to authenticated
  using (private.can_read_financial_line(source_account_id,(select auth.uid()))
    and private.can_read_financial_line(destination_account_id,(select auth.uid())));
create policy "l1 private compensations" on public.member_compensations
  as restrictive for select to authenticated
  using (private.can_read_financial_line(actual_account_id,(select auth.uid()))
    and private.can_read_financial_line(recommended_account_id,(select auth.uid())));
