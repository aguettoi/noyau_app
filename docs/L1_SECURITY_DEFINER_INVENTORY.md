# L1 — inventaire des 121 fonctions SECURITY DEFINER exposées

> Passage 5 : les chiffres désignent trois populations différentes. **121** est
> la photographie initiale des fonctions `public SECURITY DEFINER` exécutables
> par `authenticated` au 19 octobre. **135** est le nombre actuel de *toutes*
> les fonctions `public` exécutables par ce rôle, invoker incluses. **116** est
> le nombre actuel de fonctions `public SECURITY DEFINER` exécutables par ce
> rôle (advisor Supabase et `pg_proc`). Aucun des 121 éléments historiques ne
> devient automatiquement « A » parce qu'il a quitté l'exposition ; les
> conversions et révocations doivent être rapprochées de leurs signatures.
> La qualification A–E individuelle/familiale et la matrice hostile restent
> incomplètes. Ne pas transformer cet inventaire syntaxique en certification.

Après la migration `20261021071622`, la nouvelle RPC sûre de modification des recommandations porte la population live à **136** fonctions `public` exécutables par `authenticated`, dont **117 SECURITY DEFINER** ; `anon` en exécute toujours **0**. Les 121 lignes historiques ci-dessous restent une photographie et non la liste actuelle qualifiée.

Extraction **lecture seule** du Sandbox, 19 octobre 2026. Cette liste est exhaustive pour les fonctions `public` SECURITY DEFINER avec privilège EXECUTE effectif de `authenticated` à la date du contrôle. Les indicateurs sont syntaxiques, **pas** une certification de sécurité : un appel indirect à un helper peut valider l'identité même si la fonction ne contient pas `auth.uid()` ; inversement sa simple présence ne prouve pas le respect d'une audience privée.

Bilan : 121/121 fixent `search_path`; 101/121 contiennent directement `auth.uid()`; 119/121 mentionnent household; 68/121 mentionnent account/balance/financial; 23/121 retournent JSON ou des lignes. La classification finale A–E exige encore l'analyse de chaque corps, des appels indirects et des tests authentifiés. Aucune révocation massive n'a été faite sur la base de ce seul inventaire.

| # | Signature | Retour | Auth direct | Household textuel | Finance textuelle | search_path |
|---:|---|---|:---:|:---:|:---:|---|
| 1 | `accept_household_invitation(uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 2 | `act_on_financial_reminder(uuid,text,text,timestamp with time zone,uuid)` | `void` | oui | oui | oui | `search_path=public` |
| 3 | `activate_priority_plan(uuid,uuid)` | `void` | oui | oui | non | `search_path=public` |
| 4 | `add_account_reconciliation_explanation(uuid,text,text,text)` | `uuid` | oui | oui | oui | `search_path=public` |
| 5 | `add_priority_plan_item(uuid,uuid,uuid,uuid)` | `uuid` | oui | oui | non | `search_path=public` |
| 6 | `allocate_budget_event(uuid,timestamp with time zone,text,numeric,uuid,uuid,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 7 | `append_historical_analytic_decision(uuid,uuid,text,text,numeric,text)` | `uuid` | oui | oui | non | `search_path=public, pg_temp` |
| 8 | `apply_budget_allocation_run_with_funding(uuid,uuid,jsonb,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 9 | `apply_budget_allocation_run(uuid,uuid,uuid,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 10 | `approve_budget_allocation_run(uuid,uuid)` | `void` | oui | oui | non | `search_path=public` |
| 11 | `archive_shopping_item(uuid,uuid,text)` | `void` | oui | oui | non | `search_path=public` |
| 12 | `archive_workbook_import(uuid,text,text,jsonb)` | `uuid` | oui | oui | non | `search_path=public` |
| 13 | `assert_shopping_item_links(uuid,uuid,uuid)` | `void` | non | oui | non | `search_path=public` |
| 14 | `cancel_shopping_item(uuid,uuid,text)` | `void` | oui | oui | non | `search_path=public` |
| 15 | `change_household_member_role(uuid,uuid,text)` | `void` | oui | oui | non | `search_path=public, auth` |
| 16 | `close_monthly_period(uuid,date,boolean,text,uuid)` | `uuid` | oui | oui | non | `search_path=public, auth` |
| 17 | `commit_historical_analytic_import(uuid,uuid,text,text,jsonb)` | `jsonb` | oui | oui | non | `search_path=public, pg_temp` |
| 18 | `complete_household_task(uuid,text,text,uuid)` | `household_tasks` | oui | oui | non | `search_path=public` |
| 19 | `create_account_opening_event(uuid,timestamp with time zone,text,numeric,uuid,text,uuid)` | `uuid` | non | oui | oui | `search_path=public` |
| 20 | `create_account_transfer_event(uuid,timestamp with time zone,text,numeric,uuid,uuid,text,uuid)` | `uuid` | non | oui | oui | `search_path=public` |
| 21 | `create_account_with_holders(uuid,text,text,numeric,timestamp with time zone,text,uuid[])` | `uuid` | oui | oui | oui | `search_path=public` |
| 22 | `create_budget_goal(uuid,text,text,numeric,date,integer,uuid,numeric,text,text)` | `uuid` | oui | oui | non | `search_path=public` |
| 23 | `create_cash_expense_event(uuid,timestamp with time zone,text,numeric,uuid,jsonb,text,uuid)` | `uuid` | non | oui | oui | `search_path=public` |
| 24 | `create_cash_expense_with_payment_context(uuid,timestamp with time zone,text,numeric,uuid,uuid,jsonb,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 25 | `create_cash_income_event(uuid,timestamp with time zone,text,numeric,uuid,jsonb,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 26 | `create_compensation_account_transfer(uuid,uuid,uuid,numeric,timestamp with time zone,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 27 | `create_debt_expense_event(uuid,timestamp with time zone,text,numeric,jsonb,text,date,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 28 | `create_envelope_opening_event(uuid,timestamp with time zone,text,jsonb,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 29 | `create_envelope_transfer_event(uuid,timestamp with time zone,text,numeric,uuid,uuid,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 30 | `create_household_envelope(uuid,text,numeric,text)` | `jsonb` | non | oui | oui | `search_path=public` |
| 31 | `create_household_invitation(uuid,text)` | `TABLE(invitation_id uuid, household_id uuid, household_name text, invited_email text, proposed_role text, status text, expires_at timestamp with time zone)` | oui | oui | non | `search_path=public, auth` |
| 32 | `create_household(text)` | `uuid` | oui | oui | non | `search_path=public, auth` |
| 33 | `create_income_receivable_event(uuid,timestamp with time zone,text,numeric,text,date,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 34 | `create_member_compensation(uuid,uuid,uuid,uuid,numeric,text,uuid,uuid,uuid,uuid,uuid,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 35 | `create_obligation_opening_event(uuid,timestamp with time zone,text,numeric,text,date,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 36 | `create_payment_method(uuid,uuid,uuid,text,text)` | `payment_methods` | oui | oui | oui | `search_path=public, auth` |
| 37 | `create_priority_plan(uuid,text,numeric,text)` | `uuid` | oui | oui | non | `search_path=public` |
| 38 | `create_recovery_receivable_event(uuid,uuid,uuid,timestamp with time zone,text,numeric,text,date,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 39 | `create_shopping_item_with_member_priorities(uuid,text,numeric,text,date,uuid,uuid,integer,jsonb)` | `uuid` | non | oui | non | `search_path=public` |
| 40 | `create_shopping_item(uuid,text,numeric,text,date,uuid,uuid,integer)` | `uuid` | oui | oui | non | `search_path=public` |
| 41 | `delete_household_envelope(uuid,uuid)` | `void` | oui | oui | non | `search_path=public` |
| 42 | `distribute_to_allocate_envelope_event(uuid,timestamp with time zone,text,jsonb,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 43 | `envelope_account_initial_position_draft(uuid)` | `jsonb` | oui | oui | oui | `search_path=public, auth` |
| 44 | `envelope_account_initial_position_preview(uuid)` | `jsonb` | non | oui | oui | `search_path=public` |
| 45 | `envelope_account_initial_position_unknowns(uuid)` | `jsonb` | oui | oui | oui | `search_path=public, auth` |
| 46 | `envelope_account_opening_history(uuid)` | `jsonb` | oui | oui | oui | `search_path=public, auth` |
| 47 | `envelope_account_position_snapshot(uuid)` | `jsonb` | non | oui | oui | `search_path=public` |
| 48 | `execute_cutover_opening_import(uuid,uuid,text,date,jsonb)` | `jsonb` | oui | oui | oui | `search_path=public` |
| 49 | `execute_monthly_account_reallocation_v2(uuid,date,text,date,jsonb,jsonb,uuid)` | `jsonb` | oui | oui | oui | `search_path=public, auth` |
| 50 | `execute_monthly_account_reallocation(uuid,date,text,jsonb,uuid)` | `jsonb` | oui | oui | oui | `search_path=public` |
| 51 | `execute_monthly_savings_sweep(uuid,date)` | `jsonb` | oui | oui | oui | `search_path=public, auth` |
| 52 | `get_cutover_opening_run(uuid,text,date)` | `jsonb` | non | oui | non | `search_path=public` |
| 53 | `handle_new_user()` | `trigger` | non | non | non | `search_path=public` |
| 54 | `ignore_expected_financial_occurrence(uuid,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 55 | `is_active_household_member(uuid,uuid)` | `boolean` | non | oui | non | `search_path=public` |
| 56 | `is_household_member(uuid)` | `boolean` | oui | oui | non | `search_path=public` |
| 57 | `leave_household(uuid)` | `void` | oui | oui | non | `search_path=public, auth` |
| 58 | `link_account_reconciliation_financial_event(uuid,uuid,text,text)` | `uuid` | oui | oui | oui | `search_path=public` |
| 59 | `list_household_invitations(uuid)` | `TABLE(invitation_id uuid, invited_email text, proposed_role text, status text, expires_at timestamp with time zone)` | oui | oui | non | `search_path=public, auth` |
| 60 | `list_my_pending_household_invitations()` | `TABLE(invitation_id uuid, household_id uuid, household_name text, invited_by_name text, proposed_role text, expires_at timestamp with time zone)` | oui | oui | non | `search_path=public, auth` |
| 61 | `materialize_historical_analytic_import(uuid,text,text,text,date,date,integer,text,jsonb,jsonb)` | `jsonb` | oui | oui | non | `search_path=public, pg_temp` |
| 62 | `materialize_recurring_financial_occurrences(uuid,date)` | `integer` | oui | oui | oui | `search_path=public, auth` |
| 63 | `monthly_close_automatic_target_preview(uuid,date)` | `jsonb` | oui | oui | oui | `search_path=public, auth` |
| 64 | `monthly_close_snapshot(uuid,date)` | `jsonb` | oui | oui | oui | `search_path=public, auth` |
| 65 | `monthly_close_todo_items(uuid,date)` | `jsonb` | non | oui | oui | `search_path=public` |
| 66 | `monthly_savings_sweep_preview(uuid,date)` | `jsonb` | oui | oui | oui | `search_path=public, auth` |
| 67 | `prepare_budget_period_v2(uuid,date,text,uuid)` | `uuid` | oui | oui | non | `search_path=public` |
| 68 | `purchase_shopping_item_with_expense(uuid,uuid,uuid)` | `jsonb` | oui | oui | oui | `search_path=public` |
| 69 | `reconcile_cutover_opening_run(uuid)` | `jsonb` | non | oui | oui | `search_path=public` |
| 70 | `record_account_balance_observation(uuid,timestamp with time zone,numeric,text)` | `uuid` | oui | oui | oui | `search_path=public` |
| 71 | `record_expected_financial_match(uuid,uuid,numeric,text,numeric,jsonb,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 72 | `record_member_compensation_action(uuid,text,numeric,uuid,text,jsonb,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 73 | `refresh_monthly_automatic_targets(uuid,date,uuid)` | `jsonb` | oui | oui | oui | `search_path=public, auth` |
| 74 | `register_financial_event_attachment(uuid,uuid,text,text,bigint,uuid)` | `text` | oui | oui | oui | `search_path=public, auth` |
| 75 | `regularize_account_reconciliation(uuid,numeric,text,text,jsonb,timestamp with time zone,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 76 | `remove_household_member(uuid,uuid)` | `void` | oui | oui | non | `search_path=public, auth` |
| 77 | `remove_priority_plan_item(uuid,uuid,uuid)` | `void` | oui | oui | non | `search_path=public` |
| 78 | `reopen_monthly_period(uuid,text,uuid)` | `uuid` | oui | oui | non | `search_path=public, auth` |
| 79 | `reorder_priority_plan_items(uuid,uuid,uuid[])` | `void` | oui | oui | non | `search_path=public` |
| 80 | `resolve_account_reconciliation_by_follow_up(uuid,uuid,text,text)` | `uuid` | oui | oui | oui | `search_path=public` |
| 81 | `reverse_daily_financial_event(uuid,uuid,timestamp with time zone,text,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 82 | `reverse_debt_settlement_event(uuid,uuid,timestamp with time zone,numeric,text,text,uuid)` | `uuid` | non | oui | non | `search_path=public` |
| 83 | `reverse_debt_writeoff_event(uuid,uuid,timestamp with time zone,numeric,text,text,uuid)` | `uuid` | non | oui | non | `search_path=public` |
| 84 | `reverse_income_receivable_settlement_event(uuid,uuid,timestamp with time zone,numeric,text,jsonb,text,uuid)` | `uuid` | non | oui | non | `search_path=public` |
| 85 | `reverse_income_receivable_writeoff_event(uuid,uuid,timestamp with time zone,numeric,text,text,uuid)` | `uuid` | non | oui | non | `search_path=public` |
| 86 | `reverse_reconciliation_regularization(uuid,timestamp with time zone,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 87 | `reverse_recovery_settlement_event(uuid,uuid,timestamp with time zone,numeric,text,text,uuid)` | `uuid` | non | oui | non | `search_path=public` |
| 88 | `reverse_recovery_writeoff_event(uuid,uuid,timestamp with time zone,numeric,text,text,uuid)` | `uuid` | non | oui | non | `search_path=public` |
| 89 | `revoke_household_invitation(uuid)` | `void` | oui | oui | non | `search_path=public, auth` |
| 90 | `save_budget_allocation_run_with_contributions(uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb,jsonb)` | `uuid` | oui | oui | oui | `search_path=public` |
| 91 | `save_budget_allocation_run(uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb)` | `uuid` | oui | oui | oui | `search_path=public` |
| 92 | `save_envelope_account_initial_position_draft(uuid,jsonb)` | `integer` | oui | oui | oui | `search_path=public, auth` |
| 93 | `save_envelope_account_initial_position_unknowns(uuid,jsonb)` | `integer` | oui | oui | oui | `search_path=public, auth` |
| 94 | `save_programmable_budget_run(uuid,uuid,uuid,uuid,uuid,numeric,numeric,numeric,jsonb,jsonb)` | `uuid` | oui | oui | oui | `search_path=public` |
| 95 | `save_recurring_financial_intention(uuid,uuid,text,text,numeric,text,text,date,date,uuid,uuid,uuid,uuid,text,text,uuid,jsonb,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 96 | `set_budget_goal_status(uuid,uuid,text,text)` | `void` | oui | oui | non | `search_path=public` |
| 97 | `set_envelope_account_position_snapshot(uuid,jsonb,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 98 | `set_envelope_recommendation(uuid,uuid,uuid)` | `envelopes` | oui | oui | oui | `search_path=public, auth` |
| 99 | `set_monthly_envelope_account_target_override(uuid,date,uuid,uuid,numeric,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 100 | `set_priority_item_decision(uuid,uuid,text,uuid,text)` | `uuid` | oui | oui | non | `search_path=public` |
| 101 | `set_priority_plan_status(uuid,uuid,text)` | `void` | oui | oui | non | `search_path=public` |
| 102 | `set_recurring_financial_intention_status(uuid,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public, auth` |
| 103 | `set_shopping_financing_plan(uuid,uuid,text,numeric,numeric,uuid,uuid,text)` | `uuid` | oui | oui | non | `search_path=public` |
| 104 | `set_shopping_item_member_priority(uuid,uuid,uuid,integer)` | `void` | oui | oui | non | `search_path=public` |
| 105 | `settle_debt_event(uuid,uuid,timestamp with time zone,text,numeric,uuid,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 106 | `settle_receivable_event(uuid,uuid,timestamp with time zone,text,numeric,uuid,text,uuid,jsonb)` | `uuid` | oui | oui | oui | `search_path=public` |
| 107 | `settle_recovery_event(uuid,uuid,timestamp with time zone,text,numeric,uuid,boolean,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 108 | `soft_delete_financial_event_attachment(uuid)` | `text` | oui | oui | oui | `search_path=public, auth` |
| 109 | `undo_last_envelope_import(uuid)` | `integer` | oui | oui | non | `search_path=public` |
| 110 | `undo_workbook_import(uuid,text)` | `void` | oui | oui | non | `search_path=public` |
| 111 | `update_budget_goal(uuid,uuid,text,text,numeric,date,integer,uuid,numeric,text)` | `void` | oui | oui | non | `search_path=public` |
| 112 | `update_household_envelope(uuid,uuid,text,text,boolean)` | `void` | oui | oui | non | `search_path=public` |
| 113 | `update_household_settings(uuid,text,text)` | `households` | oui | oui | non | `search_path=public, auth` |
| 114 | `update_my_profile(text)` | `profiles` | oui | non | non | `search_path=public, auth` |
| 115 | `update_payment_method(uuid,uuid,uuid,text,text,boolean)` | `payment_methods` | oui | oui | oui | `search_path=public, auth` |
| 116 | `update_priority_plan(uuid,uuid,text,numeric,text)` | `void` | oui | oui | non | `search_path=public` |
| 117 | `update_shopping_item_with_member_priorities(uuid,uuid,text,numeric,text,date,uuid,uuid,integer,jsonb)` | `void` | non | oui | non | `search_path=public` |
| 118 | `update_shopping_item(uuid,uuid,text,numeric,text,date,uuid,uuid,integer)` | `void` | oui | oui | non | `search_path=public` |
| 119 | `writeoff_debt_event(uuid,uuid,timestamp with time zone,numeric,text,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 120 | `writeoff_income_receivable_event(uuid,uuid,timestamp with time zone,numeric,text,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
| 121 | `writeoff_recovery_event(uuid,uuid,timestamp with time zone,numeric,text,text,uuid)` | `uuid` | oui | oui | oui | `search_path=public` |
