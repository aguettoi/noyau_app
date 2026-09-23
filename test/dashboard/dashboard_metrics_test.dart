import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/dashboard/application/dashboard_metrics.dart';

void main() {
  test(
    'monthly flow recognises only income and expense origin transactions',
    () {
      final flow = DashboardMonthlyFlow.fromTransactionRows([
        {'type': 'income', 'amount': '120.00'},
        {'type': 'income_receivable', 'amount': '80.00'},
        {'type': 'expense', 'amount': '50.00'},
        {'type': 'debt_expense', 'amount': '30.00'},
        {'type': 'debt_settlement', 'amount': '30.00'},
        {'type': 'receivable_settlement', 'amount': '80.00'},
        {'type': 'recovery_settlement', 'amount': '20.00'},
        {'type': 'account_transfer', 'amount': '40.00'},
        {'type': 'envelope_transfer', 'amount': '40.00'},
      ]);

      expect(flow.income, const Money.fromMinorUnits(20000));
      expect(flow.expense, const Money.fromMinorUnits(8000));
      expect(flow.remainder, const Money.fromMinorUnits(12000));
    },
  );

  test('invalid amounts cannot become a dashboard financial flow', () {
    final flow = DashboardMonthlyFlow.fromTransactionRows([
      {'type': 'income', 'amount': 'not-a-number'},
      {'type': 'expense', 'amount': null},
    ]);

    expect(flow.income, const Money.fromMinorUnits(0));
    expect(flow.expense, const Money.fromMinorUnits(0));
  });

  test('dashboard composition keeps its Supabase access read-only', () {
    final source = File(
      'lib/features/dashboard/application/providers/remote_financial_dashboard_provider.dart',
    ).readAsStringSync();

    expect(source, contains(".from('financial_transactions')"));
    expect(source, contains(".select('type, amount')"));
    expect(source, isNot(contains('.rpc(')));
    expect(source, isNot(contains('.insert(')));
    expect(source, isNot(contains('.update(')));
    expect(source, isNot(contains('.delete(')));
  });
}
