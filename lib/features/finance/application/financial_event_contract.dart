/// Pure invariants shared by the future FinancialEvent clients.
///
/// PostgreSQL remains the authoritative enforcement point.  This small model
/// makes the same user-facing preconditions explicit and testable without
/// attempting to emulate the database transaction engine.
class FinancialEventContract {
  const FinancialEventContract._();

  static void validatePositiveAmount(num? amount) {
    if (amount == null || amount <= 0) {
      throw StateError('Un montant strictement positif est requis.');
    }
  }

  static void validateEnvelopeSplit({
    required num totalAmount,
    required Iterable<FinancialEventAllocation> allocations,
  }) {
    validatePositiveAmount(totalAmount);
    final seenEnvelopeIds = <String>{};
    num allocated = 0;
    var count = 0;

    for (final allocation in allocations) {
      if (allocation.envelopeId.trim().isEmpty || allocation.isSystemEnvelope) {
        throw StateError('Une enveloppe ordinaire est requise.');
      }
      validatePositiveAmount(allocation.amount);
      if (!seenEnvelopeIds.add(allocation.envelopeId)) {
        throw StateError('Une enveloppe ne peut apparaître qu’une fois.');
      }
      allocated += allocation.amount;
      count++;
    }

    if (count == 0 || allocated != totalAmount) {
      throw StateError(
        'Les ventilations doivent correspondre au montant total.',
      );
    }
  }

  /// Income may be left entirely to the system envelope « À répartir ».
  /// Explicit ordinary-envelope allocations therefore need only be positive,
  /// unique and no greater than the received amount.
  static void validateIncomeEnvelopeAllocations({
    required num totalAmount,
    required Iterable<FinancialEventAllocation> allocations,
  }) {
    validatePositiveAmount(totalAmount);
    final seenEnvelopeIds = <String>{};
    num allocated = 0;

    for (final allocation in allocations) {
      if (allocation.envelopeId.trim().isEmpty || allocation.isSystemEnvelope) {
        throw StateError('Une enveloppe ordinaire est requise.');
      }
      validatePositiveAmount(allocation.amount);
      if (!seenEnvelopeIds.add(allocation.envelopeId)) {
        throw StateError('Une enveloppe ne peut apparaître qu’une fois.');
      }
      allocated += allocation.amount;
    }

    if (allocated > totalAmount) {
      throw StateError(
        'Les affectations ne peuvent pas dépasser le montant du revenu.',
      );
    }
  }

  static void validateTransfer({
    required String sourceId,
    required String destinationId,
    required num amount,
  }) {
    validatePositiveAmount(amount);
    if (sourceId.trim().isEmpty || destinationId.trim().isEmpty) {
      throw StateError('Une source et une destination sont requises.');
    }
    if (sourceId == destinationId) {
      throw StateError('La source et la destination doivent être différentes.');
    }
  }

  static num remainingAfterSettlement({
    required num initialAmount,
    required num settledAmount,
    required num settlementAmount,
  }) {
    validatePositiveAmount(initialAmount);
    if (settledAmount < 0 || settlementAmount <= 0) {
      throw StateError('Le règlement doit être strictement positif.');
    }
    final remaining = initialAmount - settledAmount;
    if (remaining <= 0 || settlementAmount > remaining) {
      throw StateError('Le règlement dépasse le montant restant.');
    }
    return remaining - settlementAmount;
  }

  static void validateRecoveryRefund({
    required bool sourceEnvelopeIsLinked,
    required num unreimbursedSourceConsumption,
    required num settlementAmount,
  }) {
    validatePositiveAmount(settlementAmount);
    if (!sourceEnvelopeIsLinked) {
      throw StateError(
        'Aucune enveloppe source valide ne peut être remboursée.',
      );
    }
    if (settlementAmount > unreimbursedSourceConsumption) {
      throw StateError(
        'Le remboursement dépasse la consommation source non remboursée.',
      );
    }
  }
}

class FinancialEventAllocation {
  const FinancialEventAllocation({
    required this.envelopeId,
    required this.amount,
    this.isSystemEnvelope = false,
  });

  final String envelopeId;
  final num amount;
  final bool isSystemEnvelope;
}
