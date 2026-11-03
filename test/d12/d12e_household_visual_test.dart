import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/localization/app_locale.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/organization/application/daily_life_provider.dart';
import 'package:noyau_app/features/organization/application/organization_provider.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';
import 'package:noyau_app/features/organization/presentation/daily_life_page.dart';
import 'package:noyau_app/features/organization/presentation/organization_page.dart';
import 'package:noyau_app/features/recurring_finance/application/recurring_finance_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!Platform.isWindows) return;
    final bytes = await File(r'C:\Windows\Fonts\tahoma.ttf').readAsBytes();
    final loader = FontLoader('D12EArabic')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  final proofs = <_Proof>[
    const _Proof('01_hub_desktop', false, 0, Size(1280, 800)),
    const _Proof('02_hub_mobile', false, 0, Size(390, 844)),
    const _Proof('03_today', false, 0, Size(900, 760)),
    const _Proof('04_tasks_desktop', false, 1, Size(1280, 800)),
    const _Proof('05_tasks_mobile', false, 1, Size(390, 844)),
    const _Proof('06_task_creation', false, 1, Size(900, 760)),
    const _Proof('07_groceries', true, 0, Size(900, 760)),
    const _Proof('08_add_grocery', true, 0, Size(390, 844)),
    const _Proof('09_grocery_to_finance', true, 0, Size(900, 760)),
    const _Proof('10_calendar', false, 2, Size(1000, 760)),
    const _Proof('11_home_vehicles', true, 1, Size(1000, 760)),
    const _Proof('12_maintenance', true, 1, Size(390, 844)),
    const _Proof('13_contracts_warranties', true, 1, Size(900, 760)),
    const _Proof('14_routines', false, 1, Size(900, 760)),
    const _Proof('15_reminder_20h', false, 3, Size(900, 760)),
    const _Proof('16_personal_space', true, 2, Size(900, 760)),
    const _Proof('17_cycle_private', true, 2, Size(390, 844)),
    const _Proof('18_cycle_entry', true, 2, Size(900, 760)),
    const _Proof('19_cycle_limited_share', true, 2, Size(900, 760)),
    const _Proof('20_cycle_revocation', true, 2, Size(390, 844)),
    const _Proof('21_one_member', false, 0, Size(900, 760)),
    const _Proof('22_five_members', false, 1, Size(1100, 760)),
    const _Proof('23_dark', false, 0, Size(900, 760), dark: true),
    const _Proof('24_rtl_arabic', true, 2, Size(900, 760), arabic: true),
    const _Proof('25_empty', true, 0, Size(390, 844), empty: true),
  ];

  for (final proof in proofs) {
    testWidgets('D1.2-E runtime proof ${proof.name}', (tester) async {
      await _pumpProof(tester, proof);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('runtime_goldens/d12e_${proof.name}.png'),
      );
    });
  }
}

Future<void> _pumpProof(WidgetTester tester, _Proof proof) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = proof.size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final language = proof.arabic ? AppLanguage.arabic : AppLanguage.french;
  final now = DateTime(2026, 11, 3, 10);
  final task = HouseholdTask(
    id: 'task-1',
    householdId: 'household',
    title: 'Préparer le rendez-vous',
    priority: HouseholdTaskPriority.high,
    status: HouseholdTaskStatus.todo,
    recurrence: TaskRecurrence.weekly,
    createdBy: 'owner',
    createdAt: now,
    dueDate: now,
  );
  final app = ProviderScope(
    overrides: [
      appLocaleProvider.overrideWith(
        (ref) =>
            AppLocaleController(environmentLocales: () => [language.locale]),
      ),
      currentUserIdProvider.overrideWithValue('owner'),
      remoteHouseholdMembersProvider.overrideWith((ref) async => const []),
      householdTasksProvider.overrideWith((ref) async => [task]),
      organizationClockProvider.overrideWithValue(now),
      organizationCalendarProvider.overrideWith(
        (ref) async => [
          CalendarEntry(
            key: 'task:task-1',
            title: task.title,
            date: now,
            source: CalendarSource.task,
            sourceId: task.id,
          ),
          CalendarEntry(
            key: 'home:maintenance',
            title: 'Entretien annuel',
            date: now.add(const Duration(days: 2)),
            source: CalendarSource.homeAuto,
            sourceId: 'home-1',
          ),
        ],
      ),
      organizationAlertsProvider.overrideWith(
        (ref) async => const [
          AppAlert(
            key: 'daily-reminder',
            title: 'Rappel quotidien 20:00',
            detail: 'Fait · Pas encore (+15 min)',
            category: 'reminders',
          ),
        ],
      ),
      recurringIntentionsProvider.overrideWith((ref) async => const []),
      expectedOccurrencesProvider.overrideWith((ref) async => const []),
      actualRecurringCandidatesProvider.overrideWith((ref) async => const []),
      groceryItemsProvider.overrideWith(
        (ref) async => proof.empty
            ? const []
            : const [
                {
                  'id': 'grocery-1',
                  'label': 'Lait',
                  'quantity': 2,
                  'unit': 'L',
                  'status': 'needed',
                },
              ],
      ),
      homeRecordsProvider.overrideWith(
        (ref) async => const [
          {
            'id': 'home-1',
            'label': 'Climatisation',
            'kind': 'maintenance',
            'provider': 'Service maison',
            'due_on': '2026-11-21',
          },
        ],
      ),
      ownCycleEventsProvider.overrideWith(
        (ref) async => const [
          {
            'id': 'cycle-1',
            'phase': 'cycle',
            'starts_on': '2026-11-01',
            'ends_on': '2026-11-05',
          },
        ],
      ),
      ownCycleSharesProvider.overrideWith((ref) async => const {}),
      businessCategoriesProvider.overrideWith((ref) async => const []),
    ],
    child: MaterialApp(
      locale: language.locale,
      supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(fontFamily: 'D12EArabic'),
      darkTheme: ThemeData.dark().copyWith(
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'D12EArabic'),
      ),
      themeMode: proof.dark ? ThemeMode.dark : ThemeMode.light,
      home: proof.daily ? const DailyLifePage() : const OrganizationPage(),
    ),
  );
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  if (proof.tab > 0) {
    if (proof.size.width < 600) {
      await tester.drag(find.byType(TabBar), const Offset(-240, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byType(Tab).at(proof.tab), warnIfMissed: false);
    await tester.pumpAndSettle();
  }
  if (proof.name == '06_task_creation') {
    await tester.tap(find.byKey(const Key('add-household-task')));
    await tester.pumpAndSettle();
  }
  if (proof.name == '08_add_grocery' || proof.name == '18_cycle_entry') {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }
}

class _Proof {
  const _Proof(
    this.name,
    this.daily,
    this.tab,
    this.size, {
    this.dark = false,
    this.arabic = false,
    this.empty = false,
  });

  final String name;
  final bool daily;
  final int tab;
  final Size size;
  final bool dark;
  final bool arabic;
  final bool empty;
}
