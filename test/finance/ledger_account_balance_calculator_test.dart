import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/ledger_account_balance_calculator.dart';
import 'package:noyau_app/features/finance/domain/ledger_entry.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';

void main() {
  test(
    'le solde théorique est le solde d’ouverture plus débits moins crédits',
    () {
      final balance = const LedgerAccountBalanceCalculator().calculate(
        openingBalance: Money.fromMinorUnits(100000),
        accountId: 'cash',
        entries: [
          LedgerEntry(
            accountId: 'cash',
            debit: Money.fromMinorUnits(5000),
            credit: Money.fromMinorUnits(0),
            occurredAt: DateTime(2026, 8, 5),
            description: 'Revenu',
          ),
          LedgerEntry(
            accountId: 'cash',
            debit: Money.fromMinorUnits(0),
            credit: Money.fromMinorUnits(1250),
            occurredAt: DateTime(2026, 8, 5),
            description: 'Dépense',
          ),
          LedgerEntry(
            accountId: 'other',
            debit: Money.fromMinorUnits(999999),
            credit: Money.fromMinorUnits(0),
            occurredAt: DateTime(2026, 8, 5),
            description: 'Autre compte',
          ),
        ],
      );

      expect(balance.minorUnits, 103750);
    },
  );

  test('le remboursement débité diminue une dette affichée positive', () {
    final balance = const LedgerAccountBalanceCalculator().calculate(
      openingBalance: Money.fromMinorUnits(100000),
      accountId: 'loan',
      type: FinancialAccountType.debt,
      entries: [
        LedgerEntry(
          accountId: 'loan',
          debit: Money.fromMinorUnits(25000),
          credit: Money.fromMinorUnits(0),
          occurredAt: DateTime(2026, 8, 5),
          description: 'Remboursement',
        ),
      ],
    );

    expect(balance.minorUnits, 75000);
  });
}
