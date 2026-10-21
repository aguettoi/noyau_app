import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:noyau_app/features/organization/application/organization_provider.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';
import 'package:noyau_app/features/organization/presentation/organization_page.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/recurring_finance/application/recurring_finance_provider.dart';

void main() {
  testWidgets('tasks calendar and alerts stay usable on mobile', (
    tester,
  ) async {
    await initializeDateFormatting('fr');
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, 10);
    final task = HouseholdTask(
      id: 'task-1',
      householdId: 'h',
      title: 'Renouveler assurance',
      priority: HouseholdTaskPriority.high,
      status: HouseholdTaskStatus.todo,
      recurrence: TaskRecurrence.yearly,
      createdBy: 'u',
      createdAt: DateTime(2026),
      dueDate: due,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdTasksProvider.overrideWith((ref) async => [task]),
          organizationCalendarProvider.overrideWith(
            (ref) async => [
              CalendarEntry(
                key: 'task:task-1',
                title: task.title,
                date: task.dueDate!,
                source: CalendarSource.task,
                sourceId: task.id,
              ),
            ],
          ),
          organizationAlertsProvider.overrideWith(
            (ref) async => const [
              AppAlert(
                key: 'a',
                title: 'Tâche en retard',
                detail: 'À traiter',
                category: 'tasks',
              ),
            ],
          ),
          remoteHouseholdMembersProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: OrganizationPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Opérations attendues'), findsOneWidget);
    expect(find.text('Prévisions de trésorerie'), findsOneWidget);
    expect(find.text('Renouveler assurance'), findsOneWidget);
    await tester.tap(find.text('Calendrier'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-entry-task:task-1')), findsOneWidget);
    await tester.tap(find.text('Mois'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('calendar-next-month')), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendar-next-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-previous-month')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-current-month')));
    await tester.pumpAndSettle();
    final dueDay = find.byKey(
      Key('calendar-day-${DateFormat('yyyy-MM-dd').format(due)}'),
    );
    await tester.ensureVisible(dueDay);
    await tester.tap(dueDay);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('month-entry-task:task-1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('calendar-reset-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alertes'));
    await tester.pumpAndSettle();
    expect(find.text('Tâche en retard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the recurring finance entry is visible and opens R3.1', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdTasksProvider.overrideWith((ref) async => const []),
          organizationCalendarProvider.overrideWith((ref) async => const []),
          organizationAlertsProvider.overrideWith((ref) async => const []),
          remoteHouseholdMembersProvider.overrideWith((ref) async => const []),
          recurringIntentionsProvider.overrideWith((ref) async => const []),
          expectedOccurrencesProvider.overrideWith((ref) async => const []),
          actualRecurringCandidatesProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        child: const MaterialApp(home: OrganizationPage()),
      ),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('open-recurring-finance-visible'));
    expect(entry, findsOneWidget);
    expect(find.text('Opérations attendues'), findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.text('Opérations attendues'), findsOneWidget);
    expect(find.text('Récurrences'), findsOneWidget);
    expect(find.text('Prochaines occurrences'), findsOneWidget);
  });

  testWidgets('un snooze réussi masque immédiatement le rappel', (
    tester,
  ) async {
    var visible = true;
    late _FakeOrganizationActions actions;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdTasksProvider.overrideWith((ref) async => const []),
          organizationCalendarProvider.overrideWith((ref) async => const []),
          userTimezoneProvider.overrideWith((ref) async => 'Africa/Casablanca'),
          organizationAlertsProvider.overrideWith(
            (ref) async => visible
                ? const [
                    AppAlert(
                      key: 'r3.1:test:day',
                      title: 'TEST SNOOZE',
                      detail: '1,00 MAD',
                      category: 'reminders',
                    ),
                  ]
                : const [],
          ),
          organizationActionsProvider.overrideWith((ref) {
            actions = _FakeOrganizationActions(
              onSnooze: (_, _, _) async {
                visible = false;
                ref.invalidate(organizationAlertsProvider);
              },
            );
            return actions;
          }),
          remoteHouseholdMembersProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: OrganizationPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alertes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions du rappel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plus tard aujourd’hui'));
    await tester.pumpAndSettle();
    expect(actions.snoozeCalls, 1);
    expect(actions.lastUntil!.isAfter(DateTime.now().toUtc()), isTrue);
    expect(find.text('TEST SNOOZE'), findsNothing);
    // The policy may roll a late-evening action to tomorrow morning.
    expect(
      find.textContaining(RegExp('rappel reporté', caseSensitive: false)),
      findsOneWidget,
    );
  });

  testWidgets('un refus RPC reste visible et affiche une erreur', (
    tester,
  ) async {
    final actions = _FakeOrganizationActions(
      onSnooze: (_, _, _) => throw Exception('refus serveur'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdTasksProvider.overrideWith((ref) async => const []),
          organizationCalendarProvider.overrideWith((ref) async => const []),
          userTimezoneProvider.overrideWith((ref) async => 'Africa/Casablanca'),
          organizationAlertsProvider.overrideWith(
            (ref) async => const [
              AppAlert(
                key: 'r3.1:test:day',
                title: 'TEST SNOOZE',
                detail: '1,00 MAD',
                category: 'reminders',
              ),
            ],
          ),
          organizationActionsProvider.overrideWithValue(actions),
          remoteHouseholdMembersProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: OrganizationPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alertes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Actions du rappel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plus tard aujourd’hui'));
    await tester.pumpAndSettle();
    expect(find.text('TEST SNOOZE'), findsOneWidget);
    expect(find.textContaining('Impossible de reporter'), findsOneWidget);
  });
}

class _FakeOrganizationActions implements OrganizationActionsApi {
  _FakeOrganizationActions({required this.onSnooze});

  final Future<void> Function(String, DateTime, bool) onSnooze;
  int snoozeCalls = 0;
  DateTime? lastUntil;

  @override
  Future<void> snooze(String key, DateTime until, {bool notYet = false}) async {
    snoozeCalls++;
    lastUntil = until;
    await onSnooze(key, until, notYet);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
