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

  testWidgets(
    'réordonne réellement trois priorités, persiste puis recharge le même ordre',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _ReorderGateway();
      final container = ProviderContainer(
        overrides: [
          activeHouseholdProvider.overrideWith(
            (ref) async => const ActiveHouseholdState(
              status: ActiveHouseholdStatus.singleHousehold,
              householdId: 'household',
              householdIds: ['household'],
            ),
          ),
          priorityPlansGatewayProvider.overrideWithValue(gateway),
          shoppingItemsProvider.overrideWith(
            (ref) async => [_shopping('a'), _shopping('b'), _shopping('c')],
          ),
          savingsGoalsProvider.overrideWith((ref) async => const []),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: PrioritiesPage())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('priority-drag-priority-c')),
      );
      await tester.drag(
        find.byKey(const Key('priority-drag-priority-c')),
        const Offset(0, -340),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(gateway.reorderCalls, 1);
      expect(gateway.sourceIds, ['shopping-c', 'shopping-a', 'shopping-b']);
      expect(
        tester.getTopLeft(find.text('TEST C')).dy,
        lessThan(tester.getTopLeft(find.text('TEST A')).dy),
      );

      container.invalidate(priorityPlansProvider);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(gateway.fetchItemsCalls, greaterThanOrEqualTo(2));
      expect(gateway.sourceIds, ['shopping-c', 'shopping-a', 'shopping-b']);
      expect(
        tester.getTopLeft(find.text('TEST C')).dy,
        lessThan(tester.getTopLeft(find.text('TEST A')).dy),
      );
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

ShoppingItemView _shopping([String suffix = 'tv']) => ShoppingItemView(
  item: ShoppingItem(
    id: 'shopping-$suffix',
    householdId: 'household',
    label: 'TEST ${suffix.toUpperCase()}',
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

class _ReorderGateway implements PriorityPlansGateway {
  _ReorderGateway()
    : _items = List.generate(
        3,
        (index) => _item(
          id: 'priority-${String.fromCharCode(97 + index)}',
          rank: index + 1,
          sourceId: 'shopping-${String.fromCharCode(97 + index)}',
        ),
      );

  List<PriorityPlanItem> _items;
  var reorderCalls = 0;
  var fetchItemsCalls = 0;

  List<String> get sourceIds => _items.map((item) => item.sourceId).toList();

  @override
  Future<List<PriorityPlan>> fetchPlans(String householdId) async => [
    PriorityPlan(
      id: 'plan',
      householdId: householdId,
      name: 'TEST PRIOS',
      status: PriorityPlanStatus.active,
      monthlyCapacity: const Money.fromMinorUnits(500000),
      createdBy: 'user',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    ),
  ];

  @override
  Future<List<PriorityPlanItem>> fetchItems(String householdId) async {
    fetchItemsCalls++;
    return List.unmodifiable(_items);
  }

  @override
  Future<void> reorderItems(
    String householdId,
    String planId,
    List<String> itemIds,
  ) async {
    reorderCalls++;
    final byId = {for (final item in _items) item.id: item};
    _items = [
      for (var index = 0; index < itemIds.length; index++)
        _itemFrom(byId[itemIds[index]]!, rank: index + 1),
    ];
  }

  @override
  Future<String> addItem(
    String householdId,
    String planId,
    PrioritySourceType sourceType,
    String sourceId,
  ) async => 'item';

  @override
  Future<String> create(String householdId, PriorityPlanDraft draft) async =>
      'plan';
  @override
  Future<void> removeItem(
    String householdId,
    String planId,
    String itemId,
  ) async {}
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

PriorityPlanItem _item({
  required String id,
  required int rank,
  required String sourceId,
}) => PriorityPlanItem(
  id: id,
  planId: 'plan',
  householdId: 'household',
  rank: rank,
  sourceType: PrioritySourceType.shoppingItem,
  sourceId: sourceId,
  createdBy: 'user',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

PriorityPlanItem _itemFrom(PriorityPlanItem item, {required int rank}) =>
    _item(id: item.id, rank: rank, sourceId: item.sourceId);
