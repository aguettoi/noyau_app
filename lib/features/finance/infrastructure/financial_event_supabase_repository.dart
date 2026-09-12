import '../../../core/money/money.dart';
import '../application/financial_event_contract.dart';

abstract interface class FinancialEventSupabaseGateway {
  Future<Object?> call(String function, Map<String, Object?> parameters);
}

class FinancialEventSupabaseRepository {
  const FinancialEventSupabaseRepository({
    required this.gateway,
    required this.householdId,
  });

  final FinancialEventSupabaseGateway gateway;
  final String householdId;

  Future<String> createCashExpense({
    required DateTime occurredAt,
    required String description,
    required Money amount,
    required String sourceAccountId,
    required List<FinancialEventAllocation> allocations,
    required String idempotencyKey,
    String? notes,
  }) {
    FinancialEventContract.validateEnvelopeSplit(
      totalAmount: amount.dirhams,
      allocations: allocations,
    );
    if (sourceAccountId.trim().isEmpty) {
      return Future.error(StateError('Un compte de paiement est requis.'));
    }
    return _call('create_cash_expense_event', {
      'p_household_id': householdId,
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_description': description.trim(),
      'p_amount': _mad(amount),
      'p_source_account_id': sourceAccountId,
      'p_envelope_allocations': _allocations(allocations),
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<String> createCashIncome({
    required DateTime occurredAt,
    required String description,
    required Money amount,
    required String destinationAccountId,
    required List<FinancialEventAllocation> allocations,
    required String idempotencyKey,
    String? notes,
  }) {
    FinancialEventContract.validateIncomeEnvelopeAllocations(
      totalAmount: amount.dirhams,
      allocations: allocations,
    );
    if (destinationAccountId.trim().isEmpty) {
      return Future.error(StateError('Un compte encaissé est requis.'));
    }
    return _call('create_cash_income_event', {
      'p_household_id': householdId,
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_description': description.trim(),
      'p_amount': _mad(amount),
      'p_destination_account_id': destinationAccountId,
      'p_envelope_allocations': _allocations(allocations),
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<String> createDebtExpense({
    required DateTime occurredAt,
    required String description,
    required Money amount,
    required List<FinancialEventAllocation> allocations,
    required String idempotencyKey,
    String? creditorName,
    DateTime? dueAt,
    String? notes,
  }) {
    FinancialEventContract.validateEnvelopeSplit(
      totalAmount: amount.dirhams,
      allocations: allocations,
    );
    return _call('create_debt_expense_event', {
      'p_household_id': householdId,
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_description': description.trim(),
      'p_amount': _mad(amount),
      'p_envelope_allocations': _allocations(allocations),
      'p_creditor_name': _nullable(creditorName),
      'p_due_at': dueAt == null ? null : _date(dueAt),
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<String> settleDebt({
    required String obligationId,
    required DateTime occurredAt,
    required String description,
    required Money amount,
    required Money remaining,
    required String sourceAccountId,
    required String idempotencyKey,
    String? notes,
  }) {
    FinancialEventContract.remainingAfterSettlement(
      initialAmount: remaining.dirhams,
      settledAmount: 0,
      settlementAmount: amount.dirhams,
    );
    if (obligationId.trim().isEmpty || sourceAccountId.trim().isEmpty) {
      return Future.error(StateError('Une dette et un compte sont requis.'));
    }
    return _call('settle_debt_event', {
      'p_household_id': householdId,
      'p_obligation_id': obligationId,
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_description': description.trim(),
      'p_amount': _mad(amount),
      'p_source_account_id': sourceAccountId,
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<String> reverseDebtSettlement({
    required String sourceSettlementId,
    required DateTime occurredAt,
    required Money amount,
    required String reason,
    required String idempotencyKey,
    String? notes,
  }) => _reverseSettlement(
    function: 'reverse_debt_settlement_event',
    sourceSettlementId: sourceSettlementId,
    occurredAt: occurredAt,
    amount: amount,
    reason: reason,
    idempotencyKey: idempotencyKey,
    notes: notes,
  );

  Future<String> reverseIncomeReceivableSettlement({
    required String sourceSettlementId,
    required DateTime occurredAt,
    required Money amount,
    required String reason,
    required List<FinancialEventAllocation> envelopeReversals,
    required String idempotencyKey,
    String? notes,
  }) {
    FinancialEventContract.validateIncomeEnvelopeAllocations(
      totalAmount: amount.dirhams,
      allocations: envelopeReversals,
    );
    return _reverseSettlement(
      function: 'reverse_income_receivable_settlement_event',
      sourceSettlementId: sourceSettlementId,
      occurredAt: occurredAt,
      amount: amount,
      reason: reason,
      idempotencyKey: idempotencyKey,
      notes: notes,
      envelopeReversals: envelopeReversals,
    );
  }

  Future<String> reverseRecoverySettlement({
    required String sourceSettlementId,
    required DateTime occurredAt,
    required Money amount,
    required String reason,
    required String idempotencyKey,
    String? notes,
  }) => _reverseSettlement(
    function: 'reverse_recovery_settlement_event',
    sourceSettlementId: sourceSettlementId,
    occurredAt: occurredAt,
    amount: amount,
    reason: reason,
    idempotencyKey: idempotencyKey,
    notes: notes,
  );

  Future<String> _reverseSettlement({
    required String function,
    required String sourceSettlementId,
    required DateTime occurredAt,
    required Money amount,
    required String reason,
    required String idempotencyKey,
    required String? notes,
    List<FinancialEventAllocation>? envelopeReversals,
  }) {
    FinancialEventContract.validatePositiveAmount(amount.dirhams);
    if (sourceSettlementId.trim().isEmpty || reason.trim().isEmpty) {
      return Future.error(
        StateError('Le règlement d’origine et un motif sont requis.'),
      );
    }
    final parameters = <String, Object?>{
      'p_household_id': householdId,
      'p_source_settlement_id': sourceSettlementId,
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_amount': _mad(amount),
      'p_reason': reason.trim(),
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    };
    if (envelopeReversals != null) {
      parameters['p_envelope_reversals'] = envelopeReversals
          .map(
            (allocation) => <String, Object?>{
              'source_movement_id': allocation.envelopeId,
              'amount': _mad(Money.fromDirhams(allocation.amount)),
            },
          )
          .toList(growable: false);
    }
    return _call(function, parameters);
  }

  Future<String> writeOffDebt({
    required String obligationId,
    required DateTime occurredAt,
    required Money amount,
    required Money remaining,
    required String reason,
    required String idempotencyKey,
    String? notes,
  }) => _writeOff(
    function: 'writeoff_debt_event',
    obligationId: obligationId,
    occurredAt: occurredAt,
    amount: amount,
    remaining: remaining,
    reason: reason,
    idempotencyKey: idempotencyKey,
    notes: notes,
  );

  Future<String> writeOffIncomeReceivable({
    required String obligationId,
    required DateTime occurredAt,
    required Money amount,
    required Money remaining,
    required String reason,
    required String idempotencyKey,
    String? notes,
  }) => _writeOff(
    function: 'writeoff_income_receivable_event',
    obligationId: obligationId,
    occurredAt: occurredAt,
    amount: amount,
    remaining: remaining,
    reason: reason,
    idempotencyKey: idempotencyKey,
    notes: notes,
  );

  Future<String> writeOffRecovery({
    required String obligationId,
    required DateTime occurredAt,
    required Money amount,
    required Money remaining,
    required String reason,
    required String idempotencyKey,
    String? notes,
  }) => _writeOff(
    function: 'writeoff_recovery_event',
    obligationId: obligationId,
    occurredAt: occurredAt,
    amount: amount,
    remaining: remaining,
    reason: reason,
    idempotencyKey: idempotencyKey,
    notes: notes,
  );

  Future<String> _writeOff({
    required String function,
    required String obligationId,
    required DateTime occurredAt,
    required Money amount,
    required Money remaining,
    required String reason,
    required String idempotencyKey,
    required String? notes,
  }) {
    FinancialEventContract.remainingAfterSettlement(
      initialAmount: remaining.dirhams,
      settledAmount: 0,
      settlementAmount: amount.dirhams,
    );
    if (obligationId.trim().isEmpty || reason.trim().isEmpty) {
      return Future.error(
        StateError('Une obligation et un motif sont requis.'),
      );
    }
    return _call(function, {
      'p_household_id': householdId,
      'p_obligation_id': obligationId,
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_amount': _mad(amount),
      'p_reason': reason.trim(),
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<String> createIncomeReceivable({
    required DateTime occurredAt,
    required String description,
    required Money amount,
    required String debtorName,
    required String idempotencyKey,
    DateTime? dueAt,
    String? notes,
  }) {
    FinancialEventContract.validatePositiveAmount(amount.dirhams);
    if (debtorName.trim().isEmpty) {
      return Future.error(StateError('Un débiteur est requis.'));
    }
    return _call('create_income_receivable_event', {
      'p_household_id': householdId,
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_description': description.trim(),
      'p_amount': _mad(amount),
      'p_debtor_name': debtorName.trim(),
      'p_due_at': dueAt == null ? null : _date(dueAt),
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<String> createRecoveryReceivable({
    required String sourceEventId,
    required String? sourceEnvelopeId,
    required DateTime occurredAt,
    required String description,
    required Money amount,
    required Money maximumAmount,
    required String debtorName,
    required String idempotencyKey,
    DateTime? dueAt,
    String? notes,
  }) {
    FinancialEventContract.validatePositiveAmount(amount.dirhams);
    if (sourceEventId.trim().isEmpty || debtorName.trim().isEmpty) {
      return Future.error(
        StateError('Une dépense source et un débiteur sont requis.'),
      );
    }
    if (amount.minorUnits > maximumAmount.minorUnits) {
      return Future.error(
        StateError('Le montant dépasse le maximum récupérable.'),
      );
    }
    return _call('create_recovery_receivable_event', {
      'p_household_id': householdId,
      'p_source_event_id': sourceEventId,
      'p_source_envelope_id': _nullable(sourceEnvelopeId),
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_description': description.trim(),
      'p_amount': _mad(amount),
      'p_debtor_name': debtorName.trim(),
      'p_due_at': dueAt == null ? null : _date(dueAt),
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<String> settleIncomeReceivable({
    required String obligationId,
    required DateTime occurredAt,
    required String description,
    required Money amount,
    required Money remaining,
    required String destinationAccountId,
    required String idempotencyKey,
    List<FinancialEventAllocation> allocations = const [],
    String? notes,
  }) {
    FinancialEventContract.validateIncomeEnvelopeAllocations(
      totalAmount: amount.dirhams,
      allocations: allocations,
    );
    return _settleReceivable(
      function: 'settle_receivable_event',
      obligationId: obligationId,
      occurredAt: occurredAt,
      description: description,
      amount: amount,
      remaining: remaining,
      destinationAccountId: destinationAccountId,
      idempotencyKey: idempotencyKey,
      notes: notes,
      envelopeAllocations: allocations,
    );
  }

  Future<String> settleRecoveryReceivable({
    required String obligationId,
    required DateTime occurredAt,
    required String description,
    required Money amount,
    required Money remaining,
    required String destinationAccountId,
    required String idempotencyKey,
    String? notes,
  }) => _settleReceivable(
    function: 'settle_recovery_event',
    obligationId: obligationId,
    occurredAt: occurredAt,
    description: description,
    amount: amount,
    remaining: remaining,
    destinationAccountId: destinationAccountId,
    idempotencyKey: idempotencyKey,
    notes: notes,
    // Le serveur impose également cette restitution. La valeur explicite rend
    // le contrat client lisible tout en conservant la compatibilité RPC.
    refundSourceEnvelope: true,
  );

  Future<String> _settleReceivable({
    required String function,
    required String obligationId,
    required DateTime occurredAt,
    required String description,
    required Money amount,
    required Money remaining,
    required String destinationAccountId,
    required String idempotencyKey,
    required String? notes,
    bool? refundSourceEnvelope,
    List<FinancialEventAllocation>? envelopeAllocations,
  }) {
    FinancialEventContract.remainingAfterSettlement(
      initialAmount: remaining.dirhams,
      settledAmount: 0,
      settlementAmount: amount.dirhams,
    );
    if (obligationId.trim().isEmpty || destinationAccountId.trim().isEmpty) {
      return Future.error(StateError('Une créance et un compte sont requis.'));
    }
    final parameters = <String, Object?>{
      'p_household_id': householdId,
      'p_obligation_id': obligationId,
      'p_occurred_at': occurredAt.toUtc().toIso8601String(),
      'p_description': description.trim(),
      'p_amount': _mad(amount),
      'p_destination_account_id': destinationAccountId,
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    };
    if (refundSourceEnvelope != null) {
      parameters['p_refund_source_envelope'] = refundSourceEnvelope;
    }
    if (envelopeAllocations != null) {
      parameters['p_envelope_allocations'] = _allocations(envelopeAllocations);
    }
    return _call(function, parameters);
  }

  Future<String> _call(String function, Map<String, Object?> parameters) async {
    final value = await gateway.call(function, parameters);
    if (value is! String || value.isEmpty) {
      throw StateError(
        'L’opération financière n’a retourné aucun identifiant.',
      );
    }
    return value;
  }

  static List<Map<String, String>> _allocations(
    Iterable<FinancialEventAllocation> allocations,
  ) => [
    for (final allocation in allocations)
      {
        'envelope_id': allocation.envelopeId,
        'amount': allocation.amount.toStringAsFixed(2),
      },
  ];
  static String _mad(Money amount) => amount.dirhams.toStringAsFixed(2);
  static String? _nullable(String? value) =>
      value?.trim().isEmpty ?? true ? null : value!.trim();
  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
