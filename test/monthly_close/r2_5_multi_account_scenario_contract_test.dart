import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R2.5 preview derives multi-account targets from Budget Intelligence', () {
    final sql = File(
      'supabase/migrations/20261011161409_r2_5_restore_canonical_target_preview.sql',
    ).readAsStringSync();

    expect(sql, contains('monthly_close_automatic_target_preview'));
    expect(sql, contains('budget_scenario_steps'));
    expect(sql, contains('funding_source_preference'));
    expect(sql, contains('ss.missing_sources=0'));
    expect(sql, contains("ss.method in ('fixed','percentage')"));
    expect(sql, contains('balance-coalesce(sum(part)'));
    expect(sql, contains("'Scénario '||coalesce(v_name,'actif')"));
    expect(sql, contains('and not e.is_system'));
    expect(sql, isNot(contains('recommended_payment_method_id')));
    expect(sql, contains("'complete',jsonb_array_length(v_missing)=0"));
    expect(sql, isNot(contains('financial_events')));
    expect(sql, isNot(contains('financial_transactions')));
    expect(sql, isNot(contains('envelope_movements')));
  });

  test('R2.5 freezes the selected scenario by budget month', () {
    final sql = File(
      'supabase/migrations/20261011213758_r2_5_monthly_scenario_history.sql',
    ).readAsStringSync();

    expect(sql, contains('r2_freeze_budget_period_scenario'));
    expect(sql, contains('Budget period scenario is already frozen'));
    expect(sql, contains('before insert on public.budget_allocation_runs'));
    expect(sql, contains('and bp.scenario_id is not null'));
    expect(sql, isNot(contains("bp.status='active'")));
  });
}
