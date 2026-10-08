import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_design_system.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../application/organization_provider.dart';
import '../domain/organization_models.dart';

class OrganizationPage extends ConsumerWidget {
  const OrganizationPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Organisation du foyer'),
        actions: [
          IconButton(
            key: const Key('notification-preferences'),
            tooltip: 'Préférences des alertes',
            onPressed: () => _showPreferences(context, ref),
            icon: const Icon(Icons.tune),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Tâches'),
            Tab(text: 'Calendrier'),
            Tab(text: 'Alertes'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [_TasksTab(), _CalendarTab(), _AlertsTab()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'organization-add-task',
        key: const Key('add-household-task'),
        onPressed: () => _showTaskDialog(context, ref),
        icon: const Icon(Icons.add_task),
        label: const Text('Nouvelle tâche'),
      ),
    ),
  );
}

Future<void> _showPreferences(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, dialogRef, _) => AlertDialog(
        title: const Text('Préférences des alertes'),
        content: SizedBox(
          width: 420,
          child: dialogRef
              .watch(notificationPreferencesProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Text('Préférences indisponibles.'),
                data: (preferences) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final category in const {
                      'tasks': 'Tâches',
                      'budget': 'Budget',
                      'finance': 'Finance',
                      'goals': 'Objectifs',
                      'home_auto': 'Logement / auto',
                    }.entries)
                      SwitchListTile(
                        title: Text(category.value),
                        subtitle: const Text('Alerte dans l’application'),
                        value: preferences[category.key] ?? true,
                        onChanged: (value) => dialogRef
                            .read(organizationActionsProvider)
                            .setPreference(category.key, value),
                      ),
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Notifications système'),
                      subtitle: Text('Reportées au lot P1.'),
                    ),
                  ],
                ),
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    ),
  );
}

class _TasksTab extends ConsumerWidget {
  const _TasksTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(householdTasksProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Impossible de charger les tâches.')),
        data: (tasks) {
          if (tasks.isEmpty) {
            return const _Empty(
              icon: Icons.task_alt,
              title: 'Aucune tâche',
              detail:
                  'Ajoutez une tâche ponctuelle ou récurrente pour organiser le foyer.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: tasks.length,
            itemBuilder: (_, index) {
              final task = tasks[index];
              return Card(
                child: ListTile(
                  key: Key('household-task-${task.id}'),
                  leading: Icon(
                    task.status == HouseholdTaskStatus.completed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(task.title),
                  subtitle: Text(
                    [
                      if (task.dueDate != null)
                        DateFormat.yMMMd('fr').format(task.dueDate!),
                      if (task.recurrence != TaskRecurrence.none)
                        'Récurrence : ${task.recurrence.name}',
                    ].join(' • '),
                  ),
                  trailing: task.isActive
                      ? IconButton(
                          tooltip: 'Marquer terminée',
                          icon: const Icon(Icons.done),
                          onPressed: () => ref
                              .read(organizationActionsProvider)
                              .complete(task.id, _uuid()),
                        )
                      : null,
                ),
              );
            },
          );
        },
      );
}

class _CalendarTab extends ConsumerStatefulWidget {
  const _CalendarTab();
  @override
  ConsumerState<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends ConsumerState<_CalendarTab> {
  CalendarSource? source;
  @override
  Widget build(BuildContext context) => ref
      .watch(organizationCalendarProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Impossible de charger le calendrier.')),
        data: (all) {
          final entries = source == null
              ? all
              : all.where((e) => e.source == source).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: DropdownButtonFormField<CalendarSource?>(
                  initialValue: source,
                  decoration: const InputDecoration(
                    labelText: 'Filtrer par source',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Toutes les sources'),
                    ),
                    for (final s in CalendarSource.values)
                      DropdownMenuItem(value: s, child: Text(_sourceLabel(s))),
                  ],
                  onChanged: (value) => setState(() => source = value),
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const _Empty(
                        icon: Icons.calendar_month,
                        title: 'Aucune échéance',
                        detail:
                            'Les échéances apparaîtront ici sans créer de nouvelle donnée financière.',
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          final e = entries[i];
                          return ListTile(
                            key: Key('calendar-entry-${e.key}'),
                            leading: const Icon(Icons.event_outlined),
                            title: Text(e.title),
                            subtitle: Text(
                              '${DateFormat.yMMMd('fr').format(e.date)} • ${_sourceLabel(e.source)}',
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      );
}

class _AlertsTab extends ConsumerWidget {
  const _AlertsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(organizationAlertsProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Impossible de charger les alertes.')),
        data: (alerts) => alerts.isEmpty
            ? const _Empty(
                icon: Icons.notifications_none,
                title: 'Aucune alerte active',
                detail: 'Les alertes résolues disparaissent automatiquement.',
              )
            : ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: alerts.length,
                itemBuilder: (_, i) {
                  final alert = alerts[i];
                  return Card(
                    child: ListTile(
                      key: Key('app-alert-${alert.key}'),
                      leading: Icon(
                        alert.read
                            ? Icons.notifications_none
                            : Icons.notification_important,
                      ),
                      title: Text(alert.title),
                      subtitle: Text(alert.detail),
                      trailing: alert.read
                          ? null
                          : TextButton(
                              onPressed: () => ref
                                  .read(organizationActionsProvider)
                                  .markRead(alert.key),
                              child: const Text('Marquer lue'),
                            ),
                    ),
                  );
                },
              ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title, detail;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

Future<void> _showTaskDialog(BuildContext context, WidgetRef ref) async {
  final title = TextEditingController();
  DateTime? due;
  String? assignee;
  var recurrence = TaskRecurrence.none;
  var priority = HouseholdTaskPriority.normal;
  final members = await ref.read(remoteHouseholdMembersProvider.future);
  if (!context.mounted) return;
  final save = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Nouvelle tâche'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Titre'),
                ),
                DropdownButtonFormField<String?>(
                  initialValue: assignee,
                  decoration: const InputDecoration(
                    labelText: 'Responsable (facultatif)',
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Tout le foyer'),
                    ),
                    for (final m in members)
                      DropdownMenuItem(value: m.id, child: Text(m.displayName)),
                  ],
                  onChanged: (v) => setState(() => assignee = v),
                ),
                DropdownButtonFormField(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priorité'),
                  items: [
                    for (final p in HouseholdTaskPriority.values)
                      DropdownMenuItem(value: p, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => priority = v!),
                ),
                DropdownButtonFormField(
                  initialValue: recurrence,
                  decoration: const InputDecoration(labelText: 'Récurrence'),
                  items: [
                    for (final r in TaskRecurrence.values)
                      DropdownMenuItem(value: r, child: Text(r.name)),
                  ],
                  onChanged: (v) => setState(() => recurrence = v!),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    due == null
                        ? 'Aucune échéance'
                        : DateFormat.yMMMd('fr').format(due!),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 365),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      initialDate: due ?? DateTime.now(),
                    );
                    if (picked != null) setState(() => due = picked);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Créer'),
          ),
        ],
      ),
    ),
  );
  if (save != true || title.text.trim().isEmpty) return;
  await ref.read(organizationActionsProvider).createTask({
    'title': title.text.trim(),
    'assignee_user_id': assignee,
    'due_date': due == null ? null : DateFormat('yyyy-MM-dd').format(due!),
    'priority': priority.name,
    'recurrence': recurrence.name,
    'idempotency_key': _uuid(),
  });
}

String _sourceLabel(CalendarSource source) => switch (source) {
  CalendarSource.task => 'Tâches',
  CalendarSource.budget => 'Budget',
  CalendarSource.obligation => 'Obligations',
  CalendarSource.compensation => 'Compensations',
  CalendarSource.reconciliation => 'Rapprochements',
  CalendarSource.goal => 'Objectifs',
  CalendarSource.priority => 'Priorités',
  CalendarSource.shopping => 'Achats',
  CalendarSource.homeAuto => 'Logement / auto',
  CalendarSource.investment => 'Investissements',
};
String _uuid() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${[for (var i = 0; i < 4; i++) h(i)].join()}-${[for (var i = 4; i < 6; i++) h(i)].join()}-${[for (var i = 6; i < 8; i++) h(i)].join()}-${[for (var i = 8; i < 10; i++) h(i)].join()}-${[for (var i = 10; i < 16; i++) h(i)].join()}';
}
