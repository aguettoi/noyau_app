import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/domain/envelope_ledger.dart';

void main() {
  final occurredAt = DateTime.utc(2026, 8, 5);

  EnvelopeMovement movement({
    EnvelopeMovementType type = EnvelopeMovementType.allocation,
    EnvelopeMovementDirection direction = EnvelopeMovementDirection.inflow,
    Money amount = const Money.fromMinorUnits(10000),
    String householdId = 'household-1',
    String envelopeId = 'envelope-1',
    String movementGroupId = 'group-1',
    String? financialTransactionId,
    String? reversalOf,
    DateTime? movementOccurredAt,
  }) => EnvelopeMovement(
    id: 'movement-${movementOccurredAt?.millisecondsSinceEpoch ?? type.name}',
    householdId: householdId,
    envelopeId: envelopeId,
    movementGroupId: movementGroupId,
    type: type,
    direction: direction,
    amount: amount,
    occurredAt: movementOccurredAt ?? occurredAt,
    description: 'Mouvement de test',
    createdBy: 'member-1',
    createdAt: occurredAt,
    financialTransactionId: financialTransactionId,
    reversalOf: reversalOf,
  );

  test('un mouvement exige un montant strictement positif', () {
    expect(movement(amount: const Money.fromMinorUnits(0)).isValid, isFalse);
  });

  test('les combinaisons type et direction sont explicites', () {
    expect(
      EnvelopeMovement.isTypeDirectionAllowed(
        EnvelopeMovementType.consumption,
        EnvelopeMovementDirection.inflow,
      ),
      isFalse,
    );
    expect(
      EnvelopeMovement.isTypeDirectionAllowed(
        EnvelopeMovementType.transferIn,
        EnvelopeMovementDirection.inflow,
      ),
      isTrue,
    );
    expect(
      EnvelopeMovement.isTypeDirectionAllowed(
        EnvelopeMovementType.adjustment,
        EnvelopeMovementDirection.outflow,
      ),
      isTrue,
    );
  });

  test('une contrepassation exige la référence de son mouvement original', () {
    expect(
      movement(
        type: EnvelopeMovementType.reversal,
        direction: EnvelopeMovementDirection.outflow,
      ).isValid,
      isFalse,
    );
    expect(
      movement(
        type: EnvelopeMovementType.reversal,
        direction: EnvelopeMovementDirection.outflow,
        reversalOf: 'original-1',
      ).isValid,
      isTrue,
    );
  });

  test('le solde est inflows moins outflows sans double comptage', () {
    final balance = EnvelopeBalance.fromMovements(
      householdId: 'household-1',
      envelopeId: 'envelope-1',
      movements: [
        movement(amount: Money.fromDirhams(300)),
        movement(
          type: EnvelopeMovementType.consumption,
          direction: EnvelopeMovementDirection.outflow,
          amount: Money.fromDirhams(125.5),
          movementOccurredAt: occurredAt.add(const Duration(days: 1)),
        ),
        movement(householdId: 'other-household', amount: Money.fromDirhams(99)),
        movement(envelopeId: 'other-envelope', amount: Money.fromDirhams(88)),
      ],
    );

    expect(balance.inflows, Money.fromDirhams(300));
    expect(balance.outflows, Money.fromDirhams(125.5));
    expect(balance.balance, Money.fromDirhams(174.5));
    expect(balance.lastMovementAt, occurredAt.add(const Duration(days: 1)));
  });

  test('un brouillon de transfert exige deux enveloppes du même foyer', () {
    final invalidDraft = EnvelopeTransferDraft(
      householdId: 'household-1',
      sourceEnvelopeId: 'envelope-1',
      destinationEnvelopeId: 'envelope-1',
      amount: Money.fromDirhams(50),
      occurredAt: occurredAt,
      description: 'Alimentation',
    );
    final validDraft = EnvelopeTransferDraft(
      householdId: 'household-1',
      sourceEnvelopeId: 'to-allocate',
      destinationEnvelopeId: 'courses',
      amount: Money.fromDirhams(50),
      occurredAt: occurredAt,
      description: 'Alimentation',
    );

    expect(invalidDraft.validate(), contains('différentes'));
    expect(validDraft.validate(), isNull);
  });

  test('un transfert valide contient exactement une sortie et une entrée', () {
    final transfer = [
      movement(
        type: EnvelopeMovementType.transferOut,
        direction: EnvelopeMovementDirection.outflow,
        envelopeId: 'source',
      ),
      movement(
        type: EnvelopeMovementType.transferIn,
        direction: EnvelopeMovementDirection.inflow,
        envelopeId: 'destination',
      ),
    ];

    expect(EnvelopeMovementGroupValidator.validateTransfer(transfer), isNull);
  });

  test('un transfert avec une ou trois lignes est refusé', () {
    final source = movement(
      type: EnvelopeMovementType.transferOut,
      direction: EnvelopeMovementDirection.outflow,
      envelopeId: 'source',
    );
    final destination = movement(
      type: EnvelopeMovementType.transferIn,
      direction: EnvelopeMovementDirection.inflow,
      envelopeId: 'destination',
    );

    expect(
      EnvelopeMovementGroupValidator.validateTransfer([source]),
      contains('exactement deux'),
    );
    expect(
      EnvelopeMovementGroupValidator.validateTransfer([
        source,
        destination,
        destination,
      ]),
      contains('exactement deux'),
    );
  });

  test('un transfert déséquilibré ou vers la même enveloppe est refusé', () {
    final outgoing = movement(
      type: EnvelopeMovementType.transferOut,
      direction: EnvelopeMovementDirection.outflow,
      envelopeId: 'courses',
      amount: Money.fromDirhams(50),
    );
    final unbalancedIncoming = movement(
      type: EnvelopeMovementType.transferIn,
      direction: EnvelopeMovementDirection.inflow,
      envelopeId: 'épargne',
      amount: Money.fromDirhams(49),
    );
    final sameEnvelopeIncoming = movement(
      type: EnvelopeMovementType.transferIn,
      direction: EnvelopeMovementDirection.inflow,
      envelopeId: 'courses',
      amount: Money.fromDirhams(50),
    );

    expect(
      EnvelopeMovementGroupValidator.validateTransfer([
        outgoing,
        unbalancedIncoming,
      ]),
      contains('même montant'),
    );
    expect(
      EnvelopeMovementGroupValidator.validateTransfer([
        outgoing,
        sameEnvelopeIncoming,
      ]),
      contains('différentes'),
    );
  });

  test('un split de dépense doit égaler la dépense', () {
    final split = [
      movement(
        type: EnvelopeMovementType.consumption,
        direction: EnvelopeMovementDirection.outflow,
        amount: Money.fromDirhams(30),
        financialTransactionId: 'expense-1',
      ),
      movement(
        type: EnvelopeMovementType.consumption,
        direction: EnvelopeMovementDirection.outflow,
        amount: Money.fromDirhams(70),
        financialTransactionId: 'expense-1',
        envelopeId: 'envelope-2',
      ),
    ];

    expect(
      EnvelopeMovementGroupValidator.validateExpenseSplit(
        movements: split,
        expenseAmount: Money.fromDirhams(100),
      ),
      isNull,
    );
    expect(
      EnvelopeMovementGroupValidator.validateExpenseSplit(
        movements: split,
        expenseAmount: Money.fromDirhams(99),
      ),
      contains('égaler'),
    );
  });

  test(
    'un revenu alimente À répartir et une contrepassation inverse l’original',
    () {
      final income = movement(
        type: EnvelopeMovementType.allocation,
        direction: EnvelopeMovementDirection.inflow,
        financialTransactionId: 'income-1',
        amount: Money.fromDirhams(300),
      );
      final original = movement(
        type: EnvelopeMovementType.consumption,
        direction: EnvelopeMovementDirection.outflow,
        amount: Money.fromDirhams(100),
      );
      final reversal = movement(
        type: EnvelopeMovementType.reversal,
        direction: EnvelopeMovementDirection.inflow,
        amount: Money.fromDirhams(100),
        reversalOf: original.id,
      );

      expect(
        EnvelopeMovementGroupValidator.validateIncomeAllocation(
          movement: income,
          incomeAmount: Money.fromDirhams(300),
          isToAllocateEnvelope: true,
        ),
        isNull,
      );
      expect(
        EnvelopeMovementGroupValidator.validateIncomeAllocation(
          movement: income,
          incomeAmount: Money.fromDirhams(300),
          isToAllocateEnvelope: false,
        ),
        contains('À répartir'),
      );
      expect(
        EnvelopeMovementGroupValidator.validateReversal(
          reversal: reversal,
          original: original,
        ),
        isNull,
      );
    },
  );
}
