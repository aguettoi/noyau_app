import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la migration PRIOS reste une couche de planification sans ledger', () {
    final sql = File(
      'supabase/migrations/20260923230126_priority_plans_mvp.sql',
    ).readAsStringSync();

    expect(sql, contains('create table public.priority_plans'));
    expect(sql, contains('create table public.priority_plan_items'));
    expect(sql, contains('num_nonnulls(shopping_item_id, budget_goal_id) = 1'));
    expect(sql, contains('references public.shopping_items(id, household_id)'));
    expect(sql, contains('references public.budget_goals(id, household_id)'));
    expect(sql, contains('assert_priority_plan_source'));
    expect(sql, contains('reorder_priority_plan_items'));
    expect(sql, contains('auth.uid()'));
    expect(sql, contains('enable row level security'));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
    expect(sql, isNot(contains('insert into public.obligations')));
  });

  test('la garde interne PRIOS n’est pas exposée à anon ni authenticated', () {
    final sql = File(
      'supabase/migrations/20260923231911_priority_plan_internal_guard_permissions.sql',
    ).readAsStringSync();

    expect(sql, contains('assert_priority_plan_source'));
    expect(sql, contains('from anon, authenticated'));
  });
}
