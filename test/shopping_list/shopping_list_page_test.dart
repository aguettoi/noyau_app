import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';
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
      remoteHouseholdMembersProvider.overrideWith((ref) async => _members),
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
      find.descendant(
        of: dialog,
        matching: find.text('Priorité commune / finale'),
      ),
      findsOneWidget,
    );
    expect(find.text('Priorités individuelles'), findsOneWidget);
    expect(find.text('Priorité Membre Alpha'), findsOneWidget);
    expect(find.text('Priorité Membre Bêta'), findsOneWidget);
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
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app([_item]));
      await tester.pumpAndSettle();

      final edit = find.widgetWithText(OutlinedButton, 'Modifier');
      await tester.tap(edit);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Modifier l’achat prévu'), findsOneWidget);
      expect(find.text('Article *'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<int?>>(
              find.byKey(
                const ValueKey('shopping-member-priority-member-alpha'),
              ),
            )
            .initialValue,
        0,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<int?>>(
              find.byKey(
                const ValueKey('shopping-member-priority-member-beta'),
              ),
            )
            .initialValue,
        2,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<int?>>(
              find.byKey(const ValueKey('shopping-final-priority')),
            )
            .initialValue,
        3,
      );
    },
  );

  testWidgets(
    'un achat prévu expose le parcours Acheter sans écriture locale',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app([_item]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Acheter'));
      await tester.pumpAndSettle();

      expect(find.text('Enregistrer l’achat maintenant'), findsOneWidget);
      expect(find.text('Rattacher une dépense existante'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('les quatre filtres présentent un empty state adapté', (
    tester,
  ) async {
    await tester.pumpWidget(app(const []));
    await tester.pumpAndSettle();
    expect(find.text('Aucun achat prévu'), findsOneWidget);

    await tester.tap(find.text('Acheté'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun achat effectué'), findsOneWidget);

    await tester.tap(find.text('Annulé'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun achat annulé'), findsOneWidget);

    await tester.tap(find.text('Archivé'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun achat archivé'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _members = [
  HouseholdMember(id: 'member-alpha', displayName: 'Membre Alpha'),
  HouseholdMember(id: 'member-beta', displayName: 'Membre Bêta'),
];

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
    finalPriority: 3,
    createdBy: 'actor-1',
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  memberPriorities: const [
    ShoppingMemberPriority(
      itemId: 'item-1',
      memberUserId: 'member-alpha',
      priority: 0,
      memberName: 'Membre Alpha',
    ),
    ShoppingMemberPriority(
      itemId: 'item-1',
      memberUserId: 'member-beta',
      priority: 2,
      memberName: 'Membre Bêta',
    ),
  ],
  envelopeName: 'Nourriture',
  envelopeBalance: Money.fromDirhams(1000),
  goalName: 'Voiture',
  goalProgress: .1,
);
