import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260912152549_obligation_limits_settlement_reversal.sql',
  ).readAsStringSync();

  test('aligne les deux plafonds Phase 1 sur le net des settlements', () {
    for (final function in const [
      'assert_obligation_settlement_limit',
      'assert_obligation_adjustment_limit',
    ]) {
      expect(
        migration,
        contains('function public.$function'),
        reason: '$function doit appliquer le même invariant.',
      );
    }
    expect(migration, contains('v_gross_settlements - v_settlement_reversals'));
    expect(migration, contains("adjustment_kind = 'writeoff'"));
  });

  test('ne donne pas de sémantique Phase 2 aux reversals de write-off', () {
    expect(
      migration,
      contains("adjustment_kind = 'reversal' is deliberately excluded"),
    );
    expect(
      migration,
      isNot(contains('create function public.reverse_writeoff')),
    );
  });
}
