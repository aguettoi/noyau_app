import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261011113000_r2_3_human_review_fixes.sql',
  ).readAsStringSync().toLowerCase();
  final hardeningSql = File(
    'supabase/migrations/20261011124500_r2_3_deprecate_legacy_target_rpc.sql',
  ).readAsStringSync().toLowerCase();

  test(
    'automatic targets reuse canonical scenario and account recommendations',
    () {
      expect(sql, contains('monthly_close_automatic_target_preview'));
      expect(sql, contains('budget_periods'));
      expect(sql, contains('budget_scenario_steps'));
      expect(sql, contains('recommended_account_id'));
      expect(sql, contains('funding_source_preference'));
      expect(sql, contains('aucun compte cible canonique unique'));
    },
  );

  test('manual targets are explicit audited monthly overrides', () {
    expect(sql, contains('manual_override'));
    expect(sql, contains('override_reason'));
    expect(sql, contains('owner access denied'));
    expect(sql, contains('closed month targets are immutable'));
  });

  test('planning creates no financial or ledger write', () {
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
  });

  test('RPCs reject anonymous access and validate household references', () {
    expect(sql, contains('auth.uid() is null'));
    expect(sql, contains('household access denied'));
    expect(sql, contains('target reference denied'));
    expect(sql, contains('revoke all on function'));
  });

  test('legacy manual target RPC is no longer executable by app roles', () {
    expect(
      hardeningSql,
      contains(
        'revoke execute on function public.set_monthly_envelope_account_target',
      ),
    );
    expect(hardeningSql, contains('from public, anon, authenticated'));
    expect(
      hardeningSql,
      contains('set_monthly_envelope_account_target_override'),
    );
  });
}
