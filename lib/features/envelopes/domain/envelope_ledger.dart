import '../../../core/money/money.dart';

enum EnvelopeMovementType {
  allocation,
  consumption,
  transferOut,
  transferIn,
  refund,
  adjustment,
  reversal,
}

enum EnvelopeMovementDirection { inflow, outflow }

/// Immutable entry in the budget ledger. [amount] is always strictly positive;
/// [direction] carries the economic sign.
class EnvelopeMovement {
  const EnvelopeMovement({
    required this.id,
    required this.householdId,
    required this.envelopeId,
    required this.movementGroupId,
    required this.type,
    required this.direction,
    required this.amount,
    required this.occurredAt,
    required this.description,
    required this.createdBy,
    required this.createdAt,
    this.financialTransactionId,
    this.reversalOf,
  });

  final String id;
  final String householdId;
  final String envelopeId;
  final String movementGroupId;
  final EnvelopeMovementType type;
  final EnvelopeMovementDirection direction;
  final Money amount;
  final DateTime occurredAt;
  final String description;
  final String createdBy;
  final DateTime createdAt;
  final String? financialTransactionId;
  final String? reversalOf;

  Money get signedAmount => direction == EnvelopeMovementDirection.inflow
      ? amount
      : Money.fromMinorUnits(-amount.minorUnits);

  bool get isValid =>
      id.isNotEmpty &&
      householdId.isNotEmpty &&
      envelopeId.isNotEmpty &&
      movementGroupId.isNotEmpty &&
      amount.minorUnits > 0 &&
      description.trim().isNotEmpty &&
      createdBy.isNotEmpty &&
      isTypeDirectionAllowed(type, direction) &&
      (type == EnvelopeMovementType.reversal
          ? reversalOf != null && reversalOf!.isNotEmpty
          : reversalOf == null);

  static bool isTypeDirectionAllowed(
    EnvelopeMovementType type,
    EnvelopeMovementDirection direction,
  ) => switch (type) {
    EnvelopeMovementType.allocation ||
    EnvelopeMovementType.transferIn ||
    EnvelopeMovementType.refund =>
      direction == EnvelopeMovementDirection.inflow,
    EnvelopeMovementType.consumption || EnvelopeMovementType.transferOut =>
      direction == EnvelopeMovementDirection.outflow,
    EnvelopeMovementType.adjustment || EnvelopeMovementType.reversal => true,
  };
}

class EnvelopeBalance {
  const EnvelopeBalance({
    required this.householdId,
    required this.envelopeId,
    required this.inflows,
    required this.outflows,
    required this.lastMovementAt,
  });

  final String householdId;
  final String envelopeId;
  final Money inflows;
  final Money outflows;
  final DateTime? lastMovementAt;

  Money get balance => inflows - outflows;

  static EnvelopeBalance fromMovements({
    required String householdId,
    required String envelopeId,
    required Iterable<EnvelopeMovement> movements,
  }) {
    var inflows = const Money.fromMinorUnits(0);
    var outflows = const Money.fromMinorUnits(0);
    DateTime? lastMovementAt;
    for (final movement in movements) {
      if (movement.householdId != householdId ||
          movement.envelopeId != envelopeId) {
        continue;
      }
      if (movement.direction == EnvelopeMovementDirection.inflow) {
        inflows += movement.amount;
      } else {
        outflows += movement.amount;
      }
      if (lastMovementAt == null ||
          movement.occurredAt.isAfter(lastMovementAt)) {
        lastMovementAt = movement.occurredAt;
      }
    }
    return EnvelopeBalance(
      householdId: householdId,
      envelopeId: envelopeId,
      inflows: inflows,
      outflows: outflows,
      lastMovementAt: lastMovementAt,
    );
  }
}

/// Pure domain checks mirroring the atomic SQL group invariants. SQL remains
/// the authoritative enforcement point; these checks make the same failures
/// explicit before a future RPC call.
abstract final class EnvelopeMovementGroupValidator {
  static String? validateTransfer(Iterable<EnvelopeMovement> movements) {
    final entries = List<EnvelopeMovement>.unmodifiable(movements);
    if (entries.length != 2) {
      return 'Un transfert doit contenir exactement deux mouvements.';
    }
    if (!_hasOneHouseholdAndGroup(entries)) {
      return 'Les mouvements doivent appartenir au même foyer et au même groupe.';
    }
    final outgoing = entries
        .where((entry) => entry.type == EnvelopeMovementType.transferOut)
        .toList(growable: false);
    final incoming = entries
        .where((entry) => entry.type == EnvelopeMovementType.transferIn)
        .toList(growable: false);
    if (outgoing.length != 1 || incoming.length != 1) {
      return 'Un transfert exige un mouvement sortant et un mouvement entrant.';
    }
    if (outgoing.single.amount != incoming.single.amount) {
      return 'Les deux mouvements du transfert doivent avoir le même montant.';
    }
    if (outgoing.single.envelopeId == incoming.single.envelopeId) {
      return 'Les enveloppes source et destination doivent être différentes.';
    }
    if (entries.any((entry) => entry.financialTransactionId != null)) {
      return 'Un transfert entre enveloppes ne lie aucune transaction financière.';
    }
    return null;
  }

  static String? validateExpenseSplit({
    required Iterable<EnvelopeMovement> movements,
    required Money expenseAmount,
  }) {
    final entries = List<EnvelopeMovement>.unmodifiable(movements);
    if (entries.isEmpty) {
      return 'Une dépense doit être affectée à au moins une enveloppe.';
    }
    if (!_hasOneHouseholdAndGroup(entries) ||
        entries.any(
          (entry) =>
              entry.type != EnvelopeMovementType.consumption ||
              entry.direction != EnvelopeMovementDirection.outflow ||
              entry.financialTransactionId == null,
        )) {
      return 'Les affectations de dépense doivent être des sorties liées à la même transaction.';
    }
    final transactionId = entries.first.financialTransactionId;
    if (entries.any((entry) => entry.financialTransactionId != transactionId)) {
      return 'Les affectations de dépense doivent viser une seule transaction.';
    }
    final total = entries.fold(
      const Money.fromMinorUnits(0),
      (sum, entry) => sum + entry.amount,
    );
    if (total != expenseAmount) {
      return 'Le total des enveloppes doit égaler le montant de la dépense.';
    }
    return null;
  }

  static String? validateIncomeAllocation({
    required EnvelopeMovement movement,
    required Money incomeAmount,
    required bool isToAllocateEnvelope,
  }) {
    if (movement.type != EnvelopeMovementType.allocation ||
        movement.direction != EnvelopeMovementDirection.inflow ||
        movement.financialTransactionId == null ||
        !isToAllocateEnvelope) {
      return 'Un revenu doit alimenter l’enveloppe À répartir.';
    }
    if (movement.amount != incomeAmount) {
      return 'L’allocation doit égaler le montant du revenu.';
    }
    return null;
  }

  static String? validateReversal({
    required EnvelopeMovement reversal,
    required EnvelopeMovement original,
  }) {
    if (reversal.type != EnvelopeMovementType.reversal ||
        reversal.reversalOf != original.id ||
        reversal.householdId != original.householdId ||
        reversal.amount != original.amount ||
        reversal.direction == original.direction) {
      return 'La contrepassation doit inverser exactement un mouvement du même foyer.';
    }
    return null;
  }

  static bool _hasOneHouseholdAndGroup(List<EnvelopeMovement> entries) {
    final first = entries.first;
    return entries.every(
      (entry) =>
          entry.householdId == first.householdId &&
          entry.movementGroupId == first.movementGroupId,
    );
  }
}

class EnvelopeTransferDraft {
  const EnvelopeTransferDraft({
    required this.householdId,
    required this.sourceEnvelopeId,
    required this.destinationEnvelopeId,
    required this.amount,
    required this.occurredAt,
    required this.description,
  });

  final String householdId;
  final String sourceEnvelopeId;
  final String destinationEnvelopeId;
  final Money amount;
  final DateTime occurredAt;
  final String description;

  String? validate() {
    if (householdId.isEmpty) {
      return 'Le foyer est obligatoire.';
    }
    if (sourceEnvelopeId.isEmpty || destinationEnvelopeId.isEmpty) {
      return 'Choisissez les deux enveloppes.';
    }
    if (sourceEnvelopeId == destinationEnvelopeId) {
      return 'Les enveloppes source et destination doivent être différentes.';
    }
    if (amount.minorUnits <= 0) {
      return 'Le montant doit être strictement positif.';
    }
    if (description.trim().isEmpty) {
      return 'Le motif est obligatoire.';
    }
    return null;
  }
}
