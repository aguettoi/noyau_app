-- A1/A2 follow-up: cover composite household/actor foreign keys.
create index if not exists economic_responsibility_household_actor_fk_idx
  on public.economic_responsibility_assignments(household_id, created_by);

create index if not exists monthly_sweep_rule_household_actor_fk_idx
  on public.monthly_envelope_sweep_rules(household_id, created_by);
