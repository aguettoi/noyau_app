import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../finance/application/providers/remote_household_members_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
import '../../../finance/domain/household_member.dart';
import '../../../organization/application/organization_provider.dart';
import '../../../organization/domain/organization_models.dart';
import '../../../savings_goals/domain/savings_goal.dart';
import 'dashboard_history_provider.dart';
import 'remote_financial_dashboard_provider.dart';

class DashboardHomeModel {
  const DashboardHomeModel({
    required this.snapshot,
    required this.actions,
    required this.today,
    required this.goals,
    required this.now,
    this.memberName,
    this.partial = false,
    this.cycleHighlights = const [],
  });

  final FinancialDashboardSnapshot snapshot;
  final List<AppAlert> actions;
  final List<CalendarEntry> today;
  final List<SavingsGoalProgress> goals;
  final DateTime now;
  final String? memberName;
  final bool partial;
  final List<CalendarEntry> cycleHighlights;
}

final dashboardHomeProvider = FutureProvider<DashboardHomeModel>((ref) async {
  // Start the mandatory snapshot and the secondary home sources together.
  // The previous sequence made alerts, calendar and member name wait for the
  // whole financial snapshot even though none depends on it.
  final snapshotFuture = ref.watch(financialDashboardProvider.future);
  final alertsFuture = _optional(
    ref.watch(organizationAlertsProvider.future),
    const <AppAlert>[],
  );
  final calendarFuture = _optional(
    ref.watch(organizationCalendarProvider.future),
    const <CalendarEntry>[],
  );
  final membersFuture = _optional(
    ref.watch(remoteHouseholdMembersProvider.future),
    const <HouseholdMember>[],
  );

  final snapshot = await snapshotFuture;
  final alertsResult = await alertsFuture;
  final calendarResult = await calendarFuture;
  final membersResult = await membersFuture;
  final now = ref.watch(dashboardClockProvider);
  final partial =
      alertsResult.failed || calendarResult.failed || membersResult.failed;

  String? memberName;
  if (!membersResult.failed) {
    final userId = ref.watch(currentUserIdProvider);
    memberName = membersResult.value
        .where((member) => member.id == userId)
        .firstOrNull
        ?.displayName;
  }

  return composeDashboardHome(
    snapshot: snapshot,
    alerts: alertsResult.value,
    calendar: calendarResult.value,
    now: now,
    memberName: memberName,
    partial: partial,
  );
});

Future<_OptionalResult<T>> _optional<T>(Future<T> future, T fallback) async {
  try {
    return _OptionalResult(value: await future, failed: false);
  } catch (_) {
    return _OptionalResult(value: fallback, failed: true);
  }
}

class _OptionalResult<T> {
  const _OptionalResult({required this.value, required this.failed});

  final T value;
  final bool failed;
}

DashboardHomeModel composeDashboardHome({
  required FinancialDashboardSnapshot snapshot,
  required Iterable<AppAlert> alerts,
  required Iterable<CalendarEntry> calendar,
  required DateTime now,
  String? memberName,
  bool partial = false,
}) {
  final deduplicated = <String, AppAlert>{};
  for (final alert in alerts.where((item) => !item.read)) {
    final semanticKey =
        '${alert.category}|${alert.title.trim()}|${alert.sourceId ?? ''}';
    final current = deduplicated[semanticKey];
    if (current == null || _priority(alert) > _priority(current)) {
      deduplicated[semanticKey] = alert;
    }
  }
  final actions = deduplicated.values.toList()
    ..sort((a, b) {
      final priority = _priority(b).compareTo(_priority(a));
      if (priority != 0) return priority;
      final due = (a.dueAt ?? DateTime(9999)).compareTo(
        b.dueAt ?? DateTime(9999),
      );
      return due != 0 ? due : a.title.compareTo(b.title);
    });

  final day = DateTime(now.year, now.month, now.day);
  final today =
      calendar
          .where((entry) => entry.status == CalendarEntryStatus.active)
          .where((entry) {
            final date = entry.date.toLocal();
            return DateTime(date.year, date.month, date.day) == day;
          })
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));

  final goals = snapshot.activeGoals.toList()
    ..sort((a, b) {
      final priority = a.goal.priority.compareTo(b.goal.priority);
      return priority != 0
          ? priority
          : b.progressRatio.compareTo(a.progressRatio);
    });

  return DashboardHomeModel(
    snapshot: snapshot,
    actions: List.unmodifiable(actions.take(5)),
    today: List.unmodifiable(today.take(5)),
    goals: List.unmodifiable(goals.take(3)),
    now: now,
    memberName: memberName?.trim().isEmpty == true ? null : memberName?.trim(),
    partial: partial,
    cycleHighlights: _cycleHighlights(calendar, day),
  );
}

List<CalendarEntry> _cycleHighlights(
  Iterable<CalendarEntry> calendar,
  DateTime day,
) {
  final horizon = day.add(const Duration(days: 30));
  final items =
      calendar
          .where((entry) => entry.source == CalendarSource.cycle)
          .where(
            (entry) =>
                !entry.date.isBefore(day) && !entry.date.isAfter(horizon) ||
                (entry.endDate != null && !entry.endDate!.isBefore(day)),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  return List.unmodifiable(items.take(2));
}

int _priority(AppAlert alert) => switch (alert.priority) {
  HouseholdTaskPriority.urgent => 4,
  HouseholdTaskPriority.high => 3,
  HouseholdTaskPriority.normal => 2,
  HouseholdTaskPriority.low => 1,
};

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
