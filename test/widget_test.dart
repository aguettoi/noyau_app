import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/noyau_app.dart';
import 'package:noyau_app/features/finance/application/finance_workspace.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';
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
    expect(find.text('Fondation financiere'), findsOneWidget);
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
        'Soldes calcules a partir du Journal importe. Aucun montant n est saisi ici.',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Import')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 3);
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
}

class _TestWorkspaceController extends FinanceWorkspaceController {
  @override
  Future<FinanceWorkspace> build() async => FinanceWorkspace.empty(const []);
}
