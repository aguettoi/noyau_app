import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/household_locale.dart';
import '../../../core/network/network_failure.dart';
import '../../../core/presentation/user_safe_error.dart';
import '../../finance/domain/transaction_draft.dart';
import '../../finance/domain/household_member.dart';
import '../../finance/presentation/transactions_page.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../../experience/application/experience_provider.dart';
import '../../experience/application/offline_connectivity.dart';
import '../../experience/domain/offline_draft.dart';
import '../application/daily_life_provider.dart';
import '../application/organization_provider.dart';
import '../domain/cycle_tracking.dart';

class DailyLifePage extends ConsumerWidget {
  const DailyLifePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = HouseholdWords(ref.watch(appLocaleProvider));
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(words.text('daily.title')),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: words.text('daily.groceries')),
              Tab(text: words.text('daily.home')),
              Tab(text: words.text('daily.personal')),
              Tab(text: words.text('daily.categories')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _GroceriesTab(),
            _HomeTab(),
            _CycleTab(),
            _CategoriesTab(),
          ],
        ),
      ),
    );
  }
}

class _GroceriesTab extends ConsumerWidget {
  const _GroceriesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = HouseholdWords(ref.watch(appLocaleProvider));
    final snapshot = ref.watch(
      offlineSnapshotStatusProvider.select(
        (items) => items['household_groceries'],
      ),
    );
    return Column(
      children: [
        if (snapshot?.stale == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: OfflineCachedDataBanner(capturedAt: snapshot!.capturedAt),
          ),
        Expanded(
          child: _AsyncList(
            value: ref.watch(groceryItemsProvider),
            empty: words.text('grocery.empty'),
            tile: (row) {
              final pending = row['offline_state'] != null;
              return Column(
                children: [
                  CheckboxListTile(
                    key: Key('grocery-${row['id']}'),
                    value: row['status'] == 'picked',
                    title: Text(row['label'] as String),
                    subtitle: Text(
                      [
                        '${row['quantity']} ${row['unit'] ?? ''}'.trim(),
                        if (pending)
                          _offlineStateLabel(
                            AppWords.of(context),
                            row['offline_state'] as String,
                          ),
                      ].join(' • '),
                    ),
                    onChanged: pending
                        ? null
                        : (v) => ref
                              .read(dailyLifeActionsProvider)
                              .setGroceryStatus(
                                row['id'] as String,
                                v == true ? 'picked' : 'needed',
                              ),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      key: Key('grocery-expense-${row['id']}'),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(words.text('grocery.expense')),
                      onPressed: pending
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TransactionsPage(
                                  forceExpense: true,
                                  prefill: TransactionFormPrefill(
                                    description: row['label'] as String,
                                    notes: words.text('grocery.finance_notice'),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              );
            },
            addKey: const Key('grocery-add-button'),
            onAdd: () => showGroceryEntryDialog(context, ref),
          ),
        ),
      ],
    );
  }
}

String _offlineStateLabel(AppWords words, String state) => switch (state) {
  'syncing' => words.text('offline.syncing_item'),
  'rejected' => words.text('offline.rejected_item'),
  'conflict' => words.text('offline.conflict_item'),
  'actionRequired' => words.text('offline.action_required_item'),
  _ => words.text('offline.pending_item'),
};

class _HomeTab extends ConsumerWidget {
  const _HomeTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = HouseholdWords(ref.watch(appLocaleProvider));
    return _AsyncList(
      value: ref.watch(homeRecordsProvider),
      empty: words.text('home.empty'),
      tile: (row) => ListTile(
        leading: const Icon(Icons.home_repair_service_outlined),
        title: Text(row['label'] as String),
        subtitle: Text(
          [
            row['kind'],
            if (row['provider'] != null) row['provider'],
            if (row['due_on'] != null) 'Échéance ${row['due_on']}',
          ].join(' • '),
        ),
      ),
      onAdd: () => _homeDialog(context, ref),
    );
  }
}

class _CycleTab extends ConsumerStatefulWidget {
  const _CycleTab();

  @override
  ConsumerState<_CycleTab> createState() => _CycleTabState();
}

class _CycleTabState extends ConsumerState<_CycleTab> {
  final _pendingRecipients = <String>{};

  Future<void> _setShare(
    String recipient,
    bool shared,
    HouseholdWords words,
  ) async {
    if (_pendingRecipients.contains(recipient)) return;
    setState(() => _pendingRecipients.add(recipient));
    try {
      await ref.read(dailyLifeActionsProvider).setCycleShare(recipient, shared);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            words.text(shared ? 'cycle.share_success' : 'cycle.revoke_success'),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userSafeErrorMessage(context, error))),
      );
    } finally {
      if (mounted) setState(() => _pendingRecipients.remove(recipient));
    }
  }

  @override
  Widget build(BuildContext context) {
    final members =
        ref.watch(remoteHouseholdMembersProvider).valueOrNull ?? const [];
    final currentUser = ref.watch(currentUserIdProvider);
    final shares = ref.watch(ownCycleSharesProvider).valueOrNull ?? const {};
    final forecast = ref.watch(ownCycleForecastProvider).valueOrNull;
    final privateEntries =
        ref.watch(ownCyclePrivateEntriesProvider).valueOrNull ?? const [];
    final sharedEvents =
        ref.watch(cycleEventsProvider).valueOrNull?.where((row) {
          return row['owner_user_id'] != currentUser;
        }).toList() ??
        const [];
    final words = HouseholdWords(ref.watch(appLocaleProvider));
    return Column(
      children: [
        MaterialBanner(
          content: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(words.text('personal.private')),
            subtitle: Text(words.text('cycle.share_private')),
          ),
          actions: const [SizedBox.shrink()],
        ),
        _CycleForecastCard(forecast: forecast, words: words),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.enhanced_encryption_outlined),
            title: Text(words.text('cycle.private_journal')),
            subtitle: Text(
              privateEntries.isEmpty
                  ? words.text('cycle.private_empty')
                  : '${privateEntries.length}',
            ),
            trailing: IconButton(
              tooltip: words.text('cycle.add_private'),
              icon: const Icon(Icons.add),
              onPressed: () => _cyclePrivateEntryDialog(context, ref),
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ExpansionTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: Text(words.text('cycle.shared_calendar')),
            children: sharedEvents.isEmpty
                ? [ListTile(title: Text(words.text('cycle.shared_empty')))]
                : [
                    for (final row in sharedEvents)
                      ListTile(
                        title: Text(
                          '${_cyclePhaseLabel(words, row['phase'])} — '
                          '${row['starts_on']}',
                        ),
                        subtitle: row['ends_on'] == null
                            ? null
                            : Text('${row['starts_on']} – ${row['ends_on']}'),
                      ),
                  ],
          ),
        ),
        Expanded(
          child: _AsyncList(
            value: ref.watch(ownCycleEventsProvider),
            empty: words.text('cycle.empty'),
            tile: (row) => ListTile(
              leading: const Icon(Icons.favorite_border),
              title: Text(
                '${_cyclePhaseLabel(words, row['phase'])} — ${row['starts_on']}',
              ),
              subtitle: row['notes'] == null
                  ? null
                  : Text(words.text('cycle.notes_recorded')),
              onTap: () => _cycleDialog(context, ref, initial: row),
              trailing: IconButton(
                tooltip: words.text('cycle.archive'),
                icon: const Icon(Icons.archive_outlined),
                onPressed: () => ref
                    .read(dailyLifeActionsProvider)
                    .archiveCycleEvent(row['id'] as String),
              ),
            ),
            onAdd: () => _cycleDialog(context, ref),
          ),
        ),
        if (members.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                Text(words.text('cycle.share_title')),
                Text(words.text('cycle.share_allowed')),
                Text(words.text('cycle.share_private')),
                Text(words.text('cycle.revoke')),
                for (final member in members.where((m) => m.id != currentUser))
                  FilterChip(
                    label: Text(member.displayName),
                    selected: shares.contains(member.id),
                    onSelected: _pendingRecipients.contains(member.id)
                        ? null
                        : (value) => _setShare(member.id, value, words),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CycleForecastCard extends StatelessWidget {
  const _CycleForecastCard({required this.forecast, required this.words});

  final CycleForecast? forecast;
  final HouseholdWords words;

  @override
  Widget build(BuildContext context) {
    final value = forecast;
    final locale = Localizations.localeOf(context).toLanguageTag();
    String range(DateTime? from, DateTime? to) {
      if (from == null || to == null) return words.text('cycle.insufficient');
      final format = DateFormat.yMMMd(locale);
      return '${format.format(from)} – ${format.format(to)}';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              words.text('cycle.forecast'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (value == null || !value.hasEstimate)
              Text(words.text('cycle.insufficient'))
            else ...[
              Text(
                '${words.text('cycle.next_period')} : '
                '${range(value.nextPeriodFrom, value.nextPeriodTo)}',
              ),
              Text(
                '${words.text('cycle.ovulation')} : '
                '${range(value.estimatedOvulationFrom, value.estimatedOvulationTo)}',
              ),
              Text(words.text('cycle.uncertainty')),
            ],
            const SizedBox(height: 8),
            Text(
              words.text('cycle.fertility_warning'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _cyclePhaseLabel(HouseholdWords words, Object? phase) {
  final value = phase?.toString() ?? 'other';
  const supported = {'period', 'follicular', 'ovulation', 'luteal', 'other'};
  return words.text(
    'cycle.phase.${supported.contains(value) ? value : 'other'}',
  );
}

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) => _AsyncList(
    value: ref.watch(businessCategoriesProvider),
    empty: 'Aucune catégorie métier.',
    tile: (row) => ListTile(
      leading: const Icon(Icons.category_outlined),
      title: Text(row['name'] as String),
      trailing: IconButton(
        tooltip: 'Archiver la catégorie',
        icon: const Icon(Icons.archive_outlined),
        onPressed: () => ref
            .read(dailyLifeActionsProvider)
            .archiveCategory(row['id'] as String),
      ),
    ),
    onAdd: () => _textDialog(context, 'Nouvelle catégorie', 'Nom').then((v) {
      if (v != null) ref.read(dailyLifeActionsProvider).addCategory(v);
    }),
  );
}

class _AsyncList extends StatelessWidget {
  const _AsyncList({
    required this.value,
    required this.empty,
    required this.tile,
    required this.onAdd,
    this.addKey,
  });
  final AsyncValue<List<Map<String, Object?>>> value;
  final String empty;
  final Widget Function(Map<String, Object?>) tile;
  final VoidCallback onAdd;
  final Key? addKey;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: value.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => UserSafeErrorState(error: error),
          data: (rows) => rows.isEmpty
              ? Center(child: Text(empty))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [for (final row in rows) Card(child: tile(row))],
                ),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FloatingActionButton(
              key: addKey,
              onPressed: onAdd,
              child: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    ],
  );
}

Future<String?> _textDialog(
  BuildContext context,
  String title,
  String label,
) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result == null || result.isEmpty ? null : result;
}

Future<void> showGroceryEntryDialog(BuildContext context, WidgetRef ref) async {
  final label = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unit = TextEditingController();
  final words = HouseholdWords(ref.read(appLocaleProvider));
  final members = await _groceryMembersAvailableOffline(ref);
  if (!context.mounted) return;
  String? assignee;
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        key: const Key('grocery-entry-dialog'),
        title: Text(words.text('grocery.add_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              key: const Key('grocery-item-field'),
              decoration: InputDecoration(
                labelText: words.text('grocery.item'),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: words.text('grocery.quantity'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: unit,
                    decoration: InputDecoration(
                      labelText: words.text('grocery.unit'),
                    ),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: assignee,
              decoration: InputDecoration(
                labelText: words.text('grocery.assignee'),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(words.text('grocery.everyone')),
                ),
                for (final member in members)
                  DropdownMenuItem(
                    value: member.id,
                    child: Text(member.displayName),
                  ),
              ],
              onChanged: (value) => setState(() => assignee = value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(words.text('grocery.cancel')),
          ),
          FilledButton(
            key: const Key('grocery-submit-button'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(words.text('grocery.add')),
          ),
        ],
      ),
    ),
  );
  if (save == true && label.text.trim().isNotEmpty) {
    final idempotencyKey = _offlineUuid();
    final parsedQuantity =
        double.tryParse(quantity.text.replaceAll(',', '.')) ?? 1;
    Future<void> enqueue() async {
      final household = await ref.read(activeHouseholdProvider.future);
      final user = ref.read(currentUserIdProvider);
      if (household.householdId == null || user == null) {
        throw StateError('Session indisponible.');
      }
      await ref
          .read(experienceStoreProvider)
          .enqueueDraft(
            OfflineDraft(
              idempotencyKey: idempotencyKey,
              actionKind: 'grocery_item',
              updatedAt: DateTime.now().toUtc(),
              state: OfflineDraftState.pending,
              householdId: household.householdId,
              memberId: user,
              payload: {
                'label': label.text.trim(),
                'quantity': parsedQuantity,
                'unit': unit.text.trim().isEmpty ? null : unit.text.trim(),
                'assignee_user_id': assignee,
              },
            ),
          );
      ref.invalidate(offlineDraftsProvider);
      ref.invalidate(groceryItemsProvider);
      await ref.read(groceryItemsProvider.future);
      if (context.mounted) {
        final words = AppWords(ref.read(appLocaleProvider));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(words.text('offline.grocery_queued'))),
        );
      }
    }

    final connection = ref.read(syncConnectionStateProvider);
    if (connection == SyncConnectionState.offline ||
        connection == SyncConnectionState.reconnecting) {
      await enqueue();
    } else {
      try {
        await ref
            .read(dailyLifeActionsProvider)
            .addGrocery(
              label.text,
              idempotencyKey: idempotencyKey,
              assignee: assignee,
              quantity: parsedQuantity,
              unit: unit.text,
            );
      } catch (error) {
        if (!isNetworkFailure(error)) rethrow;
        ref.read(syncConnectionStateProvider.notifier).state =
            SyncConnectionState.offline;
        await enqueue();
      }
    }
  }
  // The route still animates its TextFields after showDialog completes. Delay
  // controller disposal until the dialog subtree has left the tree; otherwise
  // a fast local enqueue/invalidation can rebuild a field with a disposed
  // controller.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      label.dispose();
      quantity.dispose();
      unit.dispose();
    });
  });
}

Future<List<HouseholdMember>> _groceryMembersAvailableOffline(
  WidgetRef ref,
) async {
  final connection = ref.read(syncConnectionStateProvider);
  if (connection == SyncConnectionState.offline ||
      connection == SyncConnectionState.reconnecting) {
    return const [];
  }
  try {
    return await ref.read(remoteHouseholdMembersProvider.future);
  } catch (error) {
    // Assigning a grocery item is optional. A members lookup must never block
    // the canonical entry form; when the network is the cause, also expose the
    // shared offline state. The server still revalidates household membership
    // when the queued intent is synchronized.
    if (isNetworkFailure(error)) {
      ref.read(syncConnectionStateProvider.notifier).state =
          SyncConnectionState.offline;
    }
    return const [];
  }
}

String _offlineUuid() {
  final random = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final padded = random.padLeft(32, '0');
  return '${padded.substring(0, 8)}-${padded.substring(8, 12)}-4${padded.substring(13, 16)}-8${padded.substring(17, 20)}-${padded.substring(20, 32)}';
}

Future<void> _homeDialog(BuildContext context, WidgetRef ref) async {
  final label = TextEditingController();
  var kind = 'maintenance';
  var renewal = 'none';
  String? responsible;
  DateTime? due;
  final members = await ref.read(remoteHouseholdMembersProvider.future);
  if (!context.mounted) return;
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Maison'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'Libellé'),
            ),
            DropdownButtonFormField(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'contract', child: Text('Contrat')),
                DropdownMenuItem(value: 'warranty', child: Text('Garantie')),
                DropdownMenuItem(
                  value: 'maintenance',
                  child: Text('Entretien'),
                ),
              ],
              onChanged: (v) => setState(() => kind = v!),
            ),
            DropdownButtonFormField<String?>(
              initialValue: responsible,
              decoration: const InputDecoration(labelText: 'Responsable'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Tout le foyer'),
                ),
                for (final member in members)
                  DropdownMenuItem(
                    value: member.id,
                    child: Text(member.displayName),
                  ),
              ],
              onChanged: (value) => setState(() => responsible = value),
            ),
            DropdownButtonFormField(
              initialValue: renewal,
              decoration: const InputDecoration(labelText: 'Renouvellement'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Aucun')),
                DropdownMenuItem(value: 'monthly', child: Text('Mensuel')),
                DropdownMenuItem(value: 'yearly', child: Text('Annuel')),
              ],
              onChanged: (value) => setState(() => renewal = value!),
            ),
            ListTile(
              title: Text(
                due == null
                    ? 'Ajouter une échéance'
                    : DateFormat.yMd('fr').format(due!),
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => due = picked);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  if (save == true && label.text.trim().isNotEmpty) {
    await ref.read(dailyLifeActionsProvider).addHomeRecord({
      'label': label.text.trim(),
      'kind': kind,
      'responsible_user_id': responsible,
      'renewal': renewal,
      'due_on': due == null ? null : DateFormat('yyyy-MM-dd').format(due!),
    });
  }
  label.dispose();
}

Future<void> _cycleDialog(
  BuildContext context,
  WidgetRef ref, {
  Map<String, Object?>? initial,
}) async {
  final words = HouseholdWords(ref.read(appLocaleProvider));
  var start = initial == null
      ? ref.read(organizationClockProvider)
      : DateTime.parse(initial['starts_on'] as String);
  DateTime? end = initial?['ends_on'] == null
      ? null
      : DateTime.parse(initial!['ends_on'] as String);
  var phase = initial?['phase'] as String? ?? 'period';
  String? flow = initial?['flow'] as String?;
  final notes = TextEditingController(text: initial?['notes'] as String? ?? '');
  final symptoms = TextEditingController(
    text: ((initial?['symptoms'] as List?) ?? const []).join(', '),
  );
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(words.text('cycle.event_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField(
              initialValue: phase,
              decoration: InputDecoration(labelText: words.text('cycle.phase')),
              items: [
                for (final item in const [
                  'period',
                  'follicular',
                  'ovulation',
                  'luteal',
                  'other',
                ])
                  DropdownMenuItem(
                    value: item,
                    child: Text(words.text('cycle.phase.$item')),
                  ),
              ],
              onChanged: (v) => setState(() => phase = v!),
            ),
            ListTile(
              title: Text(
                DateFormat.yMd(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(start),
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDate: start,
                );
                if (d != null) setState(() => start = d);
              },
            ),
            ListTile(
              title: Text(
                end == null
                    ? words.text('cycle.end_date')
                    : DateFormat.yMd(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).format(end!),
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  firstDate: start,
                  lastDate: DateTime(2100),
                  initialDate: end ?? start,
                );
                if (d != null) setState(() => end = d);
              },
            ),
            DropdownButtonFormField<String?>(
              initialValue: flow,
              decoration: InputDecoration(
                labelText: words.text('cycle.flow_private'),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(words.text('cycle.flow.unspecified')),
                ),
                for (final item in const ['light', 'medium', 'heavy'])
                  DropdownMenuItem(
                    value: item,
                    child: Text(words.text('cycle.flow.$item')),
                  ),
              ],
              onChanged: (value) => setState(() => flow = value),
            ),
            TextField(
              controller: symptoms,
              decoration: InputDecoration(
                labelText: words.text('cycle.symptoms_private'),
              ),
            ),
            TextField(
              controller: notes,
              decoration: InputDecoration(
                labelText: words.text('cycle.private_notes'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(words.text('cycle.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(words.text('cycle.save')),
          ),
        ],
      ),
    ),
  );
  if (save == true) {
    final values = <String, Object?>{
      'starts_on': DateFormat('yyyy-MM-dd').format(start),
      'ends_on': end == null ? null : DateFormat('yyyy-MM-dd').format(end!),
      'phase': phase,
      'flow': flow,
      'symptoms': symptoms.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
    };
    if (initial == null) {
      await ref.read(dailyLifeActionsProvider).addCycleEvent(values);
    } else {
      await ref
          .read(dailyLifeActionsProvider)
          .updateCycleEvent(initial['id'] as String, values);
    }
  }
  notes.dispose();
  symptoms.dispose();
}

Future<void> _cyclePrivateEntryDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final words = HouseholdWords(ref.read(appLocaleProvider));
  var category = 'symptom';
  var occurredOn = ref.read(organizationClockProvider);
  final value = TextEditingController();
  final notes = TextEditingController();
  final save = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(words.text('cycle.add_private')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: InputDecoration(
                  labelText: words.text('cycle.private_category'),
                ),
                items: [
                  for (final item in const [
                    'symptom',
                    'spotting',
                    'contraception',
                    'intimacy',
                    'temperature',
                  ])
                    DropdownMenuItem(
                      value: item,
                      child: Text(words.text('cycle.category.$item')),
                    ),
                ],
                onChanged: (next) => setState(() => category = next!),
              ),
              ListTile(
                title: Text(
                  DateFormat.yMd(
                    Localizations.localeOf(context).toLanguageTag(),
                  ).format(occurredOn),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDate: occurredOn,
                  );
                  if (picked != null) setState(() => occurredOn = picked);
                },
              ),
              TextField(
                controller: value,
                decoration: InputDecoration(
                  labelText: words.text('cycle.private_value'),
                ),
              ),
              TextField(
                controller: notes,
                decoration: InputDecoration(
                  labelText: words.text('cycle.private_notes'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(words.text('cycle.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(words.text('cycle.save')),
          ),
        ],
      ),
    ),
  );
  if (save == true) {
    await ref.read(dailyLifeActionsProvider).addCyclePrivateEntry({
      'occurred_on': DateFormat('yyyy-MM-dd').format(occurredOn),
      'category': category,
      'payload': {'value': value.text.trim()},
      'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
    });
  }
  value.dispose();
  notes.dispose();
}
