import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261014203935_r2_10_global_transfer_netting.sql',
  ).readAsStringSync().toLowerCase();

  test('R2.10 independently validates global netting and current targets', () {
    expect(sql, contains('r2_expected_transfers'));
    expect(sql, contains('deterministic global net'));
    expect(sql, contains('do not reach the current monthly targets'));
    expect(sql, contains('proposal is stale'));
    expect(sql, contains('pg_advisory_xact_lock'));
  });

  test('R2.10 keeps analytical evidence and executes canonical transfers', () {
    expect(sql, contains('envelope_account_reallocation_justifications'));
    expect(sql, contains('envelope_account_physical_transfers'));
    expect(sql, contains('create_account_transfer_event'));
    expect(sql, contains('economic_date'));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
    expect(sql, isNot(contains('insert into public.gl_transactions')));
  });

  test('R2.10 is owner-only, household-scoped and idempotent', () {
    expect(sql, contains("v_role<>'owner'"));
    expect(sql, contains('household_id=p_household_id'));
    expect(sql, contains('idempotency_key=p_idempotency_key'));
    expect(sql, contains('enable row level security'));
    expect(sql, contains('revoke all'));
  });
}
