import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261014214019_r2_11_opening_position_provenance.sql',
  ).readAsStringSync().toLowerCase();

  test('R2.11 stores the four canonical opening provenances', () {
    for (final value in [
      'source_proof',
      'human_confirmation',
      'opening_inventory_arbitration',
      'balancing_deduction',
    ]) {
      expect(sql, contains(value));
    }
  });

  test(
    'source proof remains verified while business confirmation is explicit',
    () {
      expect(sql, contains("v_provenance='source_proof' and not exists"));
      expect(sql, contains('unverified source evidence'));
      expect(sql, contains('provenance reference is required'));
    },
  );

  test(
    'history exposes actor timestamp batch note and stays household scoped',
    () {
      expect(sql, contains('envelope_account_opening_history'));
      expect(sql, contains("'created_by',e.created_by"));
      expect(sql, contains("'created_at',e.created_at"));
      expect(sql, contains("'batch_id',b.id"));
      expect(sql, contains("'note',b.note"));
      expect(sql, contains('is_household_member(p_household_id)'));
    },
  );
}
