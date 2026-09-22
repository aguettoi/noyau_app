import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/savings_goals/domain/savings_goal.dart';

SavingsGoal _goal({
  Money? target,
  Money? monthly,
  DateTime? date,
  SavingsGoalStatus status = SavingsGoalStatus.active,
}) => SavingsGoal(
  id: 'goal-1',
  householdId: 'household-1',
  name: 'Voiture',
  type: SavingsGoalType.car,
  targetAmount: target ?? Money.fromDirhams(100000),
  priority: 1,
  status: status,
  fundingEnvelopeId: 'envelope-car',
  createdBy: 'actor-1',
  createdAt: DateTime.utc(2026, 9, 1),
  updatedAt: DateTime.utc(2026, 9, 1),
  monthlyTarget: monthly,
  targetDate: date,
);

void main() {
  test('une enveloppe vide affiche une progression financière à 0 %', () {
    final progress = SavingsGoalProgress(
      goal: _goal(),
      envelopeName: 'Voiture',
      accumulated: Money.fromDirhams(0),
    );

    expect(progress.progressRatio, 0);
    expect(progress.remaining, Money.fromDirhams(100000));
    expect(progress.isFinancialTargetReached, isFalse);
  });

  test(
    'la progression provient du solde d’enveloppe sans solde objectif mutable',
    () {
      final progress = SavingsGoalProgress(
        goal: _goal(),
        envelopeName: 'Voiture',
        accumulated: Money.fromDirhams(40000),
      );

      expect(progress.accumulated, Money.fromDirhams(40000));
      expect(progress.remaining, Money.fromDirhams(60000));
      expect(progress.progressRatio, .4);
      expect(progress.isFinancialTargetReached, isFalse);
    },
  );

  test('100 % atteint ne clôture jamais automatiquement l’objectif', () {
    final progress = SavingsGoalProgress(
      goal: _goal(status: SavingsGoalStatus.active),
      envelopeName: 'Voiture',
      accumulated: Money.fromDirhams(100000),
    );

    expect(progress.isFinancialTargetReached, isTrue);
    expect(progress.goal.status, SavingsGoalStatus.active);
    expect(progress.remaining, Money.fromDirhams(0));
  });

  test('une progression supérieure à 100 % conserve le surplus réel', () {
    final progress = SavingsGoalProgress(
      goal: _goal(),
      envelopeName: 'Voiture',
      accumulated: Money.fromDirhams(125000),
    );

    expect(progress.progressRatio, 1.25);
    expect(progress.progressForIndicator, 1);
    expect(progress.remaining, Money.fromDirhams(0));
  });

  test('les projections sont absentes sans cible mensuelle', () {
    final progress = SavingsGoalProgress(
      goal: _goal(),
      envelopeName: 'Voiture',
      accumulated: Money.fromDirhams(1000),
    );

    expect(progress.estimatedMonths, isNull);
    expect(progress.estimatedCompletionDate(DateTime(2026, 10, 1)), isNull);
  });

  test(
    'la cible mensuelle et l’échéance produisent des projections non financières',
    () {
      final progress = SavingsGoalProgress(
        goal: _goal(
          monthly: Money.fromDirhams(10000),
          date: DateTime(2027, 7, 1),
        ),
        envelopeName: 'Voiture',
        accumulated: Money.fromDirhams(40000),
      );

      expect(progress.estimatedMonths, 6);
      expect(
        progress.estimatedCompletionDate(DateTime(2026, 10, 1)),
        DateTime(2027, 4, 1),
      );
      expect(
        progress.requiredMonthlyPace(DateTime(2026, 10, 1)),
        Money.fromDirhams(6666.67),
      );
    },
  );
}
