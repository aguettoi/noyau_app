import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261010143000_r2_monthly_close_and_reliability.sql',
  ).readAsStringSync();
  final reopenHardening = File(
    'supabase/migrations/20261010213000_r2_1_reopen_idempotence.sql',
  ).readAsStringSync();
  test('R2 storage is household scoped, RLS protected and additive', () {
    expect(sql, contains('monthly_close_periods'));
    expect(sql, contains('monthly_close_events'));
    expect(sql, contains('monthly_envelope_account_targets'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('public.is_household_member'));
    expect(sql, contains("role='owner'"));
  });
  test('close and reopen are audited and idempotent', () {
    expect(sql, contains('unique (household_id, idempotency_key)'));
    expect(sql, contains('Monthly close has hard blockers'));
    expect(sql, contains('Owner reason required for warning override'));
    expect(sql, contains('Reopen reason required'));
    expect(reopenHardening, contains("v_period.status = 'reopened'"));
    expect(reopenHardening, contains("v_period.status <> 'closed'"));
    expect(reopenHardening, contains("role = 'owner'"));
  });
  test('R2 does not mutate financial ledgers', () {
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
  });
}
