import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261011153000_r2_4_envelope_recommendations.sql',
  ).readAsStringSync().toLowerCase();
  final fixSql = File(
    'supabase/migrations/20261011154500_r2_4_budget_period_column_fix.sql',
  ).readAsStringSync().toLowerCase();
  final hardeningSql = File(
    'supabase/migrations/20261011160000_r2_4_target_source_hardening.sql',
  ).readAsStringSync().toLowerCase();

  test('réutilise les recommandations F2 et le scénario actif', () {
    expect(sql, contains('recommended_account_id'));
    expect(sql, contains('budget_scenario_steps'));
    expect(sql, contains('funding_source_preference'));
    expect(sql, contains('répartition multi-comptes'));
    expect(fixSql, contains('bp.starts_on<=v_month'));
    expect(fixSql, contains('bp.ends_on>=v_month'));
    expect(fixSql, isNot(contains('period_start')));
    expect(hardeningSql, contains('a.archived_at is null'));
    expect(hardeningSql, contains('group by envelope_id,account_id'));
  });

  test('refuse les références inactives et cross-household', () {
    expect(sql, contains('account household mismatch or inactive'));
    expect(sql, contains('payment method household mismatch or inactive'));
    expect(sql, contains('public.is_household_member'));
    expect(sql, contains('recommendation account or holder mismatch'));
  });

  test('conserve un audit sans écriture financière', () {
    expect(sql, contains('envelope_recommendation_events'));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
  });
}
