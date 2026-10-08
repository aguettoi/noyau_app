import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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
    final task = HouseholdTask(
      id: 'task-1',
      householdId: 'h',
      title: 'Renouveler assurance',
      priority: HouseholdTaskPriority.high,
      status: HouseholdTaskStatus.todo,
      recurrence: TaskRecurrence.yearly,
      createdBy: 'u',
      createdAt: DateTime(2026),
      dueDate: DateTime(2026, 10, 10),
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
    await tester.tap(find.text('Alertes'));
    await tester.pumpAndSettle();
    expect(find.text('Tâche en retard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
