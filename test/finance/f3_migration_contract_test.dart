import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;
  setUpAll(
    () => sql = File(
      'supabase/migrations/20261006111500_f3_compensations_and_regularizations.sql',
    ).readAsStringSync().toLowerCase(),
  );
  test('compensations are specialized append-only and non economic', () {
    expect(sql, contains('create table public.member_compensations'));
    expect(
      sql,
      contains("'transfer_declared','receipt_confirmed','abandoned'"),
    );
    expect(sql, contains('prevent_financial_event_mutation'));
    expect(sql, isNot(contains("event_type='cash_income'")));
  });
  test('regularization is canonical and envelope allocations are explicit', () {
    expect(sql, contains('regularize_account_reconciliation'));
    expect(sql, contains("'reconciliation_adjustment'"));
    expect(
      sql,
      contains('envelope allocations must equal regularization amount'),
    );
    expect(sql, contains('insert_financial_event_ledger_transaction'));
  });
  test('security and idempotence are household scoped', () {
    expect(sql, contains('is_household_member'));
    expect(sql, contains('unique(household_id,idempotency_key)'));
  });
}
