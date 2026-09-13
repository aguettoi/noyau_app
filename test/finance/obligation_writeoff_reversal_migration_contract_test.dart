import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260913122822_obligation_writeoff_reversals.sql',
  ).readAsStringSync();

  test('defines explicit write-off reversal event and transaction types', () {
    expect(migration, contains('debt_writeoff_reversal'));
    expect(migration, contains('income_receivable_writeoff_reversal'));
    expect(migration, contains('recovery_writeoff_reversal'));
  });

  test('links a reversal to one exact write-off adjustment', () {
    expect(migration, contains('reverses_adjustment_id'));
    expect(migration, contains('assert_obligation_adjustment_reversal_source'));
    expect(migration, contains("v_source.adjustment_kind <> 'writeoff'"));
  });

  test('uses the net write-off invariant in the view and both guards', () {
    expect(migration, contains('+ coalesce(a.writeoff_reversed_amount, 0)'));
    expect(migration, contains('v_writeoffs - v_writeoff_reversals'));
    expect(migration, contains('net_written_off_amount'));
  });

  test('creates three family-specific append-only RPCs', () {
    expect(migration, contains('reverse_debt_writeoff_event'));
    expect(migration, contains('reverse_income_receivable_writeoff_event'));
    expect(migration, contains('reverse_recovery_writeoff_event'));
    expect(migration, contains('create_or_get_financial_event'));
    expect(migration, contains('for update of o, a'));
  });

  test('keeps write-off reversals cash and envelope neutral', () {
    expect(migration, contains('null, null, v_debit_account_id'));
    expect(migration, isNot(contains('insert into public.envelope_movements')));
  });

  test('uses the audited debit and credit system accounts', () {
    expect(migration, contains("'debt_writeoff_gain'"));
    expect(migration, contains("'debt'"));
    expect(migration, contains("'receivable_loss'"));
    expect(migration, contains("'recovery'"));
  });
}
