import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/priorities_locale.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../financial_availability/application/providers/financial_availability_provider.dart';
import '../../financial_availability/domain/financial_availability.dart';
import '../../financial_availability/application/providers/f4_planning_provider.dart';
import '../../savings_goals/domain/savings_goal.dart';
import '../../shopping_list/application/providers/remote_shopping_list_provider.dart';
import '../../shopping_list/domain/shopping_item.dart';
import '../application/providers/remote_priority_plans_provider.dart';
import '../domain/priority_plan.dart';

class PrioritiesPage extends ConsumerWidget {
  const PrioritiesPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<PriorityPlanDraft>(
      context: context,
      builder: (_) => const _PlanEditorDialog(),
    );
    if (draft == null || !context.mounted) return;
    await _run(context, () => createPriorityPlan(ref, draft));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = PrioritiesWords.of(context);
    final plans = ref.watch(priorityPlansProvider);
    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(child: Text(words.text('priorities.load_error'))),
      data: (items) => DesktopPageContainer(
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        words.text('priorities.title'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(words.text('priorities.subtitle')),
                    ],
                  ),
                ),
                FilledButton.icon(
                  key: const Key('create-priority-plan'),
                  onPressed: () => _create(context, ref),
                  icon: const Icon(Icons.add),
                  label: Text(words.text('priorities.create_plan')),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (items.isEmpty)
              DesktopSection(
                title: words.text('priorities.empty_title'),
                subtitle: words.text('priorities.empty_subtitle'),
                child: const SizedBox.shrink(),
              )
            else
              for (final plan in items) ...[
                _PriorityPlanCard(plan: plan),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
        ),
      ),
    );
  }
}

class _PriorityPlanCard extends ConsumerWidget {
  const _PriorityPlanCard({required this.plan});
  final PriorityPlanView plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = PrioritiesWords.of(context);
    final availabilityState = ref.watch(financialAvailabilityProvider);
    final canonical = availabilityState.valueOrNull;
    final canonicalEntries = availabilityState.isLoading
        ? null
        : canonical?.planEntries[plan.plan.id];
    final unavailableReason = availabilityState.isLoading
        ? words.text('priorities.projection_loading')
        : plan.plan.status == PriorityPlanStatus.planned
        ? words.text('priorities.projection_planned')
        : availabilityState.hasError
        ? words.text('priorities.projection_unavailable_data')
        : words.text('priorities.projection_unavailable_capacity');
    final projections = canonicalEntries == null
        ? List<PriorityProjectionEntry>.generate(plan.items.length, (index) {
            final item = plan.items[index];
            return PriorityProjectionEntry(
              item: item,
              estimatedNeed: item.source.estimatedNeed,
              estimatedMonths: null,
              estimatedCompletionDate: null,
              reason: unavailableReason,
            );
          }, growable: false)
        : List<PriorityProjectionEntry>.generate(plan.items.length, (index) {
            final sourceItem = plan.items[index];
            final entry = canonicalEntries.firstWhere(
              (entry) => entry.itemId == sourceItem.item.id,
              orElse: () => PlanProjectionEntry(
                itemId: sourceItem.item.id,
                remainingNeed:
                    sourceItem.source.estimatedNeed ??
                    const Money.fromMinorUnits(0),
                reason: words.text('priorities.projection_missing_item'),
              ),
            );
            return PriorityProjectionEntry(
              item: sourceItem,
              estimatedNeed: entry.remainingNeed,
              estimatedMonths: entry.months,
              estimatedCompletionDate: entry.completionDate,
              reason: entry.reason,
            );
          }, growable: false);
    final editable = plan.plan.status.isEditable;
    return DesktopSection(
      title: plan.plan.name,
      subtitle: plan.plan.notes,
      action: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          _StatusChip(status: plan.plan.status, words: words),
          if (plan.plan.status == PriorityPlanStatus.planned)
            OutlinedButton.icon(
              key: ValueKey('activate-priority-plan-${plan.plan.id}'),
              onPressed: () => _activate(context, ref),
              icon: const Icon(Icons.visibility_outlined),
              label: Text(words.text('priorities.use_for_projection')),
            ),
          if (editable)
            IconButton(
              tooltip: words.text('priorities.edit_plan'),
              onPressed: () => _editPlan(context, ref),
              icon: const Icon(Icons.edit_outlined),
            ),
          PopupMenuButton<PriorityPlanStatus>(
            tooltip: words.text('priorities.plan_status'),
            onSelected: (status) => _run(
              context,
              () => setPriorityPlanStatus(ref, plan.plan.id, status),
            ),
            itemBuilder: (_) => [
              if (editable && plan.plan.status != PriorityPlanStatus.paused)
                PopupMenuItem(
                  value: PriorityPlanStatus.paused,
                  child: Text(words.text('priorities.pause')),
                ),
              if (editable)
                PopupMenuItem(
                  value: PriorityPlanStatus.archived,
                  child: Text(words.text('priorities.archive')),
                ),
            ],
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.plan.monthlyCapacity == null
                ? words.text('priorities.capacity_missing')
                : words.format('priorities.capacity_value', {
                    'amount': _money(plan.plan.monthlyCapacity!),
                  }),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(words.text('priorities.planning_disclaimer')),
          if (canonical?.warnings.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(canonical!.warnings.first),
          ],
          const SizedBox(height: AppSpacing.md),
          if (editable)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: ValueKey('add-priority-item-${plan.plan.id}'),
                onPressed: () => _addItem(context, ref),
                icon: const Icon(Icons.playlist_add_outlined),
                label: Text(words.text('priorities.add_project')),
              ),
            ),
          if (plan.items.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(words.text('priorities.no_project')),
          ] else ...[
            const SizedBox(height: AppSpacing.sm),
            _PrioritySequence(
              plan: plan,
              projections: projections,
              editable: editable,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editPlan(BuildContext context, WidgetRef ref) async {
    final draft = await showDialog<PriorityPlanDraft>(
      context: context,
      builder: (_) => _PlanEditorDialog(current: plan.plan),
    );
    if (draft == null || !context.mounted) return;
    await _run(context, () => updatePriorityPlan(ref, plan.plan.id, draft));
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final words = PrioritiesWords.of(context);
    final plans = await ref.read(priorityPlansProvider.future);
    if (!context.mounted) return;
    final previous = plans.where(
      (item) =>
          item.plan.status == PriorityPlanStatus.active &&
          item.plan.id != plan.plan.id,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(words.text('priorities.activate_title')),
        content: Text(
          previous.isEmpty
              ? words.text('priorities.activate_first')
              : words.format('priorities.activate_replace', {
                  'plan': previous.first.plan.name,
                }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(words.text('priorities.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(words.text('priorities.use_plan')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _run(context, () async {
      await activatePriorityPlan(ref, plan.plan.id);
      ref.invalidate(financialAvailabilityProvider);
    });
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final values = await Future.wait([
      ref.read(shoppingItemsProvider.future),
      ref.read(savingsGoalsProvider.future),
    ]);
    if (!context.mounted) return;
    final candidate = await showDialog<_PriorityCandidate>(
      context: context,
      builder: (_) => _AddPriorityItemDialog(
        currentItems: plan.items,
        shopping: values[0] as List<ShoppingItemView>,
        goals: values[1] as List<SavingsGoalProgress>,
      ),
    );
    if (candidate == null || !context.mounted) return;
    await _run(
      context,
      () =>
          addPriorityPlanItem(ref, plan.plan.id, candidate.type, candidate.id),
    );
  }
}

class _PrioritySequence extends ConsumerWidget {
  const _PrioritySequence({
    required this.plan,
    required this.projections,
    required this.editable,
  });
  final PriorityPlanView plan;
  final List<PriorityProjectionEntry> projections;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = projections;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 420),
      child: ReorderableListView.builder(
        key: ValueKey('priority-sequence-${plan.plan.id}'),
        primary: false,
        buildDefaultDragHandles: false,
        itemCount: items.length,
        onReorderItem: !editable
            ? (_, _) {}
            : (oldIndex, newIndex) async {
                if (oldIndex == newIndex) return;
                final reordered = [...items];
                final item = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, item);
                await _run(
                  context,
                  () => reorderPriorityPlanItems(
                    ref,
                    plan.plan.id,
                    reordered.map((entry) => entry.item.item.id).toList(),
                  ),
                );
              },
        itemBuilder: (context, index) {
          final entry = items[index];
          return _PriorityEntryCard(
            key: ValueKey(entry.item.item.id),
            entry: entry,
            rank: index + 1,
            editable: editable,
            dragHandle: editable
                ? ReorderableDragStartListener(
                    key: ValueKey('priority-drag-${entry.item.item.id}'),
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  )
                : null,
            onRemove: () => _run(
              context,
              () =>
                  removePriorityPlanItem(ref, plan.plan.id, entry.item.item.id),
            ),
          );
        },
      ),
    );
  }
}

class _PriorityEntryCard extends ConsumerWidget {
  const _PriorityEntryCard({
    super.key,
    required this.entry,
    required this.rank,
    required this.editable,
    this.dragHandle,
    required this.onRemove,
  });
  final PriorityProjectionEntry entry;
  final int rank;
  final bool editable;
  final Widget? dragHandle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = PrioritiesWords.of(context);
    final source = entry.item.source;
    final date = entry.estimatedCompletionDate ?? source.date;
    final decision = ref
        .watch(priorityItemDecisionsProvider)
        .valueOrNull?[entry.item.item.id];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: CompactListRow(
        leading: CircleAvatar(child: Text(rank.toString())),
        title: source.label,
        subtitle: [
          _sourceTypeLabel(words, source.type),
          if (entry.estimatedNeed != null)
            words.format('priorities.estimated_need', {
              'amount': _money(entry.estimatedNeed!),
            }),
          if (source.progress != null)
            words.format('priorities.progress', {
              'progress': (source.progress! * 100)
                  .toStringAsFixed(1)
                  .replaceAll('.', ','),
            }),
          if (entry.estimatedMonths != null)
            words.format(
              entry.estimatedMonths == 1
                  ? 'priorities.funding_month.one'
                  : 'priorities.funding_month.many',
              {'count': entry.estimatedMonths!},
            ),
          if (date != null)
            words.format('priorities.forecast', {'date': _date(date)}),
          if (entry.reason != null) entry.reason!,
          if (decision != null)
            words.format('priorities.decision', {
              'decision': _decisionLabel(
                words,
                PriorityDecision.values.firstWhere(
                  (value) => value.databaseValue == decision,
                ),
              ),
            }),
          words.format('priorities.status', {
            'status': _sourceStatusLabel(words, source.status),
          }),
        ].join(' · '),
        trailing: !editable
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dragHandle case final Widget handle) handle,
                  PopupMenuButton<PriorityDecision>(
                    key: ValueKey('priority-decision-${entry.item.item.id}'),
                    tooltip: words.text('priorities.financial_decision'),
                    onSelected: (value) => savePriorityDecision(
                      ref,
                      itemId: entry.item.item.id,
                      decision: value,
                    ),
                    itemBuilder: (_) => [
                      for (final value in PriorityDecision.values)
                        PopupMenuItem(
                          value: value,
                          child: Text(_decisionLabel(words, value)),
                        ),
                    ],
                    icon: const Icon(Icons.rule_outlined),
                  ),
                  IconButton(
                    tooltip: words.text('priorities.remove'),
                    onPressed: onRemove,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PlanEditorDialog extends StatefulWidget {
  const _PlanEditorDialog({this.current});
  final PriorityPlan? current;

  @override
  State<_PlanEditorDialog> createState() => _PlanEditorDialogState();
}

class _PlanEditorDialogState extends State<_PlanEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _capacity;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.current?.name ?? '');
    _capacity = TextEditingController(
      text: widget.current?.monthlyCapacity?.dirhams.toStringAsFixed(2) ?? '',
    );
    _notes = TextEditingController(text: widget.current?.notes ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _capacity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = PrioritiesWords.of(context);
    return AlertDialog(
      title: Text(
        widget.current == null
            ? words.text('priorities.create_plan')
            : words.text('priorities.edit_plan'),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('priority-plan-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: words.text('priorities.plan_name'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('priority-plan-capacity'),
                controller: _capacity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: words.text('priorities.monthly_capacity'),
                  helperText: words.text('priorities.capacity_helper'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('priority-plan-notes'),
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: words.text('priorities.notes'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(words.text('priorities.cancel')),
        ),
        FilledButton(
          onPressed: () {
            final capacityText = _capacity.text.trim().replaceAll(',', '.');
            final parsedCapacity = double.tryParse(capacityText);
            final capacity = capacityText.isEmpty || parsedCapacity == null
                ? null
                : Money.fromDirhams(parsedCapacity);
            final draft = PriorityPlanDraft(
              name: _name.text,
              monthlyCapacity: capacity,
              notes: _notes.text,
            );
            final error = parsedCapacity == null && capacityText.isNotEmpty
                ? words.text('priorities.invalid_capacity')
                : _draftValidation(words, draft);
            if (error != null) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(error)));
              return;
            }
            Navigator.of(context).pop(draft);
          },
          child: Text(
            widget.current == null
                ? words.text('priorities.create')
                : words.text('priorities.save'),
          ),
        ),
      ],
    );
  }
}

class _AddPriorityItemDialog extends StatefulWidget {
  const _AddPriorityItemDialog({
    required this.currentItems,
    required this.shopping,
    required this.goals,
  });
  final List<PriorityPlanItemView> currentItems;
  final List<ShoppingItemView> shopping;
  final List<SavingsGoalProgress> goals;

  @override
  State<_AddPriorityItemDialog> createState() => _AddPriorityItemDialogState();
}

class _AddPriorityItemDialogState extends State<_AddPriorityItemDialog> {
  String? _selectedKey;

  List<_PriorityCandidate> _candidates(PrioritiesWords words) {
    final sources = widget.currentItems.map((item) => item.source).toList();
    final shopping = widget.shopping
        .where((item) => item.item.status == ShoppingItemStatus.planned)
        .where(
          (item) => !sources.any(
            (source) =>
                source.type == PrioritySourceType.shoppingItem &&
                source.id == item.item.id,
          ),
        )
        .where(
          (item) => !sources.any(
            (source) =>
                item.item.budgetGoalId != null &&
                source.type == PrioritySourceType.budgetGoal &&
                source.id == item.item.budgetGoalId,
          ),
        )
        .map(
          (item) => _PriorityCandidate(
            type: PrioritySourceType.shoppingItem,
            id: item.item.id,
            label: words.format('priorities.shopping_candidate', {
              'name': item.item.label,
            }),
          ),
        );
    final goals = widget.goals
        .where((item) => !item.goal.status.isClosed)
        .where(
          (item) => !sources.any(
            (source) =>
                source.type == PrioritySourceType.budgetGoal &&
                source.id == item.goal.id,
          ),
        )
        .where(
          (item) => !sources.any(
            (source) =>
                source.type == PrioritySourceType.shoppingItem &&
                source.goalId == item.goal.id,
          ),
        )
        .map(
          (item) => _PriorityCandidate(
            type: PrioritySourceType.budgetGoal,
            id: item.goal.id,
            label: words.format('priorities.goal_candidate', {
              'name': item.goal.name,
            }),
          ),
        );
    return [...shopping, ...goals];
  }

  @override
  Widget build(BuildContext context) {
    final words = PrioritiesWords.of(context);
    final candidates = _candidates(words);
    final selected = candidates
        .where((candidate) => candidate.key == _selectedKey)
        .firstOrNull;
    return AlertDialog(
      title: Text(words.text('priorities.add_priority')),
      content: SizedBox(
        width: 520,
        child: candidates.isEmpty
            ? Text(words.text('priorities.no_eligible_project'))
            : DropdownButtonFormField<String>(
                key: const Key('priority-source-picker'),
                initialValue: selected?.key,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: words.text('priorities.project'),
                ),
                items: [
                  for (final candidate in candidates)
                    DropdownMenuItem(
                      value: candidate.key,
                      child: Text(candidate.label),
                    ),
                ],
                onChanged: (value) => setState(() => _selectedKey = value),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(words.text('priorities.cancel')),
        ),
        FilledButton(
          onPressed: selected == null
              ? null
              : () => Navigator.of(context).pop(selected),
          child: Text(words.text('priorities.add')),
        ),
      ],
    );
  }
}

class _PriorityCandidate {
  const _PriorityCandidate({
    required this.type,
    required this.id,
    required this.label,
  });
  final PrioritySourceType type;
  final String id;
  final String label;

  /// Dropdown values must survive provider refreshes. Candidate instances are
  /// rebuilt from source lists, whereas this key is a stable business identity.
  String get key =>
      '${type == PrioritySourceType.shoppingItem ? 'shopping' : 'goal'}:$id';
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.words});
  final PriorityPlanStatus status;
  final PrioritiesWords words;

  @override
  Widget build(BuildContext context) => Chip(
    visualDensity: VisualDensity.compact,
    label: Text(words.text('priorities.status.${status.name}')),
  );
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on Object catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          PrioritiesWords.of(context).text('priorities.action_failed'),
        ),
      ),
    );
  }
}

String? _draftValidation(PrioritiesWords words, PriorityPlanDraft draft) {
  if (draft.name.trim().isEmpty || draft.name.trim().length > 120) {
    return words.text('priorities.invalid_name');
  }
  if (draft.monthlyCapacity != null && draft.monthlyCapacity!.minorUnits <= 0) {
    return words.text('priorities.positive_capacity');
  }
  if ((draft.notes?.trim().length ?? 0) > 2000) {
    return words.text('priorities.notes_too_long');
  }
  return null;
}

String _sourceTypeLabel(PrioritiesWords words, PrioritySourceType type) =>
    words.text(
      type == PrioritySourceType.shoppingItem
          ? 'priorities.source.shopping'
          : 'priorities.source.goal',
    );

String _decisionLabel(PrioritiesWords words, PriorityDecision decision) =>
    words.text('priorities.decision.${decision.databaseValue}');

String _sourceStatusLabel(PrioritiesWords words, String status) {
  final key = switch (status) {
    'Prévu' => 'planned',
    'Actif' => 'active',
    'En pause' => 'paused',
    'Clôturé' => 'completed',
    'Acheté' => 'purchased',
    'Annulé' => 'cancelled',
    'Archivé' => 'archived',
    _ => null,
  };
  return key == null ? status : words.text('priorities.source_status.$key');
}

String _money(Money money) =>
    '${money.dirhams.toStringAsFixed(2).replaceAll('.', ',')} MAD';

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
