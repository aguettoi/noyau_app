import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/savings_goals/application/providers/remote_savings_goals_provider.dart';
import 'package:noyau_app/features/savings_goals/domain/savings_goal.dart';
import 'package:noyau_app/features/shopping_list/application/providers/remote_shopping_list_provider.dart';
import 'package:noyau_app/features/shopping_list/domain/shopping_item.dart';
import 'package:noyau_app/features/shopping_list/presentation/shopping_list_page.dart';

void main() {
  Widget app(List<ShoppingItemView> items) => ProviderScope(
    overrides: [
      shoppingItemsProvider.overrideWith((ref) async => items),
      remoteEnvelopeHistoryProvider.overrideWith((ref) async => [_envelope]),
      savingsGoalsProvider.overrideWith((ref) async => [_goal]),
    ],
    child: const MaterialApp(home: Scaffold(body: ShoppingListPage())),
  );

  testWidgets('le dialogue de création rend tous ses champs sans exception', (
    tester,
  ) async {
    await tester.pumpWidget(app(const []));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('create-shopping-item')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('Ajouter un achat prévu'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Article *')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Montant estimé (MAD)')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Priorité finale')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('Objectif lié (facultatif)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.text('Enveloppe liée (facultatif)'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Notes')),
      findsOneWidget,
    );

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'le dialogue d’édition réutilise le formulaire sans clé dupliquée',
    (tester) async {
      await tester.pumpWidget(app([_item]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Modifier l’achat prévu'), findsOneWidget);
      expect(find.text('Article *'), findsOneWidget);
    },
  );
}

final _envelope = RemoteEnvelopeBalance(
  id: 'envelope-1',
  name: 'Nourriture',
  inflows: Money.fromDirhams(1000),
  outflows: Money.fromDirhams(0),
  balance: Money.fromDirhams(1000),
  isSystem: false,
);

final _goal = SavingsGoalProgress(
  goal: SavingsGoal(
    id: 'goal-1',
    householdId: 'household-1',
    name: 'Voiture',
    type: SavingsGoalType.car,
    targetAmount: Money.fromDirhams(10000),
    priority: 0,
    status: SavingsGoalStatus.active,
    fundingEnvelopeId: 'envelope-1',
    createdBy: 'actor-1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  envelopeName: 'Nourriture',
  accumulated: Money.fromDirhams(1000),
);

final _item = ShoppingItemView(
  item: ShoppingItem(
    id: 'item-1',
    householdId: 'household-1',
    label: 'Siège auto',
    status: ShoppingItemStatus.planned,
    envelopeId: 'envelope-1',
    budgetGoalId: 'goal-1',
    createdBy: 'actor-1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  memberPriorities: const [],
  envelopeName: 'Nourriture',
  envelopeBalance: Money.fromDirhams(1000),
  goalName: 'Voiture',
  goalProgress: .1,
);
