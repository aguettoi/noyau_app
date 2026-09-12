import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260909200448_obligation_settlement_reversals.sql',
  ).readAsStringSync();

  test('introduit des reversals de settlement immuables et bornés', () {
    expect(
      migration,
      contains('create table public.obligation_settlement_reversals'),
    );
    expect(migration, contains('source_settlement_id'));
    expect(migration, contains('obligation_settlement_reversals_immutable'));
    expect(
      migration,
      contains('Settlement reversal exceeds the amount still reversible'),
    );
    expect(migration, contains('unique (financial_event_id)'));
  });

  test('calcule le net settled sans altérer les settlements originaux', () {
    expect(migration, contains('gross_settled_amount'));
    expect(migration, contains('settlement_reversed_amount'));
    expect(migration, contains('net_settled_amount'));
    expect(migration, contains('as settled_amount'));
  });

  test('contre-passe les trois familles canoniques', () {
    for (final rpc in const [
      'reverse_debt_settlement_event',
      'reverse_income_receivable_settlement_event',
      'reverse_recovery_settlement_event',
    ]) {
      expect(migration, contains('function public.$rpc'));
    }
    expect(migration, contains('for update of s,o'));
    expect(migration, contains('p_idempotency_key'));
  });

  test(
    'impose une ventilation explicite pour le revenu et un refund source pour Recovery',
    () {
      expect(
        migration,
        contains(
          'Income reversal envelope allocations must equal the reversal amount',
        ),
      );
      expect(migration, contains("movement_type='allocation'"));
      expect(migration, contains("movement_type='refund'"));
      expect(migration, contains("'reversal','outflow'"));
    },
  );

  test(
    'remplace le full-only envelope reversal par un cumul partiel borné',
    () {
      expect(
        migration,
        contains(
          'drop index if exists public.envelope_movements_single_reversal_idx',
        ),
      );
      expect(migration, contains('envelope_movements_reversal_source_idx'));
      expect(
        migration,
        contains('Envelope reversal exceeds the amount still reversible'),
      );
    },
  );
}
