import '../../../core/money/money.dart';

enum LedgerTransactionType {
  expense,
  income,
  transfer,
  adjustment,
  openingBalance,
  correction,
  debtExpense,
  incomeReceivable,
  recovery,
  recoveryReceivable,
  debtSettlement,
  receivableSettlement,
  recoverySettlement,
  allocation,
  accountTransfer,
  envelopeTransfer,
  unknown,
}

enum BalanceDirection { increase, decrease }

/// Optional, editable context supplied by another business screen before the
/// canonical transaction form is opened. It never posts an operation itself.
class TransactionFormPrefill {
  const TransactionFormPrefill({
    required this.description,
    this.amount,
    this.envelopeId,
    this.notes,
  });

  final String description;
  final Money? amount;
  final String? envelopeId;
  final String? notes;
}

class EnvelopeAllocationDraft {
  const EnvelopeAllocationDraft({
    required this.envelopeId,
    required this.amount,
  });

  final String envelopeId;
  final Money amount;

  String? validate() {
    if (envelopeId.isEmpty) {
      return 'Choisissez une enveloppe.';
    }
    if (amount.minorUnits <= 0) {
      return 'Le montant d’enveloppe doit être positif.';
    }
    return null;
  }
}

class TransactionEnvelopeSplit {
  const TransactionEnvelopeSplit(this.allocations);

  final List<EnvelopeAllocationDraft> allocations;

  Money get total => allocations.fold(
    const Money.fromMinorUnits(0),
    (sum, allocation) => sum + allocation.amount,
  );

  String? validateFor(Money transactionAmount) {
    if (allocations.isEmpty) return 'Une dépense nécessite une enveloppe.';
    final seen = <String>{};
    for (final allocation in allocations) {
      final error = allocation.validate();
      if (error != null) return error;
      if (!seen.add(allocation.envelopeId)) {
        return 'Une enveloppe ne peut apparaître qu’une fois.';
      }
    }
    return total == transactionAmount
        ? null
        : 'Le total ventilé doit égaler le montant de la dépense.';
  }
}

class IncomeEnvelopeSplit {
  const IncomeEnvelopeSplit(this.allocations);

  final List<EnvelopeAllocationDraft> allocations;

  Money get total => allocations.fold(
    const Money.fromMinorUnits(0),
    (sum, allocation) => sum + allocation.amount,
  );

  String? validateFor(Money incomeAmount) {
    final seen = <String>{};
    for (final allocation in allocations) {
      final error = allocation.validate();
      if (error != null) return error;
      if (!seen.add(allocation.envelopeId)) {
        return 'Une enveloppe ne peut apparaître qu’une fois.';
      }
    }
    return total.minorUnits > incomeAmount.minorUnits
        ? 'Le total affecté ne peut pas dépasser le montant du revenu.'
        : null;
  }
}

/// User intent before it is atomically validated and posted to the ledger.
class FinancialTransactionDraft {
  const FinancialTransactionDraft({
    required this.type,
    required this.occurredAt,
    required this.description,
    required this.amount,
    this.sourceAccountId,
    this.destinationAccountId,
    this.categoryId,
    this.notes,
    this.direction = BalanceDirection.increase,
    this.envelopeAllocations = const [],
  });

  final LedgerTransactionType type;
  final DateTime occurredAt;
  final String description;
  final Money amount;
  final String? sourceAccountId;
  final String? destinationAccountId;
  final String? categoryId;
  final String? notes;
  final BalanceDirection direction;
  final List<EnvelopeAllocationDraft> envelopeAllocations;

  String? validate() {
    if (description.trim().isEmpty) return 'Le libellé est obligatoire.';
    if (amount.minorUnits <= 0) return 'Le montant doit être supérieur à zéro.';
    return switch (type) {
      LedgerTransactionType.expense =>
        sourceAccountId == null
            ? 'Choisissez le compte payé.'
            : TransactionEnvelopeSplit(envelopeAllocations).validateFor(amount),
      LedgerTransactionType.income =>
        destinationAccountId == null
            ? 'Choisissez le compte encaissé.'
            : IncomeEnvelopeSplit(envelopeAllocations).validateFor(amount),
      LedgerTransactionType.transfer =>
        sourceAccountId == null || destinationAccountId == null
            ? 'Choisissez les deux comptes du virement.'
            : sourceAccountId == destinationAccountId
            ? 'Les comptes source et destination doivent être différents.'
            : envelopeAllocations.isNotEmpty
            ? 'Un virement ne touche aucune enveloppe.'
            : null,
      LedgerTransactionType.adjustment ||
      LedgerTransactionType.openingBalance ||
      LedgerTransactionType.correction ||
      LedgerTransactionType.debtExpense ||
      LedgerTransactionType.incomeReceivable ||
      LedgerTransactionType.recovery ||
      LedgerTransactionType.recoveryReceivable ||
      LedgerTransactionType.debtSettlement ||
      LedgerTransactionType.receivableSettlement ||
      LedgerTransactionType.recoverySettlement ||
      LedgerTransactionType.allocation ||
      LedgerTransactionType.accountTransfer ||
      LedgerTransactionType.envelopeTransfer ||
      LedgerTransactionType.unknown =>
        sourceAccountId == null
            ? 'Choisissez le compte concerné.'
            : envelopeAllocations.isNotEmpty
            ? 'Un ajustement ne touche aucune enveloppe.'
            : null,
    };
  }
}
