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
}
