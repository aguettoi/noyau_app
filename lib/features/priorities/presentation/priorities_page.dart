import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../savings_goals/domain/savings_goal.dart';
import '../../shopping_list/application/providers/remote_shopping_list_provider.dart';
import '../../shopping_list/domain/shopping_item.dart';
import '../application/priority_projection.dart';
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
    final plans = ref.watch(priorityPlansProvider);
    return plans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Impossible de lire les priorités : $error')),
      data: (items) => DesktopPageContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Priorités',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        'Organisez les achats et objectifs existants. Cette projection ne crée aucune écriture financière.',
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  key: const Key('create-priority-plan'),
                  onPressed: () => _create(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Créer un plan'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (items.isEmpty)
              const DesktopSection(
                title: 'Aucun plan de priorités',
                subtitle:
                    'Créez un plan pour ordonner vos achats prévus et vos objectifs.',
                child: SizedBox.shrink(),
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
    final projections = projectPriorityPlan(
      items: plan.items,
      monthlyCapacity: plan.plan.monthlyCapacity,
      from: DateTime.now(),
    );
    final editable = plan.plan.status.isEditable;
    return DesktopSection(
      title: plan.plan.name,
      subtitle: plan.plan.notes,
      action: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          _StatusChip(status: plan.plan.status),
          if (editable)
            IconButton(
              tooltip: 'Modifier le plan',
              onPressed: () => _editPlan(context, ref),
              icon: const Icon(Icons.edit_outlined),
            ),
          PopupMenuButton<PriorityPlanStatus>(
            tooltip: 'Statut du plan',
            onSelected: (status) => _run(
              context,
              () => setPriorityPlanStatus(ref, plan.plan.id, status),
            ),
            itemBuilder: (_) => [
              if (editable && plan.plan.status != PriorityPlanStatus.active)
                const PopupMenuItem(
                  value: PriorityPlanStatus.active,
                  child: Text('Activer'),
                ),
              if (editable && plan.plan.status != PriorityPlanStatus.paused)
                const PopupMenuItem(
                  value: PriorityPlanStatus.paused,
                  child: Text('Mettre en pause'),
                ),
              if (editable)
                const PopupMenuItem(
                  value: PriorityPlanStatus.archived,
                  child: Text('Archiver'),
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
                ? 'Capacité mensuelle simulée : à renseigner'
                : 'Capacité mensuelle simulée : ${_money(plan.plan.monthlyCapacity!)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Hypothèse de planification uniquement — aucun budget, compte ou solde n’est modifié.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (editable)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: ValueKey('add-priority-item-${plan.plan.id}'),
                onPressed: () => _addItem(context, ref),
                icon: const Icon(Icons.playlist_add_outlined),
                label: const Text('Ajouter un achat ou un objectif'),
              ),
            ),
          if (plan.items.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text('Aucun projet dans ce plan.'),
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
    return ReorderableListView.builder(
      key: ValueKey('priority-sequence-${plan.plan.id}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: editable,
      itemCount: items.length,
      onReorderItem: !editable
          ? (_, _) {}
          : (oldIndex, newIndex) async {
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
          onRemove: () => _run(
            context,
            () => removePriorityPlanItem(ref, plan.plan.id, entry.item.item.id),
          ),
        );
      },
    );
  }
}

class _PriorityEntryCard extends StatelessWidget {
  const _PriorityEntryCard({
    super.key,
    required this.entry,
    required this.rank,
    required this.editable,
    required this.onRemove,
  });
  final PriorityProjectionEntry entry;
  final int rank;
  final bool editable;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final source = entry.item.source;
    final date = entry.estimatedCompletionDate ?? source.date;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: CompactListRow(
        leading: CircleAvatar(child: Text('$rank')),
        title: source.label,
        subtitle: [
          source.type.label,
          if (entry.estimatedNeed != null)
            'Besoin estimé : ${_money(entry.estimatedNeed!)}',
          if (source.progress != null)
            'Progression : ${(source.progress! * 100).round()} %',
          if (entry.estimatedMonths != null)
            '${entry.estimatedMonths} mois estimé${entry.estimatedMonths == 1 ? '' : 's'}',
          if (date != null) 'Prévision : ${_date(date)}',
          'Statut : ${source.status}',
        ].join(' · '),
        trailing: editable
            ? IconButton(
                tooltip: 'Retirer du plan',
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline),
              )
            : null,
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
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.current == null ? 'Créer un plan' : 'Modifier le plan'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('priority-plan-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nom du plan *'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('priority-plan-capacity'),
              controller: _capacity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Capacité mensuelle simulée (MAD)',
                helperText:
                    'Hypothèse de planification, sans écriture financière.',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('priority-plan-notes'),
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
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
              ? 'La capacité mensuelle est invalide.'
              : draft.validate();
          if (error != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error)));
            return;
          }
          Navigator.of(context).pop(draft);
        },
        child: Text(widget.current == null ? 'Créer' : 'Enregistrer'),
      ),
    ],
  );
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
  _PriorityCandidate? _selected;

  List<_PriorityCandidate> get _candidates {
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
            label: 'Achat · ${item.item.label}',
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
            label: 'Objectif · ${item.goal.name}',
          ),
        );
    return [...shopping, ...goals];
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    return AlertDialog(
      title: const Text('Ajouter une priorité'),
      content: SizedBox(
        width: 520,
        child: candidates.isEmpty
            ? const Text(
                'Aucun achat ou objectif éligible. Les projets déjà liés entre eux ne peuvent pas être ajoutés deux fois.',
              )
            : DropdownButtonFormField<_PriorityCandidate>(
                key: const Key('priority-source-picker'),
                initialValue: _selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Projet *'),
                items: [
                  for (final candidate in candidates)
                    DropdownMenuItem(
                      value: candidate,
                      child: Text(candidate.label),
                    ),
                ],
                onChanged: (value) => setState(() => _selected = value),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.of(context).pop(_selected),
          child: const Text('Ajouter'),
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
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final PriorityPlanStatus status;

  @override
  Widget build(BuildContext context) =>
      Chip(visualDensity: VisualDensity.compact, label: Text(status.label));
}

Future<void> _run(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on Object catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}

String _money(Money money) =>
    '${money.dirhams.toStringAsFixed(2).replaceAll('.', ',')} MAD';

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
