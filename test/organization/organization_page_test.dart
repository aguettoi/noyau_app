import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:noyau_app/features/organization/application/organization_provider.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';
import 'package:noyau_app/features/organization/presentation/organization_page.dart';

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
        ],
        child: const MaterialApp(home: OrganizationPage()),
      ),
    );
    await tester.pumpAndSettle();
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
}
