import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../application/providers/remote_savings_goals_provider.dart';
import '../domain/savings_goal.dart';

class SavingsGoalsPage extends ConsumerWidget {
  const SavingsGoalsPage({super.key});

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    SavingsGoalProgress? current,
  }) async {
    final envelopes = await ref.read(remoteEnvelopeHistoryProvider.future);
    final goals = await ref.read(savingsGoalsProvider.future);
    if (!context.mounted) return;
    final usedEnvelopeIds = goals
        .where(
          (item) =>
              !item.goal.status.isClosed && item.goal.id != current?.goal.id,
        )
        .map((item) => item.goal.fundingEnvelopeId)
        .toSet();
    final result = await showDialog<_GoalEditorResult>(
      context: context,
      builder: (_) => _GoalEditorDialog(
        current: current?.goal,
        envelopes: envelopes
            .where(
              (envelope) =>
                  !envelope.isSystem &&
                  !envelope.isArchived &&
                  !usedEnvelopeIds.contains(envelope.id),
            )
            .toList(growable: false),
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      if (current == null) {
        await ref.read(createSavingsGoalProvider)(
          result.draft,
          result.initialStatus,
        );
      } else {
        await ref.read(updateSavingsGoalProvider)(
          current.goal.id,
          result.draft,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              current == null
                  ? 'Objectif créé. Sa progression suivra l’enveloppe dédiée.'
                  : 'Objectif mis à jour.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(savingsGoalsProvider);
    return SafeArea(
      child: goals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: AppSpacing.page,
            child: Text('Impossible de lire les objectifs : $error'),
          ),
        ),
        data: (items) => DesktopPageContainer(
          child: ListView(
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Épargne & objectifs',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SecondaryInfoText(
                    'Les objectifs observent le solde réel de leur enveloppe dédiée.',
                  ),
                  FilledButton.icon(
                    key: const Key('create-savings-goal'),
                    onPressed: () => _openEditor(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Nouvel objectif'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (items.isEmpty)
                _EmptyGoals(onCreate: () => _openEditor(context, ref))
              else
                ResponsiveGrid(
                  minItemWidth: 350,
                  children: [
                    for (final item in items)
                      _GoalCard(
                        item: item,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SavingsGoalDetailPage(goalId: item.goal.id),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class SavingsGoalDetailPage extends ConsumerWidget {
  const SavingsGoalDetailPage({super.key, required this.goalId});

  final String goalId;

  Future<void> _changeStatus(
    BuildContext context,
    WidgetRef ref,
    SavingsGoalProgress item,
    SavingsGoalStatus status,
  ) async {
    final mustExplain =
        status == SavingsGoalStatus.completed ||
        status == SavingsGoalStatus.cancelled;
    final reason = mustExplain
        ? await showDialog<String>(
            context: context,
            builder: (_) => _ReasonDialog(
              title: status == SavingsGoalStatus.completed
                  ? 'Clôturer l’objectif'
                  : 'Annuler l’objectif',
              label: status == SavingsGoalStatus.completed
                  ? 'Motif de clôture (facultatif)'
                  : 'Motif d’annulation (facultatif)',
              confirmLabel: status == SavingsGoalStatus.completed
                  ? 'Clôturer'
                  : 'Annuler l’objectif',
            ),
          )
        : '';
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(setSavingsGoalStatusProvider)(
        item.goal.id,
        status,
        reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Statut « ${status.label} » enregistré.')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(savingsGoalsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Détail de l’objectif')),
      body: goals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Impossible de lire l’objectif : $error')),
        data: (items) {
          final matches = items.where((item) => item.goal.id == goalId);
          if (matches.isEmpty) {
            return const Center(child: Text('Objectif introuvable.'));
          }
          final item = matches.single;
          final history = ref.watch(savingsGoalHistoryProvider(goalId));
          return DesktopPageContainer(
            child: ListView(
              children: [
                _GoalSummary(item: item),
                const SizedBox(height: AppSpacing.md),
                DesktopSection(
                  title: 'Informations',
                  subtitle:
                      'Aucune écriture financière n’est créée par cet objectif.',
                  action: item.goal.status.isClosed
                      ? null
                      : FilledButton.tonalIcon(
                          onPressed: () => _openEdit(context, ref, item),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Modifier'),
                        ),
                  child: _GoalDetails(item: item),
                ),
                const SizedBox(height: AppSpacing.md),
                if (!item.goal.status.isClosed)
                  DesktopSection(
                    title: 'Actions',
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        if (item.goal.status == SavingsGoalStatus.planned ||
                            item.goal.status == SavingsGoalStatus.paused)
                          FilledButton.icon(
                            onPressed: () => _changeStatus(
                              context,
                              ref,
                              item,
                              SavingsGoalStatus.active,
                            ),
                            icon: const Icon(Icons.play_arrow_outlined),
                            label: Text(
                              item.goal.status == SavingsGoalStatus.paused
                                  ? 'Reprendre'
                                  : 'Activer',
                            ),
                          ),
                        if (item.goal.status == SavingsGoalStatus.active)
                          OutlinedButton.icon(
                            onPressed: () => _changeStatus(
                              context,
                              ref,
                              item,
                              SavingsGoalStatus.paused,
                            ),
                            icon: const Icon(Icons.pause_outlined),
                            label: const Text('Suspendre'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _changeStatus(
                            context,
                            ref,
                            item,
                            SavingsGoalStatus.completed,
                          ),
                          icon: const Icon(Icons.task_alt_outlined),
                          label: const Text('Clôturer'),
                        ),
                        TextButton.icon(
                          onPressed: () => _changeStatus(
                            context,
                            ref,
                            item,
                            SavingsGoalStatus.cancelled,
                          ),
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Annuler'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                DesktopSection(
                  title: 'Historique métier',
                  subtitle:
                      'Les mouvements financiers restent dans l’historique canonique de l’enveloppe.',
                  child: history.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, _) =>
                        Text('Historique indisponible : $error'),
                    data: (entries) => entries.isEmpty
                        ? const Text('Aucun changement métier enregistré.')
                        : Column(
                            children: [
                              for (final entry in entries)
                                CompactListRow(
                                  title: _historyActionLabel(entry.action),
                                  subtitle: [
                                    _dateTime(entry.createdAt),
                                    'Effectué par : ${entry.actorName}',
                                    if (entry.reason != null)
                                      'Motif : ${entry.reason}',
                                  ].join('\n'),
                                  leading: const Icon(Icons.history_outlined),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEdit(
    BuildContext context,
    WidgetRef ref,
    SavingsGoalProgress current,
  ) async {
    final envelopes = await ref.read(remoteEnvelopeHistoryProvider.future);
    final goals = await ref.read(savingsGoalsProvider.future);
    if (!context.mounted) return;
    final used = goals
        .where(
          (item) =>
              !item.goal.status.isClosed && item.goal.id != current.goal.id,
        )
        .map((item) => item.goal.fundingEnvelopeId)
        .toSet();
    final result = await showDialog<_GoalEditorResult>(
      context: context,
      builder: (_) => _GoalEditorDialog(
        current: current.goal,
        envelopes: envelopes
            .where(
              (envelope) =>
                  !envelope.isSystem &&
                  !envelope.isArchived &&
                  !used.contains(envelope.id),
            )
            .toList(growable: false),
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref.read(updateSavingsGoalProvider)(current.goal.id, result.draft);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Objectif mis à jour.')));
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.item, required this.onTap});

  final SavingsGoalProgress item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadius.card,
      child: Padding(
        padding: AppSpacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.goal.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _StatusBadge(status: item.goal.status),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('${item.goal.type.label} · ${item.envelopeName}'),
            const SizedBox(height: AppSpacing.md),
            Text('Accumulé : ${_money(item.accumulated)}'),
            Text('Cible : ${_money(item.goal.targetAmount)}'),
            Text('Reste : ${_money(item.remaining)}'),
            const SizedBox(height: AppSpacing.xs),
            LinearProgressIndicator(value: item.progressForIndicator),
            const SizedBox(height: AppSpacing.xs),
            Text('${(item.progressRatio * 100).toStringAsFixed(1)} %'),
            if (item.isFinancialTargetReached) ...[
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Cible financière atteinte',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (item.goal.targetDate != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('Échéance : ${_date(item.goal.targetDate!)}'),
            ],
            if (item.estimatedCompletionDate(DateTime.now()) case final date?)
              Text('Date prévisionnelle : ${_date(date)}'),
          ],
        ),
      ),
    ),
  );
}

class _GoalSummary extends StatelessWidget {
  const _GoalSummary({required this.item});

  final SavingsGoalProgress item;

  @override
  Widget build(BuildContext context) => DesktopSection(
    title: item.goal.name,
    subtitle: '${item.goal.type.label} · Enveloppe liée : ${item.envelopeName}',
    action: _StatusBadge(status: item.goal.status),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_money(item.accumulated)} sur ${_money(item.goal.targetAmount)}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        LinearProgressIndicator(value: item.progressForIndicator),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${(item.progressRatio * 100).toStringAsFixed(1)} % · Reste : ${_money(item.remaining)}',
        ),
        if (item.isFinancialTargetReached) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Cible financière atteinte. La clôture reste une décision explicite.',
            style: TextStyle(
              color: AppColors.success,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );
}

class _GoalDetails extends StatelessWidget {
  const _GoalDetails({required this.item});

  final SavingsGoalProgress item;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final projected = item.estimatedCompletionDate(now);
    final pace = item.requiredMonthlyPace(now);
    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.md,
      children: [
        _DetailValue(label: 'Priorité', value: '${item.goal.priority}'),
        _DetailValue(
          label: 'Cible mensuelle',
          value: item.goal.monthlyTarget == null
              ? 'Non renseignée'
              : _money(item.goal.monthlyTarget!),
        ),
        _DetailValue(
          label: 'Échéance',
          value: item.goal.targetDate == null
              ? 'Non renseignée'
              : _date(item.goal.targetDate!),
        ),
        _DetailValue(
          label: 'Date prévisionnelle',
          value: projected == null ? 'Non calculable' : _date(projected),
        ),
        if (pace != null)
          _DetailValue(label: 'Rythme requis', value: '${_money(pace)} / mois'),
        if (item.goal.notes != null)
          _DetailValue(label: 'Notes', value: item.goal.notes!),
        if (item.goal.closureReason != null)
          _DetailValue(
            label: 'Motif de clôture',
            value: item.goal.closureReason!,
          ),
      ],
    );
  }
}

class _DetailValue extends StatelessWidget {
  const _DetailValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 230,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.xxs),
        Text(value),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final SavingsGoalStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SavingsGoalStatus.active => AppColors.success,
      SavingsGoalStatus.completed => AppColors.success,
      SavingsGoalStatus.paused => AppColors.warning,
      SavingsGoalStatus.cancelled => AppColors.danger,
      SavingsGoalStatus.planned => AppColors.info,
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

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => DesktopSection(
    title: 'Aucun objectif pour le moment',
    subtitle:
        'Créez un objectif et reliez-le à une enveloppe dédiée. Aucun solde ne sera créé ou déplacé.',
    action: FilledButton.icon(
      onPressed: onCreate,
      icon: const Icon(Icons.add),
      label: const Text('Créer un objectif'),
    ),
    child: const Text(
      'La progression affichée suivra automatiquement le solde canonique de l’enveloppe choisie.',
    ),
  );
}

class _GoalEditorResult {
  const _GoalEditorResult({required this.draft, required this.initialStatus});

  final SavingsGoalDraft draft;
  final SavingsGoalStatus initialStatus;
}

class _GoalEditorDialog extends StatefulWidget {
  const _GoalEditorDialog({required this.current, required this.envelopes});

  final SavingsGoal? current;
  final List<RemoteEnvelopeBalance> envelopes;

  @override
  State<_GoalEditorDialog> createState() => _GoalEditorDialogState();
}

class _GoalEditorDialogState extends State<_GoalEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late final TextEditingController _targetDate;
  late final TextEditingController _monthly;
  late final TextEditingController _priority;
  late final TextEditingController _notes;
  late SavingsGoalType _type;
  late SavingsGoalStatus _status;
  String? _envelopeId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final goal = widget.current;
    _name = TextEditingController(text: goal?.name ?? '');
    _target = TextEditingController(
      text: goal == null ? '' : _number(goal.targetAmount),
    );
    _targetDate = TextEditingController(
      text: goal?.targetDate == null ? '' : _date(goal!.targetDate!),
    );
    _monthly = TextEditingController(
      text: goal?.monthlyTarget == null ? '' : _number(goal!.monthlyTarget!),
    );
    _priority = TextEditingController(text: '${goal?.priority ?? 0}');
    _notes = TextEditingController(text: goal?.notes ?? '');
    _type = goal?.type ?? SavingsGoalType.custom;
    _status = goal?.status == SavingsGoalStatus.active
        ? SavingsGoalStatus.active
        : SavingsGoalStatus.planned;
    _envelopeId = goal?.fundingEnvelopeId;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _targetDate.dispose();
    _monthly.dispose();
    _priority.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final target = _parseMoney(_target.text);
    final monthly = _monthly.text.trim().isEmpty
        ? null
        : _parseMoney(_monthly.text);
    final date = _targetDate.text.trim().isEmpty
        ? null
        : _parseDate(_targetDate.text);
    final priority = int.tryParse(_priority.text.trim());
    if (target == null ||
        (monthly == null && _monthly.text.trim().isNotEmpty) ||
        (date == null && _targetDate.text.trim().isNotEmpty) ||
        priority == null ||
        _envelopeId == null) {
      setState(
        () => _error =
            'Vérifiez le montant, la date (JJ/MM/AAAA), la priorité et l’enveloppe.',
      );
      return;
    }
    final draft = SavingsGoalDraft(
      name: _name.text,
      type: _type,
      targetAmount: target,
      targetDate: date,
      priority: priority,
      fundingEnvelopeId: _envelopeId!,
      monthlyTarget: monthly,
      notes: _notes.text,
    );
    final error = draft.validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(
      context,
    ).pop(_GoalEditorResult(draft: draft, initialStatus: _status));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.current == null ? 'Nouvel objectif' : 'Modifier l’objectif',
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nom de l’objectif *',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<SavingsGoalType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type *'),
              items: [
                for (final type in SavingsGoalType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Montant cible (MAD) *',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _envelopeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Enveloppe dédiée *',
              ),
              hint: const Text('Choisir une enveloppe ordinaire active'),
              items: [
                for (final envelope in widget.envelopes)
                  DropdownMenuItem(
                    value: envelope.id,
                    child: Text(envelope.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _envelopeId = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _monthly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Cible mensuelle (MAD)',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _targetDate,
              decoration: const InputDecoration(
                labelText: 'Échéance (JJ/MM/AAAA)',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _priority,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Priorité'),
            ),
            if (widget.current == null) ...[
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<SavingsGoalStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Statut initial'),
                items: const [
                  DropdownMenuItem(
                    value: SavingsGoalStatus.planned,
                    child: Text('Prévu'),
                  ),
                  DropdownMenuItem(
                    value: SavingsGoalStatus.active,
                    child: Text('Actif'),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value!),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
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

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String confirmLabel;

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
    content: TextFormField(
      controller: _controller,
      maxLines: 3,
      maxLength: 280,
      decoration: InputDecoration(labelText: widget.label),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Retour'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}

Money? _parseMoney(String input) {
  final normalized = input.trim().replaceAll(' ', '').replaceAll(',', '.');
  final value = double.tryParse(normalized);
  return value == null ? null : Money.fromDirhams(value);
}

DateTime? _parseDate(String input) {
  final parts = input.trim().split('/');
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;
  final value = DateTime(year, month, day);
  return value.year == year && value.month == month && value.day == day
      ? value
      : null;
}

String _number(Money money) =>
    money.dirhams.toStringAsFixed(2).replaceAll('.', ',');

String _money(Money money) => NumberFormat.currency(
  locale: 'fr_FR',
  symbol: 'MAD',
  decimalDigits: 2,
).format(money.dirhams);

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _dateTime(DateTime value) {
  final local = value.toLocal();
  return '${_date(local)} • ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String _historyActionLabel(String action) => switch (action) {
  'created' => 'Objectif créé',
  'updated' => 'Objectif modifié',
  'activated' => 'Objectif activé',
  'paused' => 'Objectif suspendu',
  'resumed' => 'Objectif repris',
  'completed' => 'Objectif clôturé',
  'cancelled' => 'Objectif annulé',
  _ => 'Mise à jour de l’objectif',
};

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Action impossible : $error')));
}
