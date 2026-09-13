import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/financial_event_contract.dart';
import 'package:noyau_app/features/finance/infrastructure/financial_event_supabase_repository.dart';

void main() {
  FinancialEventSupabaseRepository repository(_Gateway gateway) =>
      FinancialEventSupabaseRepository(gateway: gateway, householdId: 'home-1');
  const allocations = [
    FinancialEventAllocation(envelopeId: 'food', amount: 60),
    FinancialEventAllocation(envelopeId: 'transport', amount: 40),
  ];

  test('create_cash_expense_event transmet le contrat exact', () async {
    final gateway = _Gateway();
    await repository(gateway).createCashExpense(
      occurredAt: DateTime.utc(2026, 8, 10, 9),
      description: ' Courses ',
      amount: Money.fromMinorUnits(10000),
      sourceAccountId: 'cash-1',
      allocations: allocations,
      idempotencyKey: '00000000-0000-4000-8000-000000000001',
      notes: ' test ',
    );
    expect(gateway.function, 'create_cash_expense_event');
    expect(gateway.parameters, {
      'p_household_id': 'home-1',
      'p_occurred_at': '2026-08-10T09:00:00.000Z',
      'p_description': 'Courses',
      'p_amount': '100.00',
      'p_source_account_id': 'cash-1',
      'p_envelope_allocations': [
        {'envelope_id': 'food', 'amount': '60.00'},
        {'envelope_id': 'transport', 'amount': '40.00'},
      ],
      'p_notes': 'test',
      'p_idempotency_key': '00000000-0000-4000-8000-000000000001',
    });
  });

  test(
    'create_cash_income_event transmet les allocations partielles',
    () async {
      final gateway = _Gateway();
      await repository(gateway).createCashIncome(
        occurredAt: DateTime.utc(2026, 9, 2, 9),
        description: ' Salaire ',
        amount: Money.fromMinorUnits(100000),
        destinationAccountId: 'received-account',
        allocations: const [
          FinancialEventAllocation(envelopeId: 'food', amount: 600),
        ],
        idempotencyKey: '00000000-0000-4000-8000-000000000011',
      );

      expect(gateway.function, 'create_cash_income_event');
      expect(gateway.parameters, {
        'p_household_id': 'home-1',
        'p_occurred_at': '2026-09-02T09:00:00.000Z',
        'p_description': 'Salaire',
        'p_amount': '1000.00',
        'p_destination_account_id': 'received-account',
        'p_envelope_allocations': [
          {'envelope_id': 'food', 'amount': '600.00'},
        ],
        'p_notes': isNull,
        'p_idempotency_key': '00000000-0000-4000-8000-000000000011',
      });
    },
  );

  test(
    'create_cash_income_event refuse les doubles et dépassements avant RPC',
    () async {
      final gateway = _Gateway();
      expect(
        () => repository(gateway).createCashIncome(
          occurredAt: DateTime.utc(2026),
          description: 'Salaire',
          amount: Money.fromMinorUnits(1000),
          destinationAccountId: 'received-account',
          allocations: const [
            FinancialEventAllocation(envelopeId: 'food', amount: 6),
            FinancialEventAllocation(envelopeId: 'food', amount: 6),
          ],
          idempotencyKey: '00000000-0000-4000-8000-000000000012',
        ),
        throwsStateError,
      );
      expect(gateway.callCount, 0);
    },
  );

  test(
    'create_debt_expense_event ne transmet aucun compte de paiement',
    () async {
      final gateway = _Gateway();
      await repository(gateway).createDebtExpense(
        occurredAt: DateTime.utc(2026, 8, 10),
        description: 'Facture',
        amount: Money.fromMinorUnits(10000),
        allocations: allocations,
        creditorName: 'Fournisseur',
        dueAt: DateTime.utc(2026, 9, 1),
        idempotencyKey: '00000000-0000-4000-8000-000000000002',
      );
      expect(gateway.function, 'create_debt_expense_event');
      expect(gateway.parameters!['p_source_account_id'], isNull);
      expect(gateway.parameters!['p_creditor_name'], 'Fournisseur');
      expect(gateway.parameters!['p_due_at'], '2026-09-01');
    },
  );

  test('settle_debt_event transmet le contrat exact', () async {
    final gateway = _Gateway();
    await repository(gateway).settleDebt(
      obligationId: 'debt-1',
      occurredAt: DateTime.utc(2026, 8, 10),
      description: 'Règlement',
      amount: Money.fromMinorUnits(2500),
      remaining: Money.fromMinorUnits(5000),
      sourceAccountId: 'cash-1',
      idempotencyKey: '00000000-0000-4000-8000-000000000003',
    );
    expect(gateway.function, 'settle_debt_event');
    expect(gateway.parameters!['p_obligation_id'], 'debt-1');
    expect(gateway.parameters!['p_amount'], '25.00');
    expect(gateway.parameters!.containsKey('p_envelope_allocations'), isFalse);
  });

  test(
    'reverse_debt_settlement_event transmet une contre-opération motivée',
    () async {
      final gateway = _Gateway();
      await repository(gateway).reverseDebtSettlement(
        sourceSettlementId: 'settlement-1',
        occurredAt: DateTime.utc(2026, 9, 9, 10),
        amount: Money.fromMinorUnits(2000),
        reason: 'Erreur de montant',
        notes: 'Correction',
        idempotencyKey: '00000000-0000-4000-8000-000000000030',
      );
      expect(gateway.function, 'reverse_debt_settlement_event');
      expect(gateway.parameters, {
        'p_household_id': 'home-1',
        'p_source_settlement_id': 'settlement-1',
        'p_occurred_at': '2026-09-09T10:00:00.000Z',
        'p_amount': '20.00',
        'p_reason': 'Erreur de montant',
        'p_notes': 'Correction',
        'p_idempotency_key': '00000000-0000-4000-8000-000000000030',
      });
    },
  );

  test(
    'reverse_income_receivable_settlement exige la ventilation source',
    () async {
      final gateway = _Gateway();
      await repository(gateway).reverseIncomeReceivableSettlement(
        sourceSettlementId: 'settlement-2',
        occurredAt: DateTime.utc(2026, 9, 9),
        amount: Money.fromMinorUnits(2000),
        reason: 'Doublon',
        envelopeReversals: const [
          FinancialEventAllocation(
            envelopeId: 'source-movement-food',
            amount: 10,
          ),
          FinancialEventAllocation(
            envelopeId: 'source-movement-to-allocate',
            amount: 10,
          ),
        ],
        idempotencyKey: '00000000-0000-4000-8000-000000000031',
      );
      expect(gateway.function, 'reverse_income_receivable_settlement_event');
      expect(gateway.parameters!['p_envelope_reversals'], [
        {'source_movement_id': 'source-movement-food', 'amount': '10.00'},
        {
          'source_movement_id': 'source-movement-to-allocate',
          'amount': '10.00',
        },
      ]);
    },
  );

  test(
    'reverse_recovery_settlement contre-passe sans allocation arbitraire',
    () async {
      final gateway = _Gateway();
      await repository(gateway).reverseRecoverySettlement(
        sourceSettlementId: 'settlement-3',
        occurredAt: DateTime.utc(2026, 9, 9),
        amount: Money.fromMinorUnits(1000),
        reason: 'Saisie erronée',
        idempotencyKey: '00000000-0000-4000-8000-000000000032',
      );
      expect(gateway.function, 'reverse_recovery_settlement_event');
      expect(gateway.parameters!.containsKey('p_envelope_reversals'), isFalse);
    },
  );

  test(
    'settle_receivable_event transmet les allocations facultatives',
    () async {
      final gateway = _Gateway();
      await repository(gateway).settleIncomeReceivable(
        obligationId: 'receivable-1',
        occurredAt: DateTime.utc(2026, 9, 6, 10),
        description: 'Encaissement prestation',
        amount: Money.fromMinorUnits(7500),
        remaining: Money.fromMinorUnits(12000),
        destinationAccountId: 'testoj',
        allocations: const [
          FinancialEventAllocation(envelopeId: 'food', amount: 30),
          FinancialEventAllocation(envelopeId: 'savings', amount: 20),
        ],
        idempotencyKey: '00000000-0000-0000-0000-000000000016',
      );

      expect(gateway.function, 'settle_receivable_event');
      expect(gateway.parameters!['p_amount'], '75.00');
      expect(gateway.parameters!['p_envelope_allocations'], [
        {'envelope_id': 'food', 'amount': '30.00'},
        {'envelope_id': 'savings', 'amount': '20.00'},
      ]);
    },
  );

  test(
    'settle_recovery_event demande toujours la restitution source',
    () async {
      final gateway = _Gateway();
      await repository(gateway).settleRecoveryReceivable(
        obligationId: 'recovery-1',
        occurredAt: DateTime.utc(2026, 9, 7),
        description: 'Remboursement courses',
        amount: Money.fromMinorUnits(6000),
        remaining: Money.fromMinorUnits(6000),
        destinationAccountId: 'testoj',
        idempotencyKey: '00000000-0000-0000-0000-000000000018',
      );

      expect(gateway.function, 'settle_recovery_event');
      expect(gateway.parameters!['p_refund_source_envelope'], isTrue);
    },
  );

  test(
    'les abandons appellent les RPC canoniques sans compte financier',
    () async {
      final gateway = _Gateway();
      final subject = repository(gateway);
      await subject.writeOffDebt(
        obligationId: 'debt-1',
        occurredAt: DateTime.utc(2026, 9, 7),
        amount: Money.fromMinorUnits(2500),
        remaining: Money.fromMinorUnits(5000),
        reason: 'Insolvabilité confirmée',
        idempotencyKey: '00000000-0000-0000-0000-000000000019',
      );
      expect(gateway.function, 'writeoff_debt_event');
      expect(gateway.parameters!['p_amount'], '25.00');
      expect(gateway.parameters!.containsKey('p_source_account_id'), isFalse);
      await subject.writeOffIncomeReceivable(
        obligationId: 'income-1',
        occurredAt: DateTime.utc(2026, 9, 7),
        amount: Money.fromMinorUnits(2500),
        remaining: Money.fromMinorUnits(5000),
        reason: 'Insolvabilité confirmée',
        idempotencyKey: '00000000-0000-0000-0000-000000000020',
      );
      expect(gateway.function, 'writeoff_income_receivable_event');
      await subject.writeOffRecovery(
        obligationId: 'recovery-1',
        occurredAt: DateTime.utc(2026, 9, 7),
        amount: Money.fromMinorUnits(2500),
        remaining: Money.fromMinorUnits(5000),
        reason: 'Insolvabilité confirmée',
        idempotencyKey: '00000000-0000-0000-0000-000000000021',
      );
      expect(gateway.function, 'writeoff_recovery_event');
    },
  );

  test(
    'les annulations d’abandon appellent les trois RPC Phase 2A avec la source exacte',
    () async {
      final gateway = _Gateway();
      final subject = repository(gateway);
      final occurredAt = DateTime.utc(2026, 9, 13, 9, 42);

      await subject.reverseDebtWriteoff(
        sourceAdjustmentId: 'debt-writeoff-1',
        occurredAt: occurredAt,
        amount: Money.fromMinorUnits(2000),
        reason: 'Erreur de montant',
        notes: 'Première correction',
        idempotencyKey: '00000000-0000-4000-8000-000000000041',
      );
      expect(gateway.function, 'reverse_debt_writeoff_event');
      expect(gateway.parameters, {
        'p_household_id': 'home-1',
        'p_source_adjustment_id': 'debt-writeoff-1',
        'p_occurred_at': '2026-09-13T09:42:00.000Z',
        'p_amount': '20.00',
        'p_reason': 'Erreur de montant',
        'p_notes': 'Première correction',
        'p_idempotency_key': '00000000-0000-4000-8000-000000000041',
      });

      await subject.reverseIncomeReceivableWriteoff(
        sourceAdjustmentId: 'income-writeoff-1',
        occurredAt: occurredAt,
        amount: Money.fromMinorUnits(1000),
        reason: 'Erreur de saisie',
        idempotencyKey: '00000000-0000-4000-8000-000000000042',
      );
      expect(gateway.function, 'reverse_income_receivable_writeoff_event');
      expect(
        gateway.parameters!['p_source_adjustment_id'],
        'income-writeoff-1',
      );

      await subject.reverseRecoveryWriteoff(
        sourceAdjustmentId: 'recovery-writeoff-1',
        occurredAt: occurredAt,
        amount: Money.fromMinorUnits(500),
        reason: 'Justificatif rétabli',
        idempotencyKey: '00000000-0000-4000-8000-000000000043',
      );
      expect(gateway.function, 'reverse_recovery_writeoff_event');
      expect(
        gateway.parameters!['p_source_adjustment_id'],
        'recovery-writeoff-1',
      );
    },
  );

  test('une annulation d’abandon invalide ne déclenche aucune RPC', () {
    final gateway = _Gateway();
    expect(
      () => repository(gateway).reverseDebtWriteoff(
        sourceAdjustmentId: '',
        occurredAt: DateTime.utc(2026, 9, 13),
        amount: Money.fromMinorUnits(0),
        reason: '',
        idempotencyKey: '00000000-0000-4000-8000-000000000044',
      ),
      throwsStateError,
    );
    expect(gateway.callCount, 0);
  });

  test('settle_receivable_event bloque doublon et dépassement avant RPC', () {
    final gateway = _Gateway();
    expect(
      () => repository(gateway).settleIncomeReceivable(
        obligationId: 'receivable-1',
        occurredAt: DateTime.utc(2026, 9, 6),
        description: 'Encaissement prestation',
        amount: Money.fromMinorUnits(7500),
        remaining: Money.fromMinorUnits(7500),
        destinationAccountId: 'testoj',
        allocations: const [
          FinancialEventAllocation(envelopeId: 'food', amount: 40),
          FinancialEventAllocation(envelopeId: 'food', amount: 40),
        ],
        idempotencyKey: '00000000-0000-0000-0000-000000000017',
      ),
      throwsStateError,
    );
    expect(gateway.callCount, 0);
  });

  test(
    'create_income_receivable_event transmet le contrat canonique',
    () async {
      final gateway = _Gateway();
      await repository(gateway).createIncomeReceivable(
        occurredAt: DateTime.utc(2026, 9, 3),
        description: ' Prestation ',
        amount: Money.fromMinorUnits(12000),
        debtorName: ' Client ',
        dueAt: DateTime.utc(2026, 9, 30),
        notes: ' note ',
        idempotencyKey: '00000000-0000-4000-8000-000000000013',
      );
      expect(gateway.function, 'create_income_receivable_event');
      expect(gateway.parameters, {
        'p_household_id': 'home-1',
        'p_occurred_at': '2026-09-03T00:00:00.000Z',
        'p_description': 'Prestation',
        'p_amount': '120.00',
        'p_debtor_name': 'Client',
        'p_due_at': '2026-09-30',
        'p_notes': 'note',
        'p_idempotency_key': '00000000-0000-4000-8000-000000000013',
      });
    },
  );

  test('create_recovery_receivable_event contrôle le plafond source', () async {
    final gateway = _Gateway();
    await repository(gateway).createRecoveryReceivable(
      sourceEventId: 'expense-event',
      sourceEnvelopeId: 'food',
      occurredAt: DateTime.utc(2026, 9, 3),
      description: 'Remboursement courses',
      amount: Money.fromMinorUnits(6000),
      maximumAmount: Money.fromMinorUnits(6000),
      debtorName: 'Alex',
      idempotencyKey: '00000000-0000-4000-8000-000000000014',
    );
    expect(gateway.function, 'create_recovery_receivable_event');
    expect(gateway.parameters!['p_source_event_id'], 'expense-event');
    expect(gateway.parameters!['p_source_envelope_id'], 'food');
    expect(gateway.parameters!['p_amount'], '60.00');

    expect(
      () => repository(_Gateway()).createRecoveryReceivable(
        sourceEventId: 'expense-event',
        sourceEnvelopeId: 'food',
        occurredAt: DateTime.utc(2026, 9, 3),
        description: 'Remboursement courses',
        amount: Money.fromMinorUnits(6001),
        maximumAmount: Money.fromMinorUnits(6000),
        debtorName: 'Alex',
        idempotencyKey: '00000000-0000-4000-8000-000000000015',
      ),
      throwsStateError,
    );
  });

  test('propage une erreur distante', () async {
    final gateway = _Gateway(error: Exception('network'));
    await expectLater(
      repository(gateway).createCashExpense(
        occurredAt: DateTime.utc(2026),
        description: 'Courses',
        amount: Money.fromMinorUnits(100),
        sourceAccountId: 'cash-1',
        allocations: const [
          FinancialEventAllocation(envelopeId: 'food', amount: 1),
        ],
        idempotencyKey: '00000000-0000-4000-8000-000000000004',
      ),
      throwsException,
    );
  });
}

class _Gateway implements FinancialEventSupabaseGateway {
  _Gateway({this.error});
  final Object? error;
  String? function;
  Map<String, Object?>? parameters;
  var callCount = 0;
  @override
  Future<Object?> call(String function, Map<String, Object?> parameters) async {
    callCount++;
    this.function = function;
    this.parameters = Map<String, Object?>.from(parameters);
    if (error != null) throw error!;
    return '00000000-0000-4000-8000-000000000010';
  }
}
