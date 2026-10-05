import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261005140000_f2b_expense_payment_context.sql',
  ).readAsStringSync();
  final hardening = File(
    'supabase/migrations/20261005143000_f2b_immutable_expense_payment_context.sql',
  ).readAsStringSync();

  test('PAY-03 reste une extension du FinancialEvent canonique', () {
    expect(sql, contains('actual_payment_method_id uuid'));
    expect(sql, contains('payment_recommendation_snapshot jsonb'));
    expect(sql, contains('create_cash_expense_with_payment_context'));
    expect(sql, contains('public.create_cash_expense_event('));
    expect(sql, contains('Payment method household mismatch'));
    expect(sql, contains('Payment method account mismatch'));
    expect(sql, contains('Inactive payment method'));
    expect(sql, contains('Idempotent expense replay has different'));
  });

  test('PAY-03 ne crée aucune compensation ni nouveau ledger', () {
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
    expect(sql, isNot(contains('insert into public.obligations')));
    expect(sql, isNot(contains('reconciliation_adjustment')));
  });

  test(
    'le contexte final est append-only et ne mute pas le FinancialEvent',
    () {
      expect(
        hardening,
        contains('create table public.expense_payment_contexts'),
      );
      expect(hardening, contains('expense_payment_contexts_immutable'));
      expect(
        hardening,
        contains('insert into public.expense_payment_contexts'),
      );
      expect(hardening, isNot(contains('update public.financial_events')));
      expect(
        hardening,
        isNot(contains('insert into public.financial_transactions')),
      );
      expect(
        hardening,
        isNot(contains('insert into public.envelope_movements')),
      );
    },
  );

  test('la RPC est réservée aux utilisateurs authentifiés', () {
    expect(sql, contains('auth.uid() is null'));
    expect(sql, contains('is_household_member'));
    expect(sql, contains('revoke all on function'));
    expect(sql, contains('from public, anon'));
    expect(sql, contains('to authenticated'));
  });
}
