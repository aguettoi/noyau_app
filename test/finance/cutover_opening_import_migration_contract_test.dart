import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260914184757_canonical_cutover_opening_import.sql',
  ).readAsStringSync();

  test('B1 persiste un run immuable et une identité de replay stable', () {
    expect(migration, contains('cutover_opening_runs'));
    expect(migration, contains('source_fingerprint'));
    expect(migration, contains('plan_fingerprint'));
    expect(
      migration,
      contains(
        'unique (household_id, source_fingerprint, effective_date, scope)',
      ),
    );
    expect(migration, contains('return v_existing.result'));
    expect(migration, contains('auth.uid()'));
  });

  test('B1 délègue exclusivement les positions aux primitives Cutover A', () {
    expect(migration, contains('create_account_opening_event'));
    expect(migration, contains('create_envelope_opening_event'));
    expect(migration, isNot(contains("'opening_offset'")));
    expect(
      migration,
      contains(
        'opening_balance)\n      values (p_household_id,v_account_name,v_kind,0)',
      ),
    );
    expect(migration, contains('automatic_correction'));
  });

  test(
    'B1 verrouille, valide le household, le fingerprint et les montants',
    () {
      expect(migration, contains('assert_household_access(p_household_id)'));
      expect(migration, contains('for update'));
      expect(migration, contains('SHA-256 source fingerprint'));
      expect(migration, contains('positive opening'));
      expect(migration, contains('Duplicate account target in plan'));
      expect(migration, contains('Duplicate envelope target in plan'));
    },
  );
}
