import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/domain/financial_transaction.dart';
import 'package:noyau_app/features/finance/domain/ledger_line.dart';

void main() {
  test('une écriture de transfert équilibrée conserve le total', () {
    final transaction = FinancialTransaction(
      id: 'transfer-1',
      type: FinancialTransactionType.transfer,
      occurredAt: DateTime(2026, 7, 30),
      reason: 'Réserve voiture',
      createdByMemberId: 'ibrahim',
      lines: [
        LedgerLine(accountId: 'budget-food', amount: Money.fromDirhams(-100)),
        LedgerLine(accountId: 'budget-savings', amount: Money.fromDirhams(100)),
      ],
    );

    expect(transaction.isBalanced, isTrue);
  });
}
