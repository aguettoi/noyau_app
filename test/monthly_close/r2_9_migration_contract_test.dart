import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261014070553_r2_9_initial_position_evidence.sql',
  ).readAsStringSync();

  test('R2.9 stores traceable evidence without financial writes', () {
    expect(sql, contains('envelope_account_initial_evidence'));
    expect(sql, contains('source_fingerprint'));
    expect(sql, contains('human_confirmation'));
    expect(sql, contains('financial_writes'));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.gl_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
  });

  test('R2.9 hardens ownership, evidence, idempotence and concurrency', () {
    expect(sql, contains("v_role <> 'owner'"));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('idempotency_key=p_idempotency_key'));
    expect(sql, contains('The initial position matrix already exists'));
    expect(sql, contains('Unverified source evidence'));
    expect(sql, contains('Snapshot does not reconcile account balances'));
    expect(sql, contains('Snapshot does not reconcile envelope balances'));
  });

  test('R2.9 remains household scoped and cross-household safe', () {
    expect(sql, contains('public.is_household_member(p_household_id)'));
    expect(sql, contains('household_id=p_household_id'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('revoke all'));
  });
}
