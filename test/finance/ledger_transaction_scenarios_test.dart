import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/ledger_account_balance_calculator.dart';
import 'package:noyau_app/features/finance/application/ledger_posting_builder.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';

void main() {
  const postingBuilder = LedgerPostingBuilder();
  const balanceCalculator = LedgerAccountBalanceCalculator();

  FinancialTransactionDraft draft({
    required LedgerTransactionType type,
    required int amountCents,
    String? sourceAccountId,
    String? destinationAccountId,
    BalanceDirection direction = BalanceDirection.increase,
  }) => FinancialTransactionDraft(
    type: type,
    occurredAt: DateTime.utc(2026, 8, 5, 12),
    description: 'Validation moteur comptable',
    amount: Money.fromMinorUnits(amountCents),
    sourceAccountId: sourceAccountId,
    destinationAccountId: destinationAccountId,
    direction: direction,
    envelopeAllocations: type == LedgerTransactionType.expense
        ? [
            EnvelopeAllocationDraft(
              envelopeId: 'envelope-test',
              amount: Money.fromMinorUnits(amountCents),
            ),
          ]
        : const [],
  );

  test(
    'dépense, revenu, virement et ajustement produisent des écritures équilibrées',
    () {
      final entries = [
        ...postingBuilder.build(
          draft: draft(
            type: LedgerTransactionType.expense,
            amountCents: 5000,
            sourceAccountId: 'cash',
          ),
          counterpartyAccountId: 'system-expense',
        ),
        ...postingBuilder.build(
          draft: draft(
            type: LedgerTransactionType.income,
            amountCents: 20000,
            destinationAccountId: 'bank',
          ),
          counterpartyAccountId: 'system-income',
        ),
        ...postingBuilder.build(
          draft: draft(
            type: LedgerTransactionType.transfer,
            amountCents: 3000,
            sourceAccountId: 'bank',
            destinationAccountId: 'cash',
          ),
          counterpartyAccountId: 'unused',
        ),
        ...postingBuilder.build(
          draft: draft(
            type: LedgerTransactionType.adjustment,
            amountCents: 1000,
            sourceAccountId: 'cash',
            direction: BalanceDirection.decrease,
          ),
          counterpartyAccountId: 'system-adjustment',
        ),
      ];

      expect(
        entries.fold<int>(0, (sum, entry) => sum + entry.debit.minorUnits),
        entries.fold<int>(0, (sum, entry) => sum + entry.credit.minorUnits),
      );
      expect(
        balanceCalculator
            .calculate(
              openingBalance: Money.fromMinorUnits(10000),
              accountId: 'cash',
              entries: entries,
            )
            .minorUnits,
        7000,
      );
      expect(
        balanceCalculator
            .calculate(
              openingBalance: Money.fromMinorUnits(0),
              accountId: 'bank',
              entries: entries,
            )
            .minorUnits,
        17000,
      );
    },
  );

  test('la projection de solde correspond à la formule de la vue distante', () {
    final entries = postingBuilder.build(
      draft: draft(
        type: LedgerTransactionType.transfer,
        amountCents: 1250,
        sourceAccountId: 'source',
        destinationAccountId: 'destination',
      ),
      counterpartyAccountId: 'unused',
    );

    final sourceBalance = balanceCalculator.calculate(
      openingBalance: Money.fromMinorUnits(10000),
      accountId: 'source',
      entries: entries,
    );
    final destinationBalance = balanceCalculator.calculate(
      openingBalance: Money.fromMinorUnits(2000),
      accountId: 'destination',
      entries: entries,
    );

    expect(sourceBalance.minorUnits, 8750);
    expect(destinationBalance.minorUnits, 3250);
    expect(sourceBalance.minorUnits + destinationBalance.minorUnits, 12000);
  });
}
