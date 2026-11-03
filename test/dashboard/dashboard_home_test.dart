import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/dashboard/application/providers/dashboard_home_provider.dart';
import 'package:noyau_app/features/dashboard/application/providers/remote_financial_dashboard_provider.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/dashboard/presentation/dashboard_home_locale.dart';
import 'package:noyau_app/features/dashboard/presentation/financial_dashboard_page.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';

import 'dashboard_v2_test.dart' as fixtures;

void main() {
  test(
    'composition deduplicates actions and excludes sensitive calendar data',
    () {
      final model = composeDashboardHome(
        snapshot: fixtures.snapshot(populated: true),
        now: fixtures.now,
        alerts: [
          const AppAlert(
            key: 'a',
            title: 'Compte à vérifier',
            detail: 'Premier signal',
            category: 'finance',
            sourceId: 'account',
          ),
          const AppAlert(
            key: 'b',
            title: 'Compte à vérifier',
            detail: 'Signal prioritaire',
            category: 'finance',
            sourceId: 'account',
            priority: HouseholdTaskPriority.urgent,
          ),
        ],
        calendar: [
          CalendarEntry(
            key: 'task',
            title: 'Faire les courses',
            date: fixtures.now,
            source: CalendarSource.task,
          ),
          CalendarEntry(
            key: 'tomorrow',
            title: 'Demain',
            date: fixtures.now.add(const Duration(days: 1)),
            source: CalendarSource.task,
          ),
        ],
      );
      expect(model.actions, hasLength(1));
      expect(model.actions.single.detail, 'Signal prioritaire');
      expect(model.today.map((item) => item.title), ['Faire les courses']);
      expect(
        CalendarSource.values.map((item) => item.name),
        isNot(contains('cycle')),
      );
    },
  );

  test('dashboard catalogue is complete in four languages', () {
    final expected = DashboardHomeWords.keysFor(AppLanguage.french);
    for (final language in AppLanguage.values) {
      expect(DashboardHomeWords.keysFor(language), expected);
    }
  });

  for (final count in [1, 2, 5]) {
    test('composition remains generic for $count household member(s)', () {
      final model = composeDashboardHome(
        snapshot: fixtures.snapshot(populated: true),
        now: fixtures.now,
        alerts: const [],
        calendar: [
          for (var index = 0; index < count; index++)
            CalendarEntry(
              key: 'member-$index',
              title: 'Tâche $index',
              date: fixtures.now,
              source: CalendarSource.task,
              assigneeUserId: 'member-$index',
            ),
        ],
      );
      expect(model.today, hasLength(count));
    });
  }

  for (final spec in [
    (name: 'mobile', size: const Size(390, 844), locale: const Locale('fr')),
    (name: 'tablet', size: const Size(820, 1180), locale: const Locale('fr')),
    (name: 'desktop', size: const Size(1440, 1000), locale: const Locale('fr')),
    (name: 'rtl', size: const Size(390, 844), locale: const Locale('ar')),
  ]) {
    testWidgets('cockpit ${spec.name} keeps the five-level hierarchy', (
      tester,
    ) async {
      tester.view.physicalSize = spec.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          locale: spec.locale,
          model: DashboardHomeModel(
            snapshot: fixtures.snapshot(populated: true),
            actions: const [
              AppAlert(
                key: 'financial:accounts:review',
                title: 'Compte à vérifier',
                detail: 'Un rapprochement demande votre attention.',
                category: 'finance',
                priority: HouseholdTaskPriority.high,
              ),
            ],
            today: [
              CalendarEntry(
                key: 'task',
                title: 'Préparer la semaine',
                date: fixtures.now,
                source: CalendarSource.task,
                sourceId: 'task',
              ),
            ],
            goals: fixtures
                .snapshot(populated: true)
                .activeGoals
                .take(2)
                .toList(),
            now: fixtures.now,
            memberName: 'Samira',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-situation')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-action-center')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-today')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-goals')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('dashboard-secondary-overview')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const Key('dashboard-secondary-overview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (spec.name == 'rtl') {
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('financial-dashboard-page'))),
          ),
          TextDirection.rtl,
        );
      }
    });
  }

  testWidgets(
    'empty and no-actions states guide without exposing hidden balances',
    (tester) async {
      await tester.pumpWidget(
        _app(
          locale: const Locale('fr'),
          model: DashboardHomeModel(
            snapshot: fixtures.snapshot(),
            actions: const [],
            today: const [],
            goals: const [],
            now: fixtures.now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard-v2-empty')), findsOneWidget);
      expect(find.textContaining('••••'), findsNothing);
      expect(find.textContaining('solde'), findsNothing);
    },
  );

  testWidgets(
    'partial sources are announced and private balance stays absent',
    (tester) async {
      final base = fixtures.snapshot(populated: true);
      final privateSnapshot = FinancialDashboardSnapshot(
        accounts: [
          fixtures.account(
            id: 'private',
            balance: 987654321,
            balanceVisible: false,
          ),
        ],
        ordinaryEnvelopes: base.ordinaryEnvelopes,
        toAllocate: base.toAllocate,
        budget: base.budget,
        monthlyFlow: base.monthlyFlow,
        debts: base.debts,
        incomeReceivables: base.incomeReceivables,
        recoveryReceivables: base.recoveryReceivables,
        activeGoals: base.activeGoals,
        nextPriority: base.nextPriority,
        alerts: base.alerts,
        report: base.report,
        history: base.history,
        reconciliations: base.reconciliations,
        activePlan: base.activePlan,
        availability: base.availability,
      );
      await tester.pumpWidget(
        _app(
          locale: const Locale('fr'),
          model: DashboardHomeModel(
            snapshot: privateSnapshot,
            actions: const [],
            today: const [],
            goals: privateSnapshot.activeGoals,
            now: fixtures.now,
            partial: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Certaines informations sont temporairement indisponibles.'),
        findsOneWidget,
      );
      expect(find.textContaining('9 876 543'), findsNothing);
      expect(find.textContaining('9876543'), findsNothing);
    },
  );
}

Widget _app({required Locale locale, required DashboardHomeModel model}) =>
    ProviderScope(
      overrides: [dashboardHomeProvider.overrideWith((ref) async => model)],
      child: MaterialApp(
        locale: locale,
        supportedLocales: const [
          Locale('fr'),
          Locale('en'),
          Locale('ar'),
          Locale('ar', 'MA'),
        ],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: FinancialDashboardPage()),
      ),
    );
