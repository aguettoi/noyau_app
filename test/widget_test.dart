import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/noyau_app.dart';
import 'package:noyau_app/features/finance/application/finance_workspace.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_transactions_provider.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/savings_goals/application/providers/remote_savings_goals_provider.dart';
import 'package:noyau_app/features/shopping_list/application/providers/remote_shopping_list_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';
import 'package:noyau_app/features/finance/domain/transaction_history_item.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseUserIdProvider.overrideWith(
            (ref) => Stream.value('test-user'),
          ),
          financeWorkspaceProvider.overrideWith(_TestWorkspaceController.new),
          activeHouseholdProvider.overrideWith(
            (ref) async => const ActiveHouseholdState(
              status: ActiveHouseholdStatus.singleHousehold,
              householdId: 'household-test',
              householdIds: ['household-test'],
            ),
          ),
          remoteAccountsProvider.overrideWith(
            (ref) async => const <FinancialAccount>[],
          ),
          remoteHouseholdMembersProvider.overrideWith(
            (ref) async => const <HouseholdMember>[],
          ),
          remoteTransactionsProvider.overrideWith(
            (ref) async => const <TransactionHistoryItem>[],
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => const <RemoteEnvelopeBalance>[],
          ),
          remoteEnvelopeHistoryProvider.overrideWith(
            (ref) async => const <RemoteEnvelopeBalance>[],
          ),
          savingsGoalsProvider.overrideWith((ref) async => const []),
          shoppingItemsProvider.overrideWith((ref) async => const []),
        ],
        child: const NoyauApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('navigation relie chaque destination a sa page', (tester) async {
    await pumpApp(tester);

    final navigation = find.byType(NavigationBar);
    expect(navigation, findsOneWidget);
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Comptes')),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Fondation')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 1);
    expect(find.text('Fondation financière'), findsOneWidget);
    expect(
      find.text('Aucune donnee du foyer n est encore importee.'),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Enveloppes')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 2);
    expect(
      find.text(
        'Soldes calculés exclusivement depuis le journal des enveloppes.',
      ),
      findsOneWidget,
    );
    final importEnvelopes = find.byKey(const Key('envelope-import-csv-cta'));
    expect(importEnvelopes, findsOneWidget);
    await tester.tap(importEnvelopes);
    await tester.pumpAndSettle();
    expect(find.text('Import des enveloppes'), findsNWidgets(2));
    expect(
      find.textContaining('référentiel des enveloppes du foyer'),
      findsOneWidget,
    );
    expect(find.textContaining('00000000-'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Objectifs')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 3);
    expect(find.text('Épargne & objectifs'), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Achats')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 4);
    expect(find.text('Shopping List'), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Import')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 5);
    expect(find.text('Import des comptes'), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Comptes')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Comptes')),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets(
    'le Grand Livre est accessible et prêt à saisir une transaction',
    (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Fondation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Grand livre'));
      await tester.pumpAndSettle();

      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Grand Livre'), findsOneWidget);
      expect(find.text('Aucune transaction'), findsOneWidget);
      expect(find.byKey(const Key('add-transaction-button')), findsOneWidget);
    },
  );

  testWidgets('la navigation desktop utilise un rail sans modifier le mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);

    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(
      find.descendant(of: rail, matching: find.text('Fondation')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fondation financière'), findsOneWidget);
  });
}

class _TestWorkspaceController extends FinanceWorkspaceController {
  @override
  Future<FinanceWorkspace> build() async => FinanceWorkspace.empty(const []);
}
