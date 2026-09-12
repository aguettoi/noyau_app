import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260906192205_income_receivable_settlement_envelope_allocations.sql',
  ).readAsStringSync();
  final sqlTest = File(
    'docs/SANDBOX_INCOME_RECEIVABLE_SETTLEMENT_ENVELOPES_TEST.sql',
  ).readAsStringSync();
  final historicalDiagnostic = File(
    'docs/SANDBOX_INCOME_RECEIVABLE_SETTLEMENT_ENVELOPE_COMPENSATION_DIAGNOSTIC.sql',
  ).readAsStringSync();

  test(
    'le règlement income reçoit des allocations facultatives sans revenu',
    () {
      expect(migration, contains('p_envelope_allocations jsonb default'));
      expect(migration, contains("'receivable_settlement'"));
      expect(migration, contains("'to_allocate'"));
      expect(
        migration,
        contains('Receivable envelope allocations cannot exceed'),
      );
      expect(
        migration,
        contains('Receivable allocation envelope is not an active ordinary'),
      );
      expect(
        migration,
        contains('An envelope can appear only once in a receivable split'),
      );
      expect(migration, isNot(contains("'income', p_occurred_at")));
    },
  );

  test(
    'le validateur autorise seulement le groupe receivable settlement visé',
    () {
      expect(migration, contains("elsif v_event_type='receivable_settlement'"));
      expect(
        migration,
        contains("v_transaction_type<>'receivable_settlement'"),
      );
      expect(migration, contains("v_event_type='cash_income'"));
      expect(migration, contains("v_event_type='budget_allocation'"));
      expect(
        migration,
        contains("v_transaction_type not in ('expense','debt_expense')"),
      );
    },
  );

  test('la recette SQL est transactionnelle et couvre les treize cas', () {
    expect(sqlTest, contains('begin;'));
    expect(sqlTest, contains('rollback;'));
    expect(sqlTest, contains('select 13 as total, 13 as passed, 0 as failed'));
    for (final marker in const [
      '_NONE_SETTLEMENT',
      '_PARTIAL_SETTLEMENT',
      '_MULTI_SETTLEMENT',
      '_FULL_SETTLEMENT',
      '_OVER',
      '_SYSTEM',
      '_DUP',
      '_OTHER',
      '_OVER_SETTLEMENT',
      '_IDEMPOTENT',
    ]) {
      expect(sqlTest, contains(marker));
    }
  });

  test('le diagnostic historique est strictement read-only', () {
    expect(historicalDiagnostic, contains('proposed_to_allocate_compensation'));
    expect(historicalDiagnostic, contains('where envelope_movement_count=0'));
    expect(historicalDiagnostic.toLowerCase(), isNot(contains('insert into')));
    expect(historicalDiagnostic.toLowerCase(), isNot(contains('update ')));
    expect(historicalDiagnostic.toLowerCase(), isNot(contains('delete ')));
  });
}
