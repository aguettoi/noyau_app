import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/priorities/application/providers/remote_priority_plans_provider.dart';
import 'package:noyau_app/features/priorities/domain/priority_plan.dart';
import 'package:noyau_app/features/priorities/presentation/priorities_page.dart';

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
}

class _Gateway implements PriorityPlansGateway {
  @override
  Future<String> addItem(
    String a,
    String b,
    PrioritySourceType c,
    String d,
  ) async => 'item';
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
