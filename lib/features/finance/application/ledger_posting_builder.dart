import '../../../core/money/money.dart';
import '../domain/ledger_entry.dart';
import '../domain/transaction_draft.dart';

/// Converts a validated user intent into balanced double-entry postings.
class LedgerPostingBuilder {
  const LedgerPostingBuilder();

  List<LedgerEntry> build({
    required FinancialTransactionDraft draft,
    required String counterpartyAccountId,
  }) {
    final validationError = draft.validate();
    if (validationError != null) throw StateError(validationError);

    final amount = draft.amount;
    final description = draft.description.trim();
    final date = draft.occurredAt;
    LedgerEntry debit(String accountId) => LedgerEntry(
      accountId: accountId,
      debit: amount,
      credit: const Money.fromMinorUnits(0),
      occurredAt: date,
      description: description,
    );
    LedgerEntry credit(String accountId) => LedgerEntry(
      accountId: accountId,
      debit: const Money.fromMinorUnits(0),
      credit: amount,
      occurredAt: date,
      description: description,
    );

    final lines = switch (draft.type) {
      LedgerTransactionType.expense => [
        debit(counterpartyAccountId),
        credit(draft.sourceAccountId!),
      ],
      LedgerTransactionType.income => [
        debit(draft.destinationAccountId!),
        credit(counterpartyAccountId),
      ],
      LedgerTransactionType.transfer => [
        debit(draft.destinationAccountId!),
        credit(draft.sourceAccountId!),
      ],
      LedgerTransactionType.adjustment ||
      LedgerTransactionType.openingBalance ||
      LedgerTransactionType.correction =>
        draft.direction == BalanceDirection.increase
            ? [debit(draft.sourceAccountId!), credit(counterpartyAccountId)]
            : [debit(counterpartyAccountId), credit(draft.sourceAccountId!)],
      _ => throw StateError(
        'Ce type de transaction doit être créé par son RPC métier dédié.',
      ),
    };
    final debitTotal = lines.fold<int>(
      0,
      (sum, line) => sum + line.debit.minorUnits,
    );
    final creditTotal = lines.fold<int>(
      0,
      (sum, line) => sum + line.credit.minorUnits,
    );
    if (debitTotal != creditTotal) {
      throw StateError('La transaction n’est pas équilibrée.');
    }
    return List.unmodifiable(lines);
  }
}
