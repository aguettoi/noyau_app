import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/noyau_app.dart';
import 'package:noyau_app/app/global_refresh_provider.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_transactions_provider.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/priorities/application/providers/remote_priority_plans_provider.dart';
import 'package:noyau_app/features/savings_goals/application/providers/remote_savings_goals_provider.dart';
import 'package:noyau_app/features/shopping_list/application/providers/remote_shopping_list_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';
import 'package:noyau_app/features/finance/domain/transaction_history_item.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/dashboard/application/dashboard_metrics.dart';
import 'package:noyau_app/features/dashboard/application/providers/remote_financial_dashboard_provider.dart';
import 'package:noyau_app/core/money/money.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    GlobalRefreshAction? refreshAction,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseUserIdProvider.overrideWith(
            (ref) => Stream.value('test-user'),
          ),
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
          priorityPlansProvider.overrideWith((ref) async => const []),
          financialDashboardProvider.overrideWith(
            (ref) async => const FinancialDashboardSnapshot(
              accounts: [],
              ordinaryEnvelopes: [],
              toAllocate: null,
              budget: DashboardBudgetSummary(
                period: null,
                planned: Money.fromMinorUnits(0),
                consumed: Money.fromMinorUnits(0),
                overspentEnvelopeIds: {},
              ),
              monthlyFlow: DashboardMonthlyFlow(
                income: Money.fromMinorUnits(0),
                expense: Money.fromMinorUnits(0),
              ),
              debts: [],
              incomeReceivables: [],
              recoveryReceivables: [],
              activeGoals: [],
              nextPriority: null,
              alerts: [],
            ),
          ),
          if (refreshAction != null)
            globalRefreshActionProvider.overrideWithValue(refreshAction),
        ],
        child: const NoyauApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Actualiser coordonne un seul refresh et confirme le succès', (
    tester,
  ) async {
    final completer = Completer<void>();
    var calls = 0;
    await pumpApp(
      tester,
      refreshAction: () {
        calls += 1;
        return completer.future;
      },
    );

    final button = find.byKey(const Key('global-refresh-button'));
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.tap(button);
    await tester.pump();
    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Données actualisées.'), findsOneWidget);
  });

  testWidgets('Actualiser remonte une erreur claire', (tester) async {
    await pumpApp(
      tester,
      refreshAction: () async => throw StateError('source indisponible'),
    );

    await tester.tap(find.byKey(const Key('global-refresh-button')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Actualisation impossible. Vérifiez votre connexion puis réessayez.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('le retour au premier plan déclenche un refresh silencieux', (
    tester,
  ) async {
    var calls = 0;
    await pumpApp(tester, refreshAction: () async => calls += 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Données actualisées.'), findsNothing);
  });

  testWidgets('navigation relie chaque destination a sa page', (tester) async {
    await pumpApp(tester);

    final navigation = find.byType(NavigationBar);
    expect(navigation, findsOneWidget);
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);
    expect(find.text('Tableau de bord'), findsOneWidget);
    // V2 adds filters and an empty-household notice before the budget section.
    // Verify the same budget state through the real scrollable page.
    await tester.scrollUntilVisible(
      find.byKey(const Key('dashboard-budget-empty')),
      250,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('financial-dashboard-page')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.byKey(const Key('dashboard-budget-empty')), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Fondation')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 2);
    expect(find.text('Fondation financière'), findsOneWidget);
    expect(
      find.text(
        'Accédez aux fonctions structurantes de votre foyer financier.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('25 enveloppes détectées'), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Enveloppes')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 3);
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
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 4);
    expect(find.text('Épargne & objectifs'), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Achats')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 5);
    expect(find.text('Shopping List'), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Priorités')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 6);
    expect(find.text('Aucun plan de priorités'), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Import')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 7);
    expect(find.text('Import des comptes'), findsOneWidget);

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Comptes')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 1);
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
      await tester.tap(find.text('Grand Livre'));
      await tester.pumpAndSettle();

      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Grand Livre'), findsOneWidget);
      expect(find.text('Aucune transaction'), findsOneWidget);
      expect(find.byKey(const Key('add-transaction-button')), findsOneWidget);
    },
  );

  testWidgets('la Fondation ouvre ses quatre raccourcis canoniques', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Fondation'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Import & migration'));
    await tester.pumpAndSettle();
    expect(find.text('Import des comptes'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      7,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Fondation'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fondation financière'), findsOneWidget);

    await tester.tap(find.text('Comptes & rapprochements'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Comptes')),
      findsOneWidget,
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Fondation'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fondation financière'), findsOneWidget);

    await tester.tap(find.text('Budget'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Budget')),
      findsOneWidget,
    );
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Fondation financière'), findsOneWidget);

    await tester.tap(find.text('Grand Livre'));
    await tester.pumpAndSettle();
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Grand Livre'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Fondation financière'), findsOneWidget);
  });

  testWidgets(
    'Pilotage conserve le shell pour les sections principales et le retour des pages secondaires',
    (tester) async {
      await pumpApp(tester);
      final navigation = find.byType(NavigationBar);

      Future<void> returnToPilotage() async {
        await tester.tap(
          find.descendant(of: navigation, matching: find.text('Pilotage')),
        );
        await tester.pumpAndSettle();
        expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);
        await tester.drag(
          find.byKey(const Key('financial-dashboard-page')),
          const Offset(0, 1200),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tapDashboardAction(Key key) async {
        await tester.dragUntilVisible(
          find.byKey(key),
          find.byKey(const Key('financial-dashboard-page')),
          const Offset(0, -420),
        );
        await tester.ensureVisible(find.byKey(key));
        await tester.pumpAndSettle();
        expect(find.byKey(key).hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
      }

      for (final target in const [
        (Key('dashboard-open-accounts'), 'Comptes'),
        (Key('dashboard-open-envelopes'), 'Enveloppes'),
        (Key('dashboard-open-goals'), 'Épargne & objectifs'),
        (Key('dashboard-open-priorities'), 'Aucun plan de priorités'),
      ]) {
        await tapDashboardAction(target.$1);
        expect(find.text(target.$2), findsWidgets);
        expect(navigation, findsOneWidget);
        await returnToPilotage();
      }

      for (final target in const [
        Key('dashboard-open-envelopes'),
        Key('dashboard-open-goals'),
      ]) {
        await tapDashboardAction(target);
        expect(navigation, findsOneWidget);
        await returnToPilotage();
      }

      await tapDashboardAction(const Key('dashboard-open-month-preparation'));
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);
      expect(find.byType(BackButton), findsNothing);

      await tapDashboardAction(const Key('dashboard-open-obligations'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);
      expect(find.byType(BackButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'les messages informatifs Pilotage restent secondaires et neutres',
    (tester) async {
      await pumpApp(tester);
      final navigation = find.byType(NavigationBar);

      Future<void> tapDashboardAction(Key key) async {
        await tester.dragUntilVisible(
          find.byKey(key),
          find.byKey(const Key('financial-dashboard-page')),
          const Offset(0, -420),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(key).hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(key));
        await tester.pumpAndSettle();
      }

      Future<void> expectInfoMessage(String message) async {
        final text = tester.widget<Text>(find.text(message));
        final style = text.style!;
        expect(style.fontSize, lessThanOrEqualTo(16));
        expect(
          style.color,
          Theme.of(
            tester.element(find.text(message)),
          ).colorScheme.onSurfaceVariant,
        );
        expect(style.decoration, TextDecoration.none);
      }

      await tapDashboardAction(const Key('dashboard-open-envelopes'));
      await expectInfoMessage(
        'Soldes calculés exclusivement depuis le journal des enveloppes.',
      );
      await tester.tap(
        find.descendant(of: navigation, matching: find.text('Pilotage')),
      );
      await tester.pumpAndSettle();

      await tapDashboardAction(const Key('dashboard-open-goals'));
      await expectInfoMessage(
        'Les objectifs observent le solde réel de leur enveloppe dédiée.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 430.0]) {
    testWidgets(
      'navigation mobile compacte à $width px expose Plus et les huit espaces',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selectedIndex = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Text('Destination $selectedIndex'),
                bottomNavigationBar: CompactFinanceNavigation(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => selectedIndex = index),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final navigation = find.byKey(const Key('compact-mobile-navigation'));
        expect(navigation, findsOneWidget);
        expect(
          find.descendant(
            of: navigation,
            matching: find.byType(NavigationDestination),
          ),
          findsNWidgets(5),
        );
        for (final label in [
          'Pilotage',
          'Comptes',
          'Enveloppes',
          'Objectifs',
          'Plus',
        ]) {
          expect(
            find.descendant(of: navigation, matching: find.text(label)),
            findsOneWidget,
          );
        }
        for (final label in ['Fondation', 'Achats', 'Priorités', 'Import']) {
          expect(
            find.descendant(of: navigation, matching: find.text(label)),
            findsNothing,
          );
        }

        await tester.tap(
          find.descendant(of: navigation, matching: find.text('Plus')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Autres espaces de FINANCIEL PILOTE'), findsOneWidget);
        for (final destinationIndex in [2, 5, 6, 7]) {
          expect(
            find.byKey(Key('mobile-more-destination-$destinationIndex')),
            findsOneWidget,
          );
        }
        for (final destinationIndex in [2, 5, 6, 7]) {
          if (destinationIndex != 2) {
            await tester.tap(
              find.descendant(of: navigation, matching: find.text('Plus')),
            );
            await tester.pumpAndSettle();
          }
          await tester.tap(
            find.byKey(Key('mobile-more-destination-$destinationIndex')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Destination $destinationIndex'), findsOneWidget);
          expect(tester.widget<NavigationBar>(navigation).selectedIndex, 4);
        }
        for (final destination in const [
          (0, 'Pilotage'),
          (1, 'Comptes'),
          (3, 'Enveloppes'),
          (4, 'Objectifs'),
        ]) {
          await tester.tap(
            find.descendant(
              of: navigation,
              matching: find.text(destination.$2),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Destination ${destination.$1}'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final viewport in const [
    Size(390, 360),
    Size(430, 600),
    Size(390, 900),
  ]) {
    testWidgets(
      'la feuille Plus reste accessible à ${viewport.width}x${viewport.height}',
      (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var selectedIndex = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Text('Destination $selectedIndex'),
                bottomNavigationBar: CompactFinanceNavigation(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => selectedIndex = index),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final navigation = find.byKey(const Key('compact-mobile-navigation'));
        await tester.tap(
          find.descendant(of: navigation, matching: find.text('Plus')),
        );
        await tester.pumpAndSettle();

        final moreList = find.byKey(const Key('mobile-more-list'));
        expect(moreList, findsOneWidget);
        expect(
          find.ancestor(of: moreList, matching: find.byType(SafeArea)),
          findsOneWidget,
        );
        for (final destinationIndex in [2, 5, 6, 7]) {
          expect(
            find.byKey(Key('mobile-more-destination-$destinationIndex')),
            findsOneWidget,
          );
        }

        final scrollable = find.descendant(
          of: moreList,
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsOneWidget);
        if (viewport.height == 360) {
          expect(
            tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
            greaterThan(0),
          );
        }
        final importDestination = find.byKey(
          const Key('mobile-more-destination-7'),
        );
        await tester.scrollUntilVisible(
          importDestination,
          120,
          scrollable: scrollable,
        );
        await tester.tap(importDestination);
        await tester.pumpAndSettle();

        expect(find.text('Destination 7'), findsOneWidget);
        expect(find.byKey(const Key('mobile-more-list')), findsNothing);
        expect(tester.widget<NavigationBar>(navigation).selectedIndex, 4);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('largeur intermédiaire conserve les huit destinations lisibles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpApp(tester);
    final navigation = find.byType(NavigationBar);
    expect(
      find.descendant(
        of: navigation,
        matching: find.byType(NavigationDestination),
      ),
      findsNWidgets(8),
    );
    expect(find.text('Plus'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la navigation desktop utilise un rail sans modifier le mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
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

    await tester.tap(
      find.descendant(of: rail, matching: find.text('Pilotage')),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('financial-dashboard-page')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('dashboard-open-envelopes')),
    );
    await tester.tap(find.byKey(const Key('dashboard-open-envelopes')));
    await tester.pumpAndSettle();
    expect(rail, findsOneWidget);
    expect(find.text('Enveloppes'), findsWidgets);
    await tester.tap(
      find.descendant(of: rail, matching: find.text('Pilotage')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationRail>(rail).selectedIndex, 0);
  });
}
