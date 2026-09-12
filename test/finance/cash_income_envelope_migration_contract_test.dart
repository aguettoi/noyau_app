import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260902201124_cash_income_envelope_allocations.sql',
  ).readAsStringSync();
  final sqlTest = File(
    'docs/SANDBOX_CASH_INCOME_ENVELOPE_ALLOCATIONS_TEST.sql',
  ).readAsStringSync();

  test(
    'cash income is an atomic FinancialEvent with controlled allocations',
    () {
      expect(migration, contains("'cash_income'"));
      expect(
        migration,
        contains('create or replace function public.create_cash_income_event'),
      );
      expect(migration, contains("'income'"));
      expect(migration, contains("'to_allocate'"));
      expect(migration, contains('Income envelope allocations cannot exceed'));
      expect(
        migration,
        contains('An envelope can appear only once in an income split'),
      );
      expect(
        migration,
        contains('on function public.create_cash_income_event'),
      );
      expect(migration, contains('to authenticated;'));
      expect(migration.trimRight(), endsWith('commit;'));
    },
  );

  test('recette SQL couvre les treize cas cash income sans persistance', () {
    expect(sqlTest, contains('13 as total'));
    expect(sqlTest, contains('rollback;'));
    for (final text in const [
      '_NONE',
      '_PARTIAL',
      '_FULL',
      '_OVER',
      '_ENV',
      '_ACCOUNT',
      '_DUP',
      '_IDEMPOTENT',
    ]) {
      expect(sqlTest, contains(text));
    }
  });
}
