enum HouseholdTaskStatus { todo, inProgress, completed, cancelled }

enum HouseholdTaskPriority { low, normal, high, urgent }

enum TaskRecurrence { none, daily, weekly, monthly, yearly }

class HouseholdTask {
  const HouseholdTask({
    required this.id,
    required this.householdId,
    required this.title,
    required this.priority,
    required this.status,
    required this.recurrence,
    required this.createdBy,
    required this.createdAt,
    this.description,
    this.assigneeUserId,
    this.dueDate,
    this.sourceModule,
    this.sourceId,
  });
  final String id;
  final String householdId;
  final String title;
  final String? description;
  final String? assigneeUserId;
  final DateTime? dueDate;
  final HouseholdTaskPriority priority;
  final HouseholdTaskStatus status;
  final TaskRecurrence recurrence;
  final String createdBy;
  final DateTime createdAt;
  final String? sourceModule;
  final String? sourceId;

  bool get isActive =>
      status == HouseholdTaskStatus.todo ||
      status == HouseholdTaskStatus.inProgress;
  bool isOverdue(DateTime today) =>
      isActive &&
      dueDate != null &&
      dateOnly(dueDate!).isBefore(dateOnly(today));
}

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime nextOccurrence(DateTime from, TaskRecurrence recurrence) =>
    switch (recurrence) {
      TaskRecurrence.daily => DateTime(from.year, from.month, from.day + 1),
      TaskRecurrence.weekly => DateTime(from.year, from.month, from.day + 7),
      TaskRecurrence.monthly => _sameDayNextMonth(from),
      TaskRecurrence.yearly => _sameDayNextYear(from),
      TaskRecurrence.none => dateOnly(from),
    };

DateTime _sameDayNextMonth(DateTime from) {
  final first = DateTime(from.year, from.month + 1);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, from.day.clamp(1, last));
}

DateTime _sameDayNextYear(DateTime from) {
  final last = DateTime(from.year + 1, from.month + 1, 0).day;
  return DateTime(from.year + 1, from.month, from.day.clamp(1, last));
}

enum CalendarSource {
  task,
  budget,
  obligation,
  compensation,
  reconciliation,
  goal,
  priority,
  shopping,
  homeAuto,
  investment,
}

enum CalendarEntryStatus { active, resolved, cancelled }

enum CalendarPeriod { all, today, nextSevenDays, currentMonth, custom }

class CalendarEntry {
  const CalendarEntry({
    required this.key,
    required this.title,
    required this.date,
    required this.source,
    this.assigneeUserId,
    this.sourceId,
    this.detail,
    this.status = CalendarEntryStatus.active,
  });
  final String key;
  final String title;
  final DateTime date;
  final CalendarSource source;
  final String? assigneeUserId;
  final String? sourceId;
  final String? detail;
  final CalendarEntryStatus status;
}

class AppAlert {
  const AppAlert({
    required this.key,
    required this.title,
    required this.detail,
    required this.category,
    this.read = false,
    this.source,
    this.sourceId,
  });
  final String key;
  final String title;
  final String detail;
  final String category;
  final bool read;
  final CalendarSource? source;
  final String? sourceId;
}

List<CalendarEntry> filterCalendarEntries(
  Iterable<CalendarEntry> entries, {
  CalendarSource? source,
  String? memberId,
  CalendarEntryStatus? status,
  CalendarPeriod period = CalendarPeriod.all,
  DateTime? now,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final today = dateOnly(now ?? DateTime.now());
  bool inPeriod(DateTime raw) {
    final date = dateOnly(raw);
    return switch (period) {
      CalendarPeriod.all => true,
      CalendarPeriod.today => date == today,
      CalendarPeriod.nextSevenDays =>
        !date.isBefore(today) &&
            !date.isAfter(today.add(const Duration(days: 7))),
      CalendarPeriod.currentMonth =>
        date.year == today.year && date.month == today.month,
      CalendarPeriod.custom =>
        customStart != null &&
            customEnd != null &&
            !date.isBefore(dateOnly(customStart)) &&
            !date.isAfter(dateOnly(customEnd)),
    };
  }

  return entries
      .where((entry) => source == null || entry.source == source)
      // Household-wide entries remain visible when filtering a member.
      .where(
        (entry) =>
            memberId == null ||
            entry.assigneeUserId == null ||
            entry.assigneeUserId == memberId,
      )
      .where((entry) => status == null || entry.status == status)
      .where((entry) => inPeriod(entry.date))
      .toList(growable: false)
    ..sort((a, b) => a.date.compareTo(b.date));
}
