import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260913214354_canonical_opening_positions.sql',
  ).readAsStringSync();
  final envelopeGroupFix = File(
    'supabase/migrations/'
    '20260913214939_fix_envelope_opening_movement_group.sql',
  ).readAsStringSync();

  test('les ouvertures de comptes sont FinancialEvent, GL et idempotentes', () {
    expect(migration, contains("'account_opening'"));
    expect(migration, contains('create_account_opening_event'));
    expect(migration, contains("'opening_balance'"));
    expect(migration, contains("'Système — Soldes d’ouverture'"));
    expect(migration, contains('p_account_id, v_opening_id'));
    expect(migration, contains('Opening amount must be positive'));
    expect(migration, contains('create_or_get_financial_event'));
    expect(migration, contains('for update'));
  });

  test('les ouvertures d’enveloppes ne touchent ni GL ni À répartir', () {
    expect(migration, contains("'envelope_opening'"));
    expect(migration, contains('create_envelope_opening_event'));
    expect(migration, contains("'opening','inflow'"));
    expect(migration, isNot(contains("'opening_offset'")));
    expect(
      migration,
      contains('An envelope can appear only once in an opening'),
    );
    expect(migration, contains("event_type = 'envelope_opening'"));
  });

  test(
    'les ouvertures d’enveloppes respectent le groupe technique obligatoire',
    () {
      expect(envelopeGroupFix, contains('v_movement_group_id uuid'));
      expect(envelopeGroupFix, contains('movement_group_id'));
      expect(envelopeGroupFix, contains("'opening','inflow'"));
    },
  );
}
