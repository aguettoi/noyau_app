import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/priorities/application/providers/remote_priority_plans_provider.dart';
import 'package:noyau_app/features/priorities/domain/priority_plan.dart';
import 'package:noyau_app/features/priorities/presentation/priorities_page.dart';
import 'package:noyau_app/features/savings_goals/application/providers/remote_savings_goals_provider.dart';
import 'package:noyau_app/features/savings_goals/domain/savings_goal.dart';
import 'package:noyau_app/features/shopping_list/application/providers/remote_shopping_list_provider.dart';
import 'package:noyau_app/features/shopping_list/domain/shopping_item.dart';

void main() {
  testWidgets('permet de créer un plan sans créer de donnée financière', (
    tester,
  ) async {
    final gateway = _Gateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          priorityPlansProvider.overrideWith((ref) async => const []),
          priorityPlansGatewayProvider.overrideWithValue(gateway),
        ],
        child: const MaterialApp(home: Scaffold(body: PrioritiesPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('create-priority-plan')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Créer un plan'), findsWidgets);
    expect(find.byKey(const Key('priority-plan-name')), findsOneWidget);
    expect(find.byKey(const Key('priority-plan-capacity')), findsOneWidget);
    expect(find.textContaining('Hypothèse de planification'), findsOneWidget);
  });

  testWidgets(
    'sélectionne réellement un achat puis un objectif avec une identité stable',
    (tester) async {
      final gateway = _Gateway();
      final plan = _planView();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeHouseholdProvider.overrideWith(
              (ref) async => const ActiveHouseholdState(
                status: ActiveHouseholdStatus.singleHousehold,
                householdId: 'household',
                householdIds: ['household'],
              ),
            ),
            priorityPlansProvider.overrideWith((ref) async => [plan]),
            priorityPlansGatewayProvider.overrideWithValue(gateway),
            shoppingItemsProvider.overrideWith((ref) async => [_shopping()]),
            savingsGoalsProvider.overrideWith((ref) async => [_goal()]),
          ],
          child: const MaterialApp(home: Scaffold(body: PrioritiesPage())),
        ),
      );
      await tester.pumpAndSettle();

      final add = find.byKey(const Key('add-priority-item-plan'));
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('priority-source-picker')), findsOneWidget);

      await tester.tap(find.byKey(const Key('priority-source-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Achat · TEST TV').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(gateway.added, [(PrioritySourceType.shoppingItem, 'shopping-tv')]);

      await tester.tap(add);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('priority-source-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Objectif · TEST Voyage').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Ajouter'));
      await tester.pumpAndSettle();
      expect(gateway.added, [
        (PrioritySourceType.shoppingItem, 'shopping-tv'),
        (PrioritySourceType.budgetGoal, 'goal-voyage'),
      ]);
    },
  );
}

PriorityPlanView _planView() => PriorityPlanView(
  plan: PriorityPlan(
    id: 'plan',
    householdId: 'household',
    name: 'TEST PRIOS',
    status: PriorityPlanStatus.active,
    createdBy: 'user',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  items: const [],
);

ShoppingItemView _shopping() => ShoppingItemView(
  item: ShoppingItem(
    id: 'shopping-tv',
    householdId: 'household',
    label: 'TEST TV',
    status: ShoppingItemStatus.planned,
    createdBy: 'user',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    estimatedAmount: const Money.fromMinorUnits(600000),
  ),
  memberPriorities: const [],
);

SavingsGoalProgress _goal() => SavingsGoalProgress(
  goal: SavingsGoal(
    id: 'goal-voyage',
    householdId: 'household',
    name: 'TEST Voyage',
    type: SavingsGoalType.travel,
    targetAmount: const Money.fromMinorUnits(1500000),
    priority: 1,
    status: SavingsGoalStatus.active,
    fundingEnvelopeId: 'envelope',
    createdBy: 'user',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  envelopeName: 'Voyage',
  accumulated: const Money.fromMinorUnits(0),
);

class _Gateway implements PriorityPlansGateway {
  final added = <(PrioritySourceType, String)>[];

  @override
  Future<String> addItem(
    String a,
    String b,
    PrioritySourceType c,
    String d,
  ) async {
    added.add((c, d));
    return 'item';
  }

  @override
  Future<String> create(String a, PriorityPlanDraft b) async => 'plan';
  @override
  Future<List<PriorityPlanItem>> fetchItems(String householdId) async =>
      const [];
  @override
  Future<List<PriorityPlan>> fetchPlans(String householdId) async => const [];
  @override
  Future<void> removeItem(String a, String b, String c) async {}
  @override
  Future<void> reorderItems(String a, String b, List<String> c) async {}
  @override
  Future<void> setStatus(String a, String b, PriorityPlanStatus c) async {}
  @override
  Future<void> update(String a, String b, PriorityPlanDraft c) async {}
}
