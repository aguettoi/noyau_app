import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261016221410_r2_13_1_shared_initial_position_draft.sql',
  ).readAsStringSync();

  test('R2.13.1 stores one household-scoped non-financial shared draft', () {
    expect(sql, contains('envelope_account_initial_position_drafts'));
    expect(sql, contains('public.is_household_member(p_household_id)'));
    expect(sql, contains("batch_kind='explicit_snapshot'"));
    expect(
      sql,
      contains("'human_confirmation','opening_inventory_arbitration'"),
    );
    expect(sql, isNot(contains('financial_events')));
    expect(sql, isNot(contains('gl_transactions')));
    expect(sql, isNot(contains('envelope_movements')));
  });

  test('R2.13.1 validates account and envelope in the same household', () {
    expect(sql, contains('id=v_account and household_id=p_household_id'));
    expect(sql, contains('id=v_envelope and household_id=p_household_id'));
    expect(sql, contains('pg_advisory_xact_lock'));
  });
}
