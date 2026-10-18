import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dashboard/application/providers/remote_financial_dashboard_provider.dart';
import '../../budget_intelligence/application/providers/remote_budget_provider.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/remote_debts_provider.dart';
import '../../finance/application/providers/member_compensations_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../shopping_list/application/providers/remote_shopping_list_provider.dart';
import '../../wealth/application/providers/home_auto_provider.dart';
import '../../cashflow_projection/application/cashflow_projection_provider.dart';
import '../domain/organization_models.dart';

abstract interface class OrganizationGateway {
  Future<List<HouseholdTask>> fetchTasks(String householdId);
  Future<void> createTask(
    String householdId,
    String userId,
    Map<String, Object?> values,
  );
  Future<void> completeTask(
    String taskId,
    String outcome,
    String note,
    String idempotencyKey,
  );
  Future<Set<String>> fetchReadAlertKeys(String householdId, String userId);
  Future<Map<String, UserAlertState>> fetchAlertStates(
    String householdId,
    String userId,
  );
  Future<List<AppAlert>> fetchReminders(String householdId, String userId);
  Future<void> actOnReminder(
    String householdId,
    String key,
    String action,
    DateTime? until,
    String idempotencyKey,
  );
  Future<List<ReminderRule>> fetchReminderRules(String householdId);
  Future<void> saveReminderRule(
    String householdId,
    String userId,
    ReminderRule rule,
  );
  Future<void> markAlertRead(String householdId, String userId, String key);
  Future<Map<String, bool>> fetchPreferences(String householdId, String userId);
  Future<void> setPreference(
    String householdId,
    String userId,
    String category,
    bool enabled,
  );
}

class SupabaseOrganizationGateway implements OrganizationGateway {
  SupabaseOrganizationGateway(this.client);
  final SupabaseClient client;
  @override
  Future<List<HouseholdTask>> fetchTasks(String householdId) async {
    final rows = await client
        .from('household_tasks')
        .select()
        .eq('household_id', householdId)
        .order('due_date', ascending: true)
        .order('created_at', ascending: true);
    return [
      for (final raw in rows as List<dynamic>)
        _task(Map<String, Object?>.from(raw as Map)),
    ];
  }

  @override
  Future<void> createTask(
    String householdId,
    String userId,
    Map<String, Object?> values,
  ) async {
    await client.from('household_tasks').insert({
      ...values,
      'household_id': householdId,
      'created_by': userId,
    });
  }

  @override
  Future<void> completeTask(
    String taskId,
    String outcome,
    String note,
    String idempotencyKey,
  ) => client.rpc(
    'complete_household_task',
    params: {
      'p_task_id': taskId,
      'p_outcome': outcome,
      'p_note': note,
      'p_idempotency_key': idempotencyKey,
    },
  );
  @override
  Future<Set<String>> fetchReadAlertKeys(
    String householdId,
    String userId,
  ) async {
    final rows = await client
        .from('user_alert_states')
        .select('alert_key')
        .eq('household_id', householdId)
        .eq('user_id', userId)
        .not('read_at', 'is', null);
    return {
      for (final raw in rows as List<dynamic>)
        (raw as Map)['alert_key'] as String,
    };
  }

  @override
  Future<Map<String, UserAlertState>> fetchAlertStates(
    String householdId,
    String userId,
  ) async {
    final rows = await client
        .from('user_alert_states')
        .select('alert_key,read_at,dismissed_at,snoozed_until,last_action')
        .eq('household_id', householdId)
        .eq('user_id', userId);
    return {
      for (final raw in rows as List<dynamic>)
        (raw as Map)['alert_key'] as String: _alertState(
          Map<String, Object?>.from(raw),
        ),
    };
  }

  @override
  Future<List<AppAlert>> fetchReminders(
    String householdId,
    String userId,
  ) async {
    final rows = await client
        .from('financial_reminders')
        .select()
        .eq('household_id', householdId)
        .eq('status', 'active')
        .lte('due_at', DateTime.now().toUtc().toIso8601String())
        .order('due_at', ascending: true);
    return [
      for (final raw in rows as List<dynamic>)
        _reminder(Map<String, Object?>.from(raw as Map)),
    ];
  }

  @override
  Future<void> actOnReminder(
    String householdId,
    String key,
    String action,
    DateTime? until,
    String idempotencyKey,
  ) => client.rpc(
    'act_on_financial_reminder',
    params: {
      'p_household_id': householdId,
      'p_alert_key': key,
      'p_action': action,
      'p_snoozed_until': until?.toUtc().toIso8601String(),
      'p_idempotency_key': idempotencyKey,
    },
  );

  @override
  Future<List<ReminderRule>> fetchReminderRules(String householdId) async {
    final rows = await client
        .from('reminder_rules')
        .select()
        .eq('household_id', householdId)
        .order('rule_type', ascending: true);
    return [
      for (final raw in rows as List<dynamic>)
        _rule(Map<String, Object?>.from(raw as Map)),
    ];
  }

  @override
  Future<void> saveReminderRule(
    String householdId,
    String userId,
    ReminderRule rule,
  ) async {
    await client.from('reminder_rules').upsert({
      'household_id': householdId,
      'recipient_user_id': userId,
      'rule_type': rule.type,
      'enabled': rule.enabled,
      'priority': rule.priority.name,
      'parameters': rule.parameters,
      'source_kind': rule.type,
      'created_by': userId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'household_id,recipient_user_id,rule_type');
  }

  @override
  Future<void> markAlertRead(
    String householdId,
    String userId,
    String key,
  ) async {
    await client.from('user_alert_states').upsert({
      'household_id': householdId,
      'user_id': userId,
      'alert_key': key,
      'read_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @override
  Future<Map<String, bool>> fetchPreferences(
    String householdId,
    String userId,
  ) async {
    final rows = await client
        .from('notification_preferences')
        .select('category,in_app_enabled')
        .eq('household_id', householdId)
        .eq('user_id', userId);
    return {
      for (final raw in rows as List<dynamic>)
        (raw as Map)['category'] as String: (raw)['in_app_enabled'] as bool,
    };
  }

  @override
  Future<void> setPreference(
    String householdId,
    String userId,
    String category,
    bool enabled,
  ) async {
    await client.from('notification_preferences').upsert({
      'household_id': householdId,
      'user_id': userId,
      'category': category,
      'in_app_enabled': enabled,
      'native_enabled': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

final organizationGatewayProvider = Provider<OrganizationGateway>(
  (ref) => SupabaseOrganizationGateway(ref.watch(supabaseClientProvider)),
);
final householdTasksProvider = FutureProvider<List<HouseholdTask>>((ref) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  if (household.householdId == null) throw StateError('Aucun foyer actif.');
  return ref
      .watch(organizationGatewayProvider)
      .fetchTasks(household.householdId!);
});

final organizationCalendarProvider = FutureProvider<List<CalendarEntry>>((
  ref,
) async {
  final tasks = await ref.watch(householdTasksProvider.future);
  final homeAuto = await ref.watch(homeAutoDataProvider.future);
  final periods = await ref.watch(remoteBudgetPeriodsProvider.future);
  final debts = await ref.watch(remoteDebtBalancesProvider.future);
  final goals = await ref.watch(savingsGoalsProvider.future);
  final shopping = await ref.watch(shoppingItemsProvider.future);
  final entries = <CalendarEntry>[
    for (final task in tasks)
      if (task.dueDate != null)
        CalendarEntry(
          key: 'task:${task.id}',
          title: task.title,
          date: task.dueDate!,
          source: CalendarSource.task,
          assigneeUserId: task.assigneeUserId,
          sourceId: task.id,
          status: task.status == HouseholdTaskStatus.cancelled
              ? CalendarEntryStatus.cancelled
              : task.isActive
              ? CalendarEntryStatus.active
              : CalendarEntryStatus.resolved,
        ),
    for (final plan in homeAuto.costPlans)
      CalendarEntry(
        key: 'home-auto:${plan.id}',
        title: plan.label,
        date: plan.dueDate,
        source: CalendarSource.homeAuto,
        sourceId: plan.id,
      ),
    for (final period in periods)
      CalendarEntry(
        key: 'budget:${period.id}',
        title: 'Clôture budget ${period.label}',
        date: period.endsOn,
        source: CalendarSource.budget,
        sourceId: period.id,
      ),
    for (final debt in debts)
      if (debt.dueAt != null && debt.status == 'open')
        CalendarEntry(
          key: 'obligation:${debt.id}',
          title: debt.description,
          date: debt.dueAt!,
          source: CalendarSource.obligation,
          sourceId: debt.id,
        ),
    for (final goal in goals)
      if (goal.goal.targetDate != null)
        CalendarEntry(
          key: 'goal:${goal.goal.id}',
          title: goal.goal.name,
          date: goal.goal.targetDate!,
          source: CalendarSource.goal,
          sourceId: goal.goal.id,
        ),
    for (final item in shopping)
      if (item.item.desiredDate != null && item.item.status.name == 'planned')
        CalendarEntry(
          key: 'shopping:${item.item.id}',
          title: item.item.label,
          date: item.item.desiredDate!,
          source: CalendarSource.shopping,
          sourceId: item.item.id,
        ),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return List.unmodifiable(entries);
});

final organizationAlertsProvider = FutureProvider<List<AppAlert>>((ref) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final userId = ref.watch(currentUserIdProvider);
  if (household.householdId == null || userId == null) return const [];
  final tasks = await ref.watch(householdTasksProvider.future);
  final dashboard = await ref.watch(financialDashboardProvider.future);
  final compensations = await ref.watch(memberCompensationsProvider.future);
  final gateway = ref.watch(organizationGatewayProvider);
  final states = await gateway.fetchAlertStates(household.householdId!, userId);
  final read = {
    for (final e in states.entries)
      if (e.value.readAt != null) e.key,
  };
  final reminders = await gateway.fetchReminders(
    household.householdId!,
    userId,
  );
  final rules = await gateway.fetchReminderRules(household.householdId!);
  bool ruleEnabled(String type) {
    final personal = rules.where(
      (r) => r.type == type && r.recipientUserId == userId,
    );
    if (personal.isNotEmpty) return personal.first.enabled;
    final shared = rules.where(
      (r) => r.type == type && r.recipientUserId == null,
    );
    return shared.isEmpty || shared.first.enabled;
  }

  final projection = await ref.watch(cashflowProjectionProvider.future);
  final preferences = await ref.watch(notificationPreferencesProvider.future);
  final alerts = <AppAlert>[
    for (final task in tasks.where((task) => task.isOverdue(DateTime.now())))
      AppAlert(
        key: 'task-overdue:${task.id}',
        title: 'Tâche en retard',
        detail: task.title,
        category: 'tasks',
        read: read.contains('task-overdue:${task.id}'),
      ),
    for (var i = 0; i < dashboard.alerts.length; i++)
      AppAlert(
        key:
            'financial:${dashboard.alerts[i].destination.name}:${dashboard.alerts[i].title}',
        title: dashboard.alerts[i].title,
        detail: dashboard.alerts[i].detail,
        category: 'finance',
        read: read.contains(
          'financial:${dashboard.alerts[i].destination.name}:${dashboard.alerts[i].title}',
        ),
      ),
    ...buildCompensationAlerts(compensations, userId, read),
    ...reminders.where(
      (r) => ruleEnabled(
        r.actionType == 'open_occurrence'
            ? 'expected_occurrence'
            : 'monthly_close',
      ),
    ),
    if (ruleEnabled('cashflow_risk'))
      for (var i = 0; i < projection.risks.length; i++)
        AppAlert(
          key:
              'cashflow-risk:${projection.risks[i].date.toIso8601String()}:${projection.risks[i].message}',
          title: 'Risque de trésorerie',
          detail: projection.risks[i].message,
          category: 'reminders',
          dueAt: projection.risks[i].date,
          priority: HouseholdTaskPriority.high,
          source: CalendarSource.cashflowProjection,
          sourceId: 'projection',
          actionType: 'open_projection',
        ),
  ];
  final now = DateTime.now();
  return List.unmodifiable(
    alerts
        .where(
          (alert) =>
              (preferences[alert.category] ?? true) &&
              (states[alert.key]?.visibleAt(now) ?? true),
        )
        .map(
          (a) => AppAlert(
            key: a.key,
            title: a.title,
            detail: a.detail,
            category: a.category,
            read: states[a.key]?.readAt != null || a.read,
            source: a.source,
            sourceId: a.sourceId,
            dueAt: a.dueAt,
            priority: a.priority,
            actionType: a.actionType,
          ),
        ),
  );
});

final reminderRulesProvider = FutureProvider<List<ReminderRule>>((ref) async {
  final h = await ref.watch(activeHouseholdProvider.future);
  if (h.householdId == null) return const [];
  return ref
      .watch(organizationGatewayProvider)
      .fetchReminderRules(h.householdId!);
});

List<AppAlert> buildCompensationAlerts(
  Iterable<MemberCompensation> compensations,
  String userId,
  Set<String> read,
) => [
  for (final item in compensations)
    if (item.status == 'to_pay' && item.debtorUserId == userId)
      AppAlert(
        key: 'compensation:pay:${item.id}',
        title: 'Compensation à verser',
        detail:
            '${item.remaining.toStringAsFixed(2)} MAD restant — ${item.reason}',
        category: 'compensations',
        read: read.contains('compensation:pay:${item.id}'),
        source: CalendarSource.compensation,
        sourceId: item.id,
      ),
  for (final item in compensations)
    if (item.status == 'transfer_sent' &&
        item.pendingReceipt > 0 &&
        item.creditorUserId == userId)
      AppAlert(
        key: 'compensation:receipt:${item.id}',
        title: 'Réception à confirmer',
        detail:
            '${item.pendingReceipt.toStringAsFixed(2)} MAD — ${item.reason}',
        category: 'compensations',
        read: read.contains('compensation:receipt:${item.id}'),
        source: CalendarSource.compensation,
        sourceId: item.id,
      ),
];

final notificationPreferencesProvider = FutureProvider<Map<String, bool>>((
  ref,
) async {
  final household = await ref.watch(activeHouseholdProvider.future);
  final user = ref.watch(currentUserIdProvider);
  if (household.householdId == null || user == null) return const {};
  return ref
      .watch(organizationGatewayProvider)
      .fetchPreferences(household.householdId!, user);
});

final organizationActionsProvider = Provider((ref) => OrganizationActions(ref));

class OrganizationActions {
  OrganizationActions(this.ref);
  final Ref ref;
  Future<void> createTask(Map<String, Object?> values) async {
    final h = await ref.read(activeHouseholdProvider.future);
    final u = ref.read(currentUserIdProvider);
    if (h.householdId == null || u == null) {
      throw StateError('Session indisponible.');
    }
    await ref
        .read(organizationGatewayProvider)
        .createTask(h.householdId!, u, values);
    ref.invalidate(householdTasksProvider);
  }

  Future<void> complete(String id, String key) async {
    await ref
        .read(organizationGatewayProvider)
        .completeTask(id, 'completed', '', key);
    ref.invalidate(householdTasksProvider);
  }

  Future<void> markRead(String key) async {
    final h = await ref.read(activeHouseholdProvider.future);
    final u = ref.read(currentUserIdProvider);
    if (h.householdId == null || u == null) return;
    await ref
        .read(organizationGatewayProvider)
        .markAlertRead(h.householdId!, u, key);
    ref.invalidate(organizationAlertsProvider);
  }

  Future<void> snooze(String key, DateTime until, {bool notYet = false}) async {
    final h = await ref.read(activeHouseholdProvider.future);
    final u = ref.read(currentUserIdProvider);
    if (h.householdId == null || u == null) return;
    await ref
        .read(organizationGatewayProvider)
        .actOnReminder(
          h.householdId!,
          key,
          notYet ? 'not_yet' : 'snoozed',
          until,
          _uuid(),
        );
    ref.invalidate(organizationAlertsProvider);
  }

  Future<void> dismiss(String key) async {
    final h = await ref.read(activeHouseholdProvider.future);
    final u = ref.read(currentUserIdProvider);
    if (h.householdId == null || u == null) return;
    await ref
        .read(organizationGatewayProvider)
        .actOnReminder(h.householdId!, key, 'dismissed', null, _uuid());
    ref.invalidate(organizationAlertsProvider);
  }

  Future<void> saveRule(ReminderRule rule) async {
    final h = await ref.read(activeHouseholdProvider.future);
    final u = ref.read(currentUserIdProvider);
    if (h.householdId == null || u == null) return;
    await ref
        .read(organizationGatewayProvider)
        .saveReminderRule(h.householdId!, u, rule);
    ref.invalidate(reminderRulesProvider);
  }

  Future<void> setPreference(String category, bool enabled) async {
    final h = await ref.read(activeHouseholdProvider.future);
    final u = ref.read(currentUserIdProvider);
    if (h.householdId == null || u == null) return;
    await ref
        .read(organizationGatewayProvider)
        .setPreference(h.householdId!, u, category, enabled);
    ref.invalidate(notificationPreferencesProvider);
    ref.invalidate(organizationAlertsProvider);
  }
}

UserAlertState _alertState(Map<String, Object?> r) => UserAlertState(
  key: r['alert_key'] as String,
  readAt: r['read_at'] == null ? null : DateTime.parse(r['read_at'] as String),
  dismissedAt: r['dismissed_at'] == null
      ? null
      : DateTime.parse(r['dismissed_at'] as String),
  snoozedUntil: r['snoozed_until'] == null
      ? null
      : DateTime.parse(r['snoozed_until'] as String),
  lastAction: r['last_action'] as String?,
);

AppAlert _reminder(Map<String, Object?> r) => AppAlert(
  key: r['dedupe_key'] as String,
  title: r['title'] as String,
  detail: r['detail'] as String,
  category: 'reminders',
  dueAt: DateTime.parse(r['due_at'] as String),
  priority: HouseholdTaskPriority.values.byName(r['priority'] as String),
  sourceId: r['source_id'] as String?,
  source: switch (r['action_type']) {
    'open_occurrence' => CalendarSource.recurringFinance,
    'open_monthly_close' => CalendarSource.monthlyClose,
    _ => CalendarSource.cashflowProjection,
  },
  actionType: r['action_type'] as String?,
);

ReminderRule _rule(Map<String, Object?> r) => ReminderRule(
  type: r['rule_type'] as String,
  enabled: r['enabled'] as bool,
  priority: HouseholdTaskPriority.values.byName(r['priority'] as String),
  parameters: Map<String, Object?>.from(r['parameters'] as Map),
  recipientUserId: r['recipient_user_id'] as String?,
);

String _uuid() {
  final random = Random.secure();
  final values = List<int>.generate(16, (_) => random.nextInt(256));
  values[6] = (values[6] & 15) | 64;
  values[8] = (values[8] & 63) | 128;
  String h(int i) => values[i].toRadixString(16).padLeft(2, '0');
  return '${[for (var i = 0; i < 4; i++) h(i)].join()}-${[for (var i = 4; i < 6; i++) h(i)].join()}-${[for (var i = 6; i < 8; i++) h(i)].join()}-${[for (var i = 8; i < 10; i++) h(i)].join()}-${[for (var i = 10; i < 16; i++) h(i)].join()}';
}

HouseholdTask _task(Map<String, Object?> row) => HouseholdTask(
  id: row['id'] as String,
  householdId: row['household_id'] as String,
  title: row['title'] as String,
  description: row['description'] as String?,
  assigneeUserId: row['assignee_user_id'] as String?,
  dueDate: row['due_date'] == null
      ? null
      : DateTime.parse(row['due_date'] as String),
  priority: HouseholdTaskPriority.values.byName(row['priority'] as String),
  status: HouseholdTaskStatus.values.byName(
    (row['status'] as String).replaceFirst('in_progress', 'inProgress'),
  ),
  recurrence: TaskRecurrence.values.byName(row['recurrence'] as String),
  createdBy: row['created_by'] as String,
  createdAt: DateTime.parse(row['created_at'] as String),
  sourceModule: row['source_module'] as String?,
  sourceId: row['source_id'] as String?,
);
