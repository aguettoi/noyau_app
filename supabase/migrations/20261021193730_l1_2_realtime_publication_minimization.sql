-- Only the redacted invalidation table is transported through Realtime.
-- This also closes the unfilterable DELETE payload channel on raw tables.
alter publication supabase_realtime drop table
  public.accounts,
  public.budget_goals,
  public.envelope_account_initial_position_drafts,
  public.envelope_account_initial_position_unknowns,
  public.envelopes,
  public.expected_financial_occurrence_matches,
  public.expected_financial_occurrences,
  public.financial_events,
  public.financial_reminders,
  public.household_tasks,
  public.member_compensations,
  public.obligations,
  public.priority_plans,
  public.recurring_financial_intentions,
  public.shopping_items,
  public.wealth_assets;
