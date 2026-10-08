import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/organization/domain/organization_models.dart';

void main() {
  test('monthly recurrence clamps month end and yearly handles leap day', () {
    expect(
      nextOccurrence(DateTime(2026, 1, 31), TaskRecurrence.monthly),
      DateTime(2026, 2, 28),
    );
    expect(
      nextOccurrence(DateTime(2028, 2, 29), TaskRecurrence.yearly),
      DateTime(2029, 2, 28),
    );
  });

  test('only active dated tasks can be overdue', () {
    final task = HouseholdTask(
      id: 't',
      householdId: 'h',
      title: 'Assurance',
      priority: HouseholdTaskPriority.high,
      status: HouseholdTaskStatus.todo,
      recurrence: TaskRecurrence.yearly,
      createdBy: 'u',
      createdAt: DateTime(2026),
      dueDate: DateTime(2026, 10, 1),
    );
    expect(task.isOverdue(DateTime(2026, 10, 8)), isTrue);
  });

  test('calendar filters compose and keep household-wide entries', () {
    final entries = [
      CalendarEntry(
        key: 'member',
        title: 'Member task',
        date: DateTime(2026, 10, 10),
        source: CalendarSource.task,
        assigneeUserId: 'a',
      ),
      CalendarEntry(
        key: 'household',
        title: 'Household due date',
        date: DateTime(2026, 10, 11),
        source: CalendarSource.obligation,
      ),
      CalendarEntry(
        key: 'done',
        title: 'Done',
        date: DateTime(2026, 10, 12),
        source: CalendarSource.task,
        assigneeUserId: 'b',
        status: CalendarEntryStatus.resolved,
      ),
    ];
    final filtered = filterCalendarEntries(
      entries,
      memberId: 'a',
      status: CalendarEntryStatus.active,
      period: CalendarPeriod.currentMonth,
      now: DateTime(2026, 10, 8),
    );
    expect(filtered.map((e) => e.key), ['member', 'household']);
  });
}
