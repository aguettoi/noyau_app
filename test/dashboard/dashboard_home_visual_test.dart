import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/app/fp_adaptive_navigation.dart';
import 'package:noyau_app/core/theme/noyau_theme.dart';
import 'package:noyau_app/features/dashboard/application/providers/dashboard_home_provider.dart';
import 'package:noyau_app/features/dashboard/presentation/financial_dashboard_page.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';

import 'dashboard_v2_test.dart' as fixtures;

void main() {
  final specs =
      <({String name, Size size, Locale locale, ThemeMode mode, String state})>[
        (
          name: 'desktop',
          size: const Size(1440, 1000),
          locale: const Locale('fr'),
          mode: ThemeMode.light,
          state: 'full',
        ),
        (
          name: 'mobile',
          size: const Size(390, 844),
          locale: const Locale('fr'),
          mode: ThemeMode.light,
          state: 'full',
        ),
        (
          name: 'tablet',
          size: const Size(820, 1100),
          locale: const Locale('fr'),
          mode: ThemeMode.light,
          state: 'full',
        ),
        (
          name: 'dark',
          size: const Size(1440, 1000),
          locale: const Locale('fr'),
          mode: ThemeMode.dark,
          state: 'full',
        ),
        (
          name: 'rtl',
          size: const Size(390, 844),
          locale: const Locale('ar'),
          mode: ThemeMode.light,
          state: 'full',
        ),
        (
          name: 'empty',
          size: const Size(390, 844),
          locale: const Locale('fr'),
          mode: ThemeMode.light,
          state: 'empty',
        ),
        (
          name: 'no_actions',
          size: const Size(820, 1100),
          locale: const Locale('fr'),
          mode: ThemeMode.light,
          state: 'no-actions',
        ),
      ];

  for (final spec in specs) {
    testWidgets('D1.2-B visual ${spec.name}', (tester) async {
      tester.view.physicalSize = spec.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final full = fixtures.snapshot(populated: true);
      final empty = fixtures.snapshot();
      final model = DashboardHomeModel(
        snapshot: spec.state == 'empty' ? empty : full,
        actions: spec.state == 'full'
            ? const [
                AppAlert(
                  key: 'financial:budget:overspent',
                  title: 'Budget à vérifier',
                  detail: 'Une enveloppe demande votre attention.',
                  category: 'finance',
                  priority: HouseholdTaskPriority.high,
                ),
                AppAlert(
                  key: 'task:week',
                  title: 'Préparer la semaine',
                  detail: 'Une tâche est prévue aujourd’hui.',
                  category: 'tasks',
                ),
              ]
            : const [],
        today: spec.state == 'empty'
            ? const []
            : [
                CalendarEntry(
                  key: 'today',
                  title: 'Renouveler l’assurance',
                  date: fixtures.now,
                  source: CalendarSource.task,
                  sourceId: 'task',
                ),
              ],
        goals: spec.state == 'empty'
            ? const []
            : full.activeGoals.take(2).toList(),
        now: fixtures.now,
        memberName: 'Samira',
      );
      await tester.pumpWidget(
        _app(
          locale: spec.locale,
          mode: spec.mode,
          child: ProviderScope(
            overrides: [
              dashboardHomeProvider.overrideWith((ref) async => model),
            ],
            child: const RepaintBoundary(
              key: Key('proof'),
              child: Scaffold(body: FinancialDashboardPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('proof')),
        matchesGoldenFile('goldens/d12b_dashboard_${spec.name}.png'),
      );
    });
  }

  testWidgets('D1.2-B visual add sheet', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        child: RepaintBoundary(
          key: const Key('proof'),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: FpUniversalAddSheet(
                universe: FpUniverse.home,
                actions: [
                  for (final item in const [
                    ('expense', Icons.remove_circle_outline),
                    ('income', Icons.add_circle_outline),
                    ('transfer', Icons.swap_horiz),
                    ('debt', Icons.request_quote_outlined),
                    ('receivable', Icons.payments_outlined),
                    ('task', Icons.task_alt),
                    ('grocery', Icons.shopping_cart_outlined),
                    ('event', Icons.event_outlined),
                    ('goal', Icons.flag_outlined),
                    ('priority', Icons.low_priority),
                  ])
                    FpAddAction(item.$1, item.$2, () {}),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('proof')),
      matchesGoldenFile('goldens/d12b_dashboard_add_sheet.png'),
    );
  });
}

Widget _app({
  Widget? child,
  Locale locale = const Locale('fr'),
  ThemeMode mode = ThemeMode.light,
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [
    Locale('fr'),
    Locale('en'),
    Locale('ar'),
    Locale('ar', 'MA'),
  ],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: NoyauTheme.light,
  darkTheme: NoyauTheme.dark,
  themeMode: mode,
  home: child,
);
