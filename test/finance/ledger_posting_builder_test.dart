import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/ledger_posting_builder.dart';
import 'package:noyau_app/features/finance/domain/ledger_entry.dart';
import 'package:noyau_app/features/finance/domain/transaction_draft.dart';

void main() {
  const builder = LedgerPostingBuilder();

  FinancialTransactionDraft draft({
    LedgerTransactionType type = LedgerTransactionType.expense,
    String? source = 'account-source',
    String? destination,
    BalanceDirection direction = BalanceDirection.increase,
  }) => FinancialTransactionDraft(
    type: type,
    occurredAt: DateTime(2026, 8, 5),
    description: 'Opération de test',
    amount: Money.fromMinorUnits(12550),
    sourceAccountId: source,
    destinationAccountId: destination,
    direction: direction,
    envelopeAllocations: type == LedgerTransactionType.expense
        ? const [
            EnvelopeAllocationDraft(
              envelopeId: 'envelope-test',
              amount: Money.fromMinorUnits(12550),
            ),
          ]
        : const [],
  );

  void expectBalanced(List<LedgerEntry> lines) {
    final debit = lines.fold<int>(
      0,
      (sum, line) => sum + line.debit.minorUnits,
    );
    final credit = lines.fold<int>(
      0,
      (sum, line) => sum + line.credit.minorUnits,
    );
    expect(debit, credit);
  }

  test('une dépense génère deux écritures équilibrées', () {
    final lines = builder.build(
      draft: draft(),
      counterpartyAccountId: 'system-expense',
    );

    expect(lines.map((line) => line.accountId), [
      'system-expense',
      'account-source',
    ]);
    expect(lines.first.debit.minorUnits, 12550);
    expect(lines.last.credit.minorUnits, 12550);
    expectBalanced(lines);
  });

  test('un revenu augmente le compte destinataire', () {
    final lines = builder.build(
      draft: draft(
        type: LedgerTransactionType.income,
        source: null,
        destination: 'account-income',
      ),
      counterpartyAccountId: 'system-income',
    );

    expect(lines.first.accountId, 'account-income');
    expect(lines.first.debit.minorUnits, 12550);
    expect(lines.last.accountId, 'system-income');
    expectBalanced(lines);
  });

  test('un virement débite la destination et crédite la source', () {
    final lines = builder.build(
      draft: draft(
        type: LedgerTransactionType.transfer,
        destination: 'account-destination',
      ),
      counterpartyAccountId: 'unused',
    );

    expect(lines.first.accountId, 'account-destination');
    expect(lines.last.accountId, 'account-source');
    expectBalanced(lines);
  });

  test('un ajustement négatif diminue le compte concerné', () {
    final lines = builder.build(
      draft: draft(
        type: LedgerTransactionType.adjustment,
        direction: BalanceDirection.decrease,
      ),
      counterpartyAccountId: 'system-adjustment',
    );

    expect(lines.last.accountId, 'account-source');
    expect(lines.last.credit.minorUnits, 12550);
    expectBalanced(lines);
  });

  test('un brouillon invalide ne peut pas être posté', () {
    expect(
      () => builder.build(
        draft: draft(
          type: LedgerTransactionType.transfer,
          destination: 'account-source',
        ),
        counterpartyAccountId: 'unused',
      ),
      throwsStateError,
    );
  });
}
