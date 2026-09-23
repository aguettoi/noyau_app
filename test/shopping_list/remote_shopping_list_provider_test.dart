import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
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
      remoteEnvelopeHistoryProvider.overrideWith(
        (ref) async => [
          RemoteEnvelopeBalance(
            id: 'envelope-1',
            name: 'Nourriture',
            inflows: Money.fromDirhams(900),
            outflows: Money.fromDirhams(0),
            balance: Money.fromDirhams(900),
            isSystem: false,
          ),
        ],
      ),
      savingsGoalsProvider.overrideWith((ref) async => [_goal()]),
      shoppingListGatewayProvider.overrideWithValue(gateway),
    ],
  );

  test(
    'les indicateurs lisent seulement les ledgers canoniques associés',
    () async {
      final container = scope(_Gateway());
      addTearDown(container.dispose);
      final item = (await container.read(shoppingItemsProvider.future)).single;
      expect(item.envelopeName, 'Nourriture');
      expect(item.envelopeBalance, Money.fromDirhams(900));
      expect(item.estimatedGap, Money.fromDirhams(100));
      expect(item.goalName, 'Voiture');
    },
  );

  test(
    'les mutations Shopping ne sollicitent aucun moteur financier',
    () async {
      final gateway = _Gateway();
      final container = scope(gateway);
      addTearDown(container.dispose);
      const draft = ShoppingItemDraft(
        label: 'Lit bébé',
        estimatedAmount: Money.fromMinorUnits(10000),
      );
      await gateway.create('household-1', draft);
      await gateway.update('household-1', 'item-1', draft);
      await gateway.setMyPriority('household-1', 'item-1', 1);
      await gateway.cancel('household-1', 'item-1', null);
      await gateway.archive('household-1', 'item-1', null);
      expect(gateway.operations, [
        'create',
        'update',
        'priority',
        'cancel',
        'archive',
      ]);
      expect(gateway.financialMutationRequested, isFalse);
    },
  );
}

SavingsGoalProgress _goal() => SavingsGoalProgress(
  goal: SavingsGoal(
    id: 'goal-1',
    householdId: 'household-1',
    name: 'Voiture',
    type: SavingsGoalType.car,
    targetAmount: Money.fromDirhams(10000),
    priority: 1,
    status: SavingsGoalStatus.active,
    fundingEnvelopeId: 'envelope-1',
    createdBy: 'actor-1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  envelopeName: 'Nourriture',
  accumulated: Money.fromDirhams(900),
);

class _Gateway implements ShoppingListGateway {
  final operations = <String>[];
  bool financialMutationRequested = false;
  @override
  Future<void> archive(
    String householdId,
    String itemId,
    String? reason,
  ) async => operations.add('archive');
  @override
  Future<void> cancel(
    String householdId,
    String itemId,
    String? reason,
  ) async => operations.add('cancel');
  @override
  Future<String> create(String householdId, ShoppingItemDraft draft) async {
    operations.add('create');
    return 'item-2';
  }

  @override
  Future<List<ShoppingItemHistoryEntry>> fetchHistory(
    String householdId,
    String itemId,
  ) async => const [];
  @override
  Future<List<ShoppingItem>> fetchItems(String householdId) async => [
    ShoppingItem(
      id: 'item-1',
      householdId: householdId,
      label: 'Siège auto',
      estimatedAmount: Money.fromDirhams(1000),
      status: ShoppingItemStatus.planned,
      envelopeId: 'envelope-1',
      budgetGoalId: 'goal-1',
      createdBy: 'actor-1',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
  ];
  @override
  Future<List<ShoppingMemberPriority>> fetchMemberPriorities(
    String householdId,
  ) async => const [];
  @override
  Future<void> setMyPriority(
    String householdId,
    String itemId,
    int priority,
  ) async => operations.add('priority');
  @override
  Future<void> update(
    String householdId,
    String itemId,
    ShoppingItemDraft draft,
  ) async => operations.add('update');
}
