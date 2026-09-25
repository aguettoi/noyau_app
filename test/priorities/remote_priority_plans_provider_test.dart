import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/priorities/application/providers/remote_priority_plans_provider.dart';
import 'package:noyau_app/features/priorities/domain/priority_plan.dart';
import 'package:noyau_app/features/savings_goals/application/providers/remote_savings_goals_provider.dart';
import 'package:noyau_app/features/savings_goals/domain/savings_goal.dart';
import 'package:noyau_app/features/shopping_list/application/providers/remote_shopping_list_provider.dart';
import 'package:noyau_app/features/shopping_list/domain/shopping_item.dart';

void main() {
  ProviderContainer scope(_Gateway gateway) => ProviderContainer(
    overrides: [
      activeHouseholdProvider.overrideWith(
        (ref) async => const ActiveHouseholdState(
          status: ActiveHouseholdStatus.singleHousehold,
          householdId: 'household-1',
        ),
      ),
      priorityPlansGatewayProvider.overrideWithValue(gateway),
      shoppingItemsProvider.overrideWith((ref) async => [_shopping]),
      savingsGoalsProvider.overrideWith((ref) async => [_goal]),
      remoteEnvelopeHistoryProvider.overrideWith((ref) async => const []),
    ],
  );

  test('un achat lié à un objectif lit le besoin restant canonique', () async {
    final container = scope(_Gateway());
    addTearDown(container.dispose);

    final plans = await container.read(priorityPlansProvider.future);
    final item = plans.single.items.single;

    expect(item.source.label, 'TV familiale');
    expect(item.source.estimatedNeed, Money.fromDirhams(6000));
    expect(item.source.goalId, 'goal-1');
  });

  test('les mutations restent hors des moteurs financiers', () async {
    final gateway = _Gateway();
    await gateway.create(
      'household-1',
      const PriorityPlanDraft(name: 'Plan famille'),
    );
    await gateway.addItem(
      'household-1',
      'plan-1',
      PrioritySourceType.shoppingItem,
      'item-1',
    );
    await gateway.reorderItems('household-1', 'plan-1', ['plan-item-1']);
    await gateway.removeItem('household-1', 'plan-1', 'plan-item-1');

    expect(gateway.operations, ['create', 'add', 'reorder', 'remove']);
    expect(gateway.financialMutationRequested, isFalse);
  });
}

final _shopping = ShoppingItemView(
  item: ShoppingItem(
    id: 'item-1',
    householdId: 'household-1',
    label: 'TV familiale',
    estimatedAmount: Money.fromDirhams(8000),
    status: ShoppingItemStatus.planned,
    budgetGoalId: 'goal-1',
    createdBy: 'actor-1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  memberPriorities: const [],
  goalName: 'TV familiale',
  goalProgress: .25,
);

final _goal = SavingsGoalProgress(
  goal: SavingsGoal(
    id: 'goal-1',
    householdId: 'household-1',
    name: 'TV familiale',
    type: SavingsGoalType.majorPurchase,
    targetAmount: Money.fromDirhams(8000),
    priority: 1,
    status: SavingsGoalStatus.active,
    fundingEnvelopeId: 'envelope-1',
    createdBy: 'actor-1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  envelopeName: 'TV',
  accumulated: Money.fromDirhams(2000),
);

class _Gateway implements PriorityPlansGateway {
  final operations = <String>[];
  bool financialMutationRequested = false;

  @override
  Future<String> addItem(
    String householdId,
    String planId,
    PrioritySourceType sourceType,
    String sourceId,
  ) async {
    operations.add('add');
    return 'plan-item-1';
  }

  @override
  Future<String> create(String householdId, PriorityPlanDraft draft) async {
    operations.add('create');
    return 'plan-2';
  }

  @override
  Future<void> activate(String householdId, String planId) async {
    operations.add('activate');
  }

  @override
  Future<List<PriorityPlanItem>> fetchItems(String householdId) async => [
    PriorityPlanItem(
      id: 'plan-item-1',
      householdId: householdId,
      planId: 'plan-1',
      rank: 1,
      sourceType: PrioritySourceType.shoppingItem,
      sourceId: 'item-1',
      createdBy: 'actor-1',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  ];

  @override
  Future<List<PriorityPlan>> fetchPlans(String householdId) async => [
    PriorityPlan(
      id: 'plan-1',
      householdId: householdId,
      name: 'Plan famille',
      status: PriorityPlanStatus.active,
      monthlyCapacity: Money.fromDirhams(5000),
      createdBy: 'actor-1',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  ];

  @override
  Future<void> removeItem(
    String householdId,
    String planId,
    String itemId,
  ) async {
    operations.add('remove');
  }

  @override
  Future<void> reorderItems(
    String householdId,
    String planId,
    List<String> itemIds,
  ) async {
    operations.add('reorder');
  }

  @override
  Future<void> setStatus(
    String householdId,
    String planId,
    PriorityPlanStatus status,
  ) async {}

  @override
  Future<void> update(
    String householdId,
    String planId,
    PriorityPlanDraft draft,
  ) async {}
}
