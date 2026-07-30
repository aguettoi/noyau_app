import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/domain/envelope_reporting.dart';

void main() {
  const calculator = EnvelopeReportCalculator();

  final movements = <EnvelopeMovement>[
    EnvelopeMovement(
      envelopeId: 'nourriture',
      occurredAt: DateTime(2026, 4, 2),
      amount: Money.fromDirhams(3000),
    ),
    EnvelopeMovement(
      envelopeId: 'nourriture',
      occurredAt: DateTime(2026, 4, 8),
      amount: Money.fromDirhams(-450.25),
    ),
    EnvelopeMovement(
      envelopeId: 'nourriture',
      occurredAt: DateTime(2026, 5, 1),
      amount: Money.fromDirhams(1500),
    ),
    EnvelopeMovement(
      envelopeId: 'wifi',
      occurredAt: DateTime(2026, 4, 4),
      amount: Money.fromDirhams(350),
    ),
  ];

  test('calcule le reste d’une enveloppe à partir de mouvements signés', () {
    final balances = calculator.balancesByEnvelope(movements);

    expect(balances['nourriture'], Money.fromDirhams(4049.75));
    expect(balances['wifi'], Money.fromDirhams(350));
    expect(
      calculator.totalEnvelopeFunds(movements),
      Money.fromDirhams(4399.75),
    );
  });

  test(
    'calcule les mouvements mensuels nets sans les confondre avec le solde',
    () {
      final monthly = calculator.monthlyNetForEnvelope(movements, 'nourriture');

      expect(monthly[DateTime(2026, 4)], Money.fromDirhams(2549.75));
      expect(monthly[DateTime(2026, 5)], Money.fromDirhams(1500));
    },
  );

  test('rapproche le solde théorique et le solde réellement constaté', () {
    final reconciliation = AccountReconciliation(
      accountId: 'cih-ibrahim',
      theoreticalBalance: Money.fromDirhams(1280),
      actualBalance: Money.fromDirhams(1250),
    );

    expect(reconciliation.difference, Money.fromDirhams(30));
    expect(reconciliation.isReconciled, isFalse);
  });

  test('protège l’épargne à garder sans mélanger une somme à récupérer', () {
    final reserve = EnvelopeSavingsReserve(
      savingsBalance: Money.fromDirhams(10245),
      protectedAmount: Money.fromDirhams(8000),
      recoverableAmount: Money.fromDirhams(449),
    );

    expect(reserve.spendableSavings, Money.fromDirhams(2245));
    expect(reserve.recoverableAmount, Money.fromDirhams(449));
  });

  test('reproduit la projection voiture avec et sans emprunt familial', () {
    final projection = EnvelopeGoalProjection(
      goalAmount: Money.fromDirhams(96750),
      availableCash: Money.fromDirhams(40098.30),
      familyLoan: Money.fromDirhams(40000),
      monthlyContribution: Money.fromDirhams(7500),
      baseDate: DateTime(2026, 7, 1),
    );

    expect(projection.monthsWithLoan, 2);
    expect(projection.monthsWithoutLoan, 8);
    expect(projection.estimatedDateWithLoan, DateTime(2026, 9, 1));
    expect(projection.estimatedDateWithoutLoan, DateTime(2027, 3, 1));
  });
}
