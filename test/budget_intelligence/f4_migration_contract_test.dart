import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261006203056_f4_budget_continuity_and_decisions.sql',
  ).readAsStringSync();

  test('F4 continuity copies configuration only', () {
    expect(sql, contains('prepare_budget_period_v2'));
    expect(sql, contains("p_mode not in ('empty','copy_previous')"));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
    expect(sql, contains('v_new_scenario'));
    expect(sql, contains('budget_scenario_steps'));
  });

  test('joint approvals are revision bound and apply remains unique', () {
    expect(sql, contains('budget_run_revision_hash'));
    expect(sql, contains('budget_run_approvals'));
    expect(sql, contains("budget_validation_mode"));
    expect(sql, contains('Budget approvals are incomplete or obsolete'));
  });

  test('Shopping and PRIOS decisions stay planning-only', () {
    expect(sql, contains('shopping_financing_plans'));
    expect(sql, contains('priority_item_decisions'));
    expect(sql, contains("'projected_bonus'"));
    expect(sql, contains("'buy_now','wait','fund_progressively'"));
    expect(sql, isNot(contains('allocate_budget_event(')));
  });
}
