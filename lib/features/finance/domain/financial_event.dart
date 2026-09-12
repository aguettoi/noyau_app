enum FinancialEventType {
  cashExpense,
  income,
  accountTransfer,
  accountAdjustment,
  budgetAllocation,
  payableCreated,
  payableSettlement,
  receivableIncomeCreated,
  receivableRecoveryCreated,
  receivableSettlement,
}

/// Immutable user intent. Its financial and budget consequences belong to
/// separate append-only ledgers.
class FinancialEvent {
  const FinancialEvent({
    required this.id,
    required this.householdId,
    required this.type,
    required this.description,
    required this.occurredAt,
    this.notes,
  });

  final String id;
  final String householdId;
  final FinancialEventType type;
  final String description;
  final DateTime occurredAt;
  final String? notes;
}
