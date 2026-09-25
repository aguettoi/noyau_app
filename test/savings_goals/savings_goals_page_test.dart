import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/financial_availability/application/providers/financial_availability_provider.dart';
import 'package:noyau_app/features/financial_availability/domain/financial_availability.dart';
import 'package:noyau_app/features/savings_goals/application/providers/remote_savings_goals_provider.dart';
import 'package:noyau_app/features/savings_goals/domain/savings_goal.dart';
import 'package:noyau_app/features/savings_goals/presentation/savings_goals_page.dart';

SavingsGoalProgress _item({required Money accumulated}) => SavingsGoalProgress(
  goal: SavingsGoal(
    id: 'goal-1',
    householdId: 'household-1',
    name: 'Voiture familiale',
    type: SavingsGoalType.car,
    targetAmount: Money.fromDirhams(100000),
    priority: 1,
    status: SavingsGoalStatus.active,
    fundingEnvelopeId: 'envelope-car',
    createdBy: 'actor-1',
    createdAt: DateTime.utc(2026, 9, 1),
    updatedAt: DateTime.utc(2026, 9, 1),
  ),
  envelopeName: 'Voiture',
  accumulated: accumulated,
);

Widget _app(
  List<SavingsGoalProgress> items, {
  FinancialAvailabilitySnapshot? availability,
}) => ProviderScope(
  overrides: [
    savingsGoalsProvider.overrideWith((ref) async => items),
    savingsGoalHistoryProvider('goal-1').overrideWith(
      (ref) async => [
        SavingsGoalHistoryItem(
          id: 'history-1',
          action: 'created',
          actorId: 'actor-1',
          actorName: 'Ibrahim Aguettoi',
          createdAt: DateTime.utc(2026, 9, 1, 10, 42),
        ),
      ],
    ),
    if (availability != null)
      financialAvailabilityProvider.overrideWith((ref) async => availability),
  ],
  child: const MaterialApp(home: Scaffold(body: SavingsGoalsPage())),
);

Widget _detailApp(List<SavingsGoalProgress> items) => ProviderScope(
  overrides: [
    savingsGoalsProvider.overrideWith((ref) async => items),
    savingsGoalHistoryProvider('goal-1').overrideWith(
      (ref) async => [
        SavingsGoalHistoryItem(
          id: 'history-1',
          action: 'created',
          actorId: 'actor-1',
          actorName: 'Ibrahim Aguettoi',
          createdAt: DateTime.utc(2026, 9, 1, 10, 42),
        ),
      ],
    ),
  ],
  child: const MaterialApp(home: SavingsGoalDetailPage(goalId: 'goal-1')),
);

void main() {
  testWidgets('affiche un état vide sans créer de solde ou de mouvement', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const []));
    await tester.pumpAndSettle();

    expect(find.text('Aucun objectif pour le moment'), findsOneWidget);
    expect(find.text('Créer un objectif'), findsOneWidget);
  });

  testWidgets('affiche la cible atteinte sans clôturer automatiquement', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([_item(accumulated: Money.fromDirhams(110000))]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cible financière atteinte'), findsOneWidget);
    expect(find.text('Actif'), findsOneWidget);
    expect(find.text('Clôturé'), findsNothing);
  });

  testWidgets('le détail affiche l’auteur de chaque changement métier', (
    tester,
  ) async {
    await tester.pumpWidget(
      _detailApp([_item(accumulated: Money.fromDirhams(30000))]),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Historique métier'), 300);
    await tester.pumpAndSettle();

    expect(find.text('Historique métier'), findsOneWidget);
    expect(
      find.textContaining('Effectué par : Ibrahim Aguettoi'),
      findsOneWidget,
    );
  });

  testWidgets('affiche une projection PRIOS estimée sans créer de donnée', (
    tester,
  ) async {
    final availability = FinancialAvailabilitySnapshot(
      realLiquidity: Money.fromDirhams(1000),
      envelopeTotal: Money.fromDirhams(30000),
      toAllocate: Money.fromDirhams(0),
      debtCommitments: Money.fromDirhams(0),
      potentialReceivables: Money.fromDirhams(0),
      goals: {
        'goal-1': GoalFundingProjection(
          goalId: 'goal-1',
          realAccumulated: Money.fromDirhams(30000),
          securedFunding: Money.fromDirhams(30000),
          remaining: Money.fromDirhams(70000),
          completionDate: DateTime(2027, 1, 1),
          reliability: ProjectionReliability.estimated,
        ),
      },
      planEntries: const {},
      warnings: const [],
    );
    await tester.pumpWidget(
      _app([
        _item(accumulated: Money.fromDirhams(30000)),
      ], availability: availability),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Finançable vers : 01/01/2027'), findsOneWidget);
    expect(
      find.text('Projection estimée selon le plan PRIOS actif.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
