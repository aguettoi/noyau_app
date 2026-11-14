-- A1/A2 follow-up: cover every new foreign key used by responsibility and sweep rules.
create index if not exists economic_responsibility_member_fk_idx
  on public.economic_responsibility_assignments(household_id, member_user_id)
  where member_user_id is not null;

create index if not exists economic_responsibility_created_by_idx
  on public.economic_responsibility_assignments(created_by);

create index if not exists monthly_sweep_rule_source_fk_idx
  on public.monthly_envelope_sweep_rules(source_envelope_id, household_id);

create index if not exists monthly_sweep_rule_destination_fk_idx
  on public.monthly_envelope_sweep_rules(destination_envelope_id, household_id);

create index if not exists monthly_sweep_rule_created_by_idx
  on public.monthly_envelope_sweep_rules(created_by);
