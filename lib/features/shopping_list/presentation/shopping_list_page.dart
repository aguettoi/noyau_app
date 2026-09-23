import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../savings_goals/domain/savings_goal.dart';
import '../application/providers/remote_shopping_list_provider.dart';
import '../domain/shopping_item.dart';

class ShoppingListPage extends ConsumerStatefulWidget {
  const ShoppingListPage({super.key});

  @override
  ConsumerState<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends ConsumerState<ShoppingListPage> {
  ShoppingItemStatus? _status = ShoppingItemStatus.planned;

  Future<void> _edit([ShoppingItemView? current]) async {
    final results = await Future.wait([
      ref.read(remoteEnvelopeHistoryProvider.future),
      ref.read(savingsGoalsProvider.future),
    ]);
    if (!mounted) return;
    final result = await showDialog<ShoppingItemDraft>(
      context: context,
      builder: (_) => _ShoppingEditorDialog(
        current: current?.item,
        envelopes: results[0] as List<RemoteEnvelopeBalance>,
        goals: results[1] as List<SavingsGoalProgress>,
      ),
    );
    if (result == null || !mounted) return;
    try {
      if (current == null) {
        await createShoppingItem(ref, result);
      } else {
        await updateShoppingItem(ref, current.item.id, result);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              current == null
                  ? 'Article prévu créé.'
                  : 'Article prévu mis à jour.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) _error(context, error);
    }
  }

  Future<void> _priority(ShoppingItemView item) async {
    final priority = await showDialog<int>(
      context: context,
      builder: (_) =>
          _PriorityDialog(initial: item.memberPriorities.firstOrNull?.priority),
    );
    if (priority == null || !mounted) return;
    try {
      await setMyShoppingPriority(ref, item.item.id, priority);
    } on Object catch (error) {
      if (mounted) _error(context, error);
    }
  }

  Future<void> _changeState(ShoppingItemView item, bool archive) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: archive ? 'Archiver l’article' : 'Annuler l’article',
        confirm: archive ? 'Archiver' : 'Annuler',
      ),
    );
    if (reason == null || !mounted) return;
    try {
      if (archive) {
        await archiveShoppingItem(ref, item.item.id, reason);
      } else {
        await cancelShoppingItem(ref, item.item.id, reason);
      }
    } on Object catch (error) {
      if (mounted) _error(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(shoppingItemsProvider);
    return SafeArea(
      child: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: AppSpacing.page,
            child: Text('Impossible de lire la Shopping List : $error'),
          ),
        ),
        data: (data) {
          final filtered = data
              .where((item) => _status == null || item.item.status == _status)
              .toList();
          return DesktopPageContainer(
            child: ListView(
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Shopping List',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Text(
                      'Une liste d’intentions : aucun argent n’est réservé ni déplacé.',
                    ),
                    FilledButton.icon(
                      key: const Key('create-shopping-item'),
                      onPressed: _edit,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un achat prévu'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    ChoiceChip(
                      label: const Text('Tous'),
                      selected: _status == null,
                      onSelected: (_) => setState(() => _status = null),
                    ),
                    for (final status in ShoppingItemStatus.values)
                      ChoiceChip(
                        label: Text(status.label),
                        selected: _status == status,
                        onSelected: (_) => setState(() => _status = status),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (filtered.isEmpty)
                  _Empty(onCreate: _edit)
                else
                  ResponsiveGrid(
                    minItemWidth: 350,
                    children: [
                      for (final item in filtered)
                        _ItemCard(
                          item: item,
                          onEdit: item.item.status == ShoppingItemStatus.planned
                              ? () => _edit(item)
                              : null,
                          onPriority:
                              item.item.status == ShoppingItemStatus.planned
                              ? () => _priority(item)
                              : null,
                          onCancel:
                              item.item.status == ShoppingItemStatus.planned
                              ? () => _changeState(item, false)
                              : null,
                          onArchive:
                              item.item.status != ShoppingItemStatus.archived
                              ? () => _changeState(item, true)
                              : null,
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({
    required this.item,
    this.onEdit,
    this.onPriority,
    this.onCancel,
    this.onArchive,
  });
  final ShoppingItemView item;
  final VoidCallback? onEdit;
  final VoidCallback? onPriority;
  final VoidCallback? onCancel;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: Padding(
      padding: AppSpacing.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.item.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _Badge(status: item.item.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (item.item.estimatedAmount != null)
            Text('Estimation : ${_money(item.item.estimatedAmount!)}'),
          if (item.item.finalPriority != null)
            Text(
              'Priorité finale : ${item.item.finalPriority} (0 = prioritaire)',
            ),
          if (item.item.desiredDate != null)
            Text('Date souhaitée : ${_date(item.item.desiredDate!)}'),
          if (item.envelopeName != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Enveloppe liée : ${item.envelopeName} · ${_money(item.envelopeBalance!)} disponibles',
            ),
            if (item.estimatedGap case final gap?)
              Text('Écart théorique : ${_money(gap)}'),
          ],
          if (item.goalName != null)
            Text(
              'Objectif lié : ${item.goalName} · ${((item.goalProgress ?? 0) * 100).toStringAsFixed(0)} %',
            ),
          if (item.memberPriorities.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Priorités membres : ${item.memberPriorities.map((p) => '${p.memberName} ${p.priority}').join(' · ')}',
            ),
          ],
          if (item.item.notes?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(item.item.notes!),
          ],
          if (item.item.cancellationReason != null)
            Text('Motif : ${item.item.cancellationReason}'),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (onEdit != null)
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
              if (onPriority != null)
                OutlinedButton.icon(
                  onPressed: onPriority,
                  icon: const Icon(Icons.how_to_vote_outlined),
                  label: const Text('Ma priorité'),
                ),
              if (onCancel != null)
                TextButton(onPressed: onCancel, child: const Text('Annuler')),
              if (onArchive != null)
                TextButton(onPressed: onArchive, child: const Text('Archiver')),
              TextButton.icon(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _ShoppingHistoryDialog(itemId: item.item.id),
                ),
                icon: const Icon(Icons.history_outlined),
                label: const Text('Historique'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ShoppingHistoryDialog extends ConsumerWidget {
  const _ShoppingHistoryDialog({required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(shoppingItemHistoryProvider(itemId));
    return AlertDialog(
      title: const Text('Historique métier'),
      content: SizedBox(
        width: 500,
        child: history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('Historique indisponible : $error'),
          data: (entries) => entries.isEmpty
              ? const Text('Aucun changement métier enregistré.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in entries)
                      CompactListRow(
                        title: _historyLabel(entry.action),
                        subtitle: [
                          _dateTime(entry.createdAt),
                          'Effectué par : ${entry.actorName}',
                          if (entry.reason != null) 'Motif : ${entry.reason}',
                        ].join('\n'),
                        leading: const Icon(Icons.history_outlined),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.status});
  final ShoppingItemStatus status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ShoppingItemStatus.planned => AppColors.info,
      ShoppingItemStatus.purchased => AppColors.success,
      ShoppingItemStatus.cancelled => AppColors.danger,
      ShoppingItemStatus.archived => AppColors.darkTextSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: AppRadius.small,
      ),
      child: Text(
        status.label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => DesktopSection(
    title: 'Aucun achat prévu',
    subtitle: 'Préparez vos achats sans créer de dépense ni réserver de solde.',
    action: FilledButton.icon(
      onPressed: onCreate,
      icon: const Icon(Icons.add),
      label: const Text('Ajouter'),
    ),
    child: const Text(
      'Vous pourrez lier un article à une enveloppe ou à un objectif, à titre d’information uniquement.',
    ),
  );
}

class _ShoppingEditorDialog extends StatefulWidget {
  const _ShoppingEditorDialog({
    this.current,
    required this.envelopes,
    required this.goals,
  });
  final ShoppingItem? current;
  final List<RemoteEnvelopeBalance> envelopes;
  final List<SavingsGoalProgress> goals;
  @override
  State<_ShoppingEditorDialog> createState() => _ShoppingEditorDialogState();
}

class _ShoppingEditorDialogState extends State<_ShoppingEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  String? _envelopeId;
  String? _goalId;
  int? _priority;
  DateTime? _date;
  @override
  void initState() {
    super.initState();
    final item = widget.current;
    _label = TextEditingController(text: item?.label ?? '');
    _amount = TextEditingController(
      text: item?.estimatedAmount?.dirhams.toStringAsFixed(2) ?? '',
    );
    _notes = TextEditingController(text: item?.notes ?? '');
    _envelopeId = item?.envelopeId;
    _goalId = item?.budgetGoalId;
    _priority = item?.finalPriority;
    _date = item?.desiredDate;
  }

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _amount.text.trim().replaceAll(',', '.');
    final amount = text.isEmpty ? null : num.tryParse(text);
    if (text.isNotEmpty && amount == null) {
      _error(context, StateError('Le montant estimé est invalide.'));
      return;
    }
    final draft = ShoppingItemDraft(
      label: _label.text,
      estimatedAmount: amount == null ? null : Money.fromDirhams(amount),
      notes: _notes.text,
      desiredDate: _date,
      envelopeId: _envelopeId,
      budgetGoalId: _goalId,
      finalPriority: _priority,
    );
    final error = draft.validate();
    if (error != null) {
      _error(context, StateError(error));
      return;
    }
    Navigator.of(context).pop(draft);
  }

  @override
  Widget build(BuildContext context) {
    final ordinary = widget.envelopes
        .where((e) => !e.isSystem && !e.isArchived)
        .toList();
    final goals = widget.goals
        .where((goal) => goal.goal.status != SavingsGoalStatus.cancelled)
        .toList();
    final goal = _goalId == null
        ? null
        : goals.where((item) => item.goal.id == _goalId).firstOrNull;
    final usableEnvelopes = goal == null
        ? ordinary
        : ordinary.where((e) => e.id == goal.goal.fundingEnvelopeId).toList();
    return AlertDialog(
      title: Text(
        widget.current == null
            ? 'Ajouter un achat prévu'
            : 'Modifier l’achat prévu',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Article *'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Montant estimé (MAD)',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<int?>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Priorité finale'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Non définie')),
                  DropdownMenuItem(value: 0, child: Text('0 — prioritaire')),
                  DropdownMenuItem(value: 1, child: Text('1')),
                  DropdownMenuItem(value: 2, child: Text('2')),
                  DropdownMenuItem(value: 3, child: Text('3')),
                ],
                onChanged: (value) => setState(() => _priority = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                key: ValueKey('shopping-goal-${_goalId ?? 'none'}'),
                initialValue: _goalId,
                decoration: const InputDecoration(
                  labelText: 'Objectif lié (facultatif)',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Aucun')),
                  for (final item in goals)
                    DropdownMenuItem(
                      value: item.goal.id,
                      child: Text(item.goal.name),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _goalId = value;
                  if (value != null) {
                    _envelopeId = goals
                        .firstWhere((g) => g.goal.id == value)
                        .goal
                        .fundingEnvelopeId;
                  }
                }),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                key: ValueKey('shopping-envelope-${_envelopeId ?? 'none'}'),
                initialValue: usableEnvelopes.any((e) => e.id == _envelopeId)
                    ? _envelopeId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Enveloppe liée (facultatif)',
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Aucune')),
                  for (final envelope in usableEnvelopes)
                    DropdownMenuItem(
                      value: envelope.id,
                      child: Text(
                        '${envelope.name} · ${_money(envelope.balance)}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _envelopeId = value),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _date == null
                          ? 'Date souhaitée : non renseignée'
                          : 'Date souhaitée : ${_dateLabel(_date!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final selected = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        initialDate: _date ?? DateTime.now(),
                      );
                      if (selected != null) setState(() => _date = selected);
                    },
                    child: const Text('Choisir'),
                  ),
                ],
              ),
              TextField(
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
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _PriorityDialog extends StatefulWidget {
  const _PriorityDialog({this.initial});
  final int? initial;
  @override
  State<_PriorityDialog> createState() => _PriorityDialogState();
}

class _PriorityDialogState extends State<_PriorityDialog> {
  late int _value;
  @override
  void initState() {
    super.initState();
    _value = widget.initial ?? 1;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Ma priorité'),
    content: DropdownButtonFormField<int>(
      initialValue: _value,
      items: const [
        DropdownMenuItem(value: 0, child: Text('0 — prioritaire')),
        DropdownMenuItem(value: 1, child: Text('1')),
        DropdownMenuItem(value: 2, child: Text('2')),
        DropdownMenuItem(value: 3, child: Text('3')),
      ],
      onChanged: (value) => setState(() => _value = value!),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _value),
        child: const Text('Enregistrer'),
      ),
    ],
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.confirm});
  final String title;
  final String confirm;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      maxLength: 280,
      decoration: const InputDecoration(labelText: 'Motif (facultatif)'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Retour'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.confirm),
      ),
    ],
  );
}

String _money(Money value) => NumberFormat.currency(
  locale: 'fr_FR',
  symbol: 'MAD',
  decimalDigits: 2,
).format(value.dirhams);
String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
String _dateLabel(DateTime value) => _date(value);
String _dateTime(DateTime value) =>
    DateFormat('dd/MM/yyyy • HH:mm').format(value.toLocal());
String _historyLabel(String action) => switch (action) {
  'created' => 'Article prévu créé',
  'updated' => 'Article prévu modifié',
  'member_priority_set' => 'Priorité membre définie',
  'cancelled' => 'Article annulé',
  'archived' => 'Article archivé',
  _ => 'Modification',
};
void _error(BuildContext context, Object error) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );
