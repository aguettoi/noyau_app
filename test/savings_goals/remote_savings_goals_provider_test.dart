import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/savings_goals/application/providers/remote_savings_goals_provider.dart';
import 'package:noyau_app/features/savings_goals/domain/savings_goal.dart';

void main() {
  ProviderContainer container(_Gateway gateway) => ProviderContainer(
    overrides: [
      activeHouseholdProvider.overrideWith(
        (ref) async => const ActiveHouseholdState(
          status: ActiveHouseholdStatus.singleHousehold,
          householdId: 'household-1',
        ),
      ),
      remoteEnvelopeHistoryProvider.overrideWith(
        (ref) async => [
          RemoteEnvelopeBalance(
            id: 'envelope-car',
            name: 'Voiture',
            inflows: Money.fromDirhams(60000),
            outflows: Money.fromDirhams(0),
            balance: Money.fromDirhams(60000),
            isSystem: false,
          ),
        ],
      ),
      savingsGoalsGatewayProvider.overrideWithValue(gateway),
    ],
  );

  test(
    'la liste dérive la progression depuis le ledger des enveloppes',
    () async {
      final scope = container(_Gateway());
      addTearDown(scope.dispose);

      final goals = await scope.read(savingsGoalsProvider.future);

      expect(goals.single.accumulated, Money.fromDirhams(60000));
      expect(goals.single.remaining, Money.fromDirhams(40000));
      expect(goals.single.goal.status, SavingsGoalStatus.active);
    },
  );

  test(
    'les mutations d’objectif ne demandent aucun mouvement financier',
    () async {
      final gateway = _Gateway();
      final scope = container(gateway);
      addTearDown(scope.dispose);
      final draft = SavingsGoalDraft(
        name: 'Voyage',
        type: SavingsGoalType.travel,
        targetAmount: Money.fromDirhams(25000),
        priority: 2,
        fundingEnvelopeId: 'envelope-car',
      );

      await scope.read(createSavingsGoalProvider)(
        draft,
        SavingsGoalStatus.planned,
      );
      await scope.read(updateSavingsGoalProvider)('goal-1', draft);
      await scope.read(setSavingsGoalStatusProvider)(
        'goal-1',
        SavingsGoalStatus.paused,
        null,
      );

      expect(gateway.created, isTrue);
      expect(gateway.updated, isTrue);
      expect(gateway.statusChanged, isTrue);
      expect(gateway.financialMutationRequested, isFalse);
    },
  );
}

class _Gateway implements SavingsGoalsGateway {
  bool created = false;
  bool updated = false;
  bool statusChanged = false;
  bool financialMutationRequested = false;

  @override
  Future<String> create({
    required String householdId,
    required SavingsGoalDraft draft,
    required SavingsGoalStatus initialStatus,
  }) async {
    created = true;
    return 'goal-2';
  }

  @override
  Future<List<SavingsGoal>> fetchGoals(String householdId) async => [
    SavingsGoal(
      id: 'goal-1',
      householdId: householdId,
      name: 'Voiture',
      type: SavingsGoalType.car,
      targetAmount: Money.fromDirhams(100000),
      priority: 1,
      status: SavingsGoalStatus.active,
      fundingEnvelopeId: 'envelope-car',
      createdBy: 'actor-1',
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    ),
  ];

  @override
  Future<List<SavingsGoalHistoryItem>> fetchHistory(
    String householdId,
    String goalId,
  ) async => const [];

  @override
  Future<void> setStatus({
    required String householdId,
    required String goalId,
    required SavingsGoalStatus status,
    String? reason,
  }) async {
    statusChanged = true;
  }

  @override
  Future<void> update({
    required String householdId,
    required String goalId,
    required SavingsGoalDraft draft,
  }) async {
    updated = true;
  }
}
