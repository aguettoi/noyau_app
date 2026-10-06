import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql, hardening, atomicTransfer;
  setUpAll(() {
    sql = File(
      'supabase/migrations/20261006111500_f3_compensations_and_regularizations.sql',
    ).readAsStringSync().toLowerCase();
    hardening = File(
      'supabase/migrations/20261006143000_f3_1_close_workflows.sql',
    ).readAsStringSync().toLowerCase();
    atomicTransfer = File(
      'supabase/migrations/20261006143500_f3_1_atomic_compensation_transfer.sql',
    ).readAsStringSync().toLowerCase();
  });
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
  test('F3.1 closes partial receipt and canonical reversal', () {
    expect(hardening, contains('pending_receipt'));
    expect(hardening, contains('receipt exceeds declared transfers'));
    expect(hardening, contains('reverse_reconciliation_regularization'));
    expect(hardening, contains("v_e.event_type<>'reconciliation_adjustment'"));
    expect(hardening, contains('reversal_of_resolution_id'));
    expect(hardening, contains("event_type='account_transfer'"));
  });
  test('assisted compensation transfer is one atomic canonical RPC', () {
    expect(atomicTransfer, contains('create_compensation_account_transfer'));
    expect(atomicTransfer, contains('create_account_transfer_event'));
    expect(atomicTransfer, contains('record_member_compensation_action'));
    expect(atomicTransfer, contains('remaining_amount-v_c.pending_receipt'));
  });
}
