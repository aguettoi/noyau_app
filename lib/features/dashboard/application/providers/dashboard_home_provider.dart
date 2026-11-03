import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../finance/application/providers/remote_household_members_provider.dart';
import '../../../finance/application/providers/supabase_client_provider.dart';
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
  });

  final FinancialDashboardSnapshot snapshot;
  final List<AppAlert> actions;
  final List<CalendarEntry> today;
  final List<SavingsGoalProgress> goals;
  final DateTime now;
  final String? memberName;
  final bool partial;
}

final dashboardHomeProvider = FutureProvider<DashboardHomeModel>((ref) async {
  final snapshot = await ref.watch(financialDashboardProvider.future);
  final now = ref.watch(dashboardClockProvider);
  var partial = false;

  List<AppAlert> alerts = const [];
  try {
    alerts = await ref.watch(organizationAlertsProvider.future);
  } catch (_) {
    partial = true;
  }

  List<CalendarEntry> calendar = const [];
  try {
    calendar = await ref.watch(organizationCalendarProvider.future);
  } catch (_) {
    partial = true;
  }

  String? memberName;
  try {
    final userId = ref.watch(currentUserIdProvider);
    final members = await ref.watch(remoteHouseholdMembersProvider.future);
    memberName = members
        .where((member) => member.id == userId)
        .firstOrNull
        ?.displayName;
  } catch (_) {
    partial = true;
  }

  return composeDashboardHome(
    snapshot: snapshot,
    alerts: alerts,
    calendar: calendar,
    now: now,
    memberName: memberName,
    partial: partial,
  );
});

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
  );
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
