import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/localization/savings_goals_locale.dart';
import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../financial_availability/application/providers/financial_availability_provider.dart';
import '../../financial_availability/domain/financial_availability.dart';
import '../application/providers/remote_savings_goals_provider.dart';
import '../domain/savings_goal.dart';

class SavingsGoalsPage extends ConsumerWidget {
  const SavingsGoalsPage({super.key});

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    SavingsGoalProgress? current,
  }) async {
    final w = SavingsGoalsWords.of(context);
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
              current == null ? w.text('created') : w.text('updated'),
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
    final w = SavingsGoalsWords.of(context);
    final goals = ref.watch(savingsGoalsProvider);
    final availability = ref.watch(financialAvailabilityProvider).valueOrNull;
    return SafeArea(
      child: goals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: AppSpacing.page,
            child: Text(w.format('read_error', {'error': error})),
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
                    w.text('title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SecondaryInfoText(w.text('intro')),
                  FilledButton.icon(
                    key: const Key('create-savings-goal'),
                    onPressed: () => _openEditor(context, ref),
                    icon: const Icon(Icons.add),
                    label: Text(w.text('new_goal')),
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
                        projection: availability?.goals[item.goal.id],
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
    final w = SavingsGoalsWords.of(context);
    final mustExplain =
        status == SavingsGoalStatus.completed ||
        status == SavingsGoalStatus.cancelled;
    final reason = mustExplain
        ? await showDialog<String>(
            context: context,
            builder: (_) => _ReasonDialog(
              title: status == SavingsGoalStatus.completed
                  ? w.text('close_goal')
                  : w.text('cancel_goal'),
              label: status == SavingsGoalStatus.completed
                  ? w.text('close_reason_optional')
                  : w.text('cancel_reason_optional'),
              confirmLabel: status == SavingsGoalStatus.completed
                  ? w.text('complete')
                  : w.text('cancel_goal'),
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
          SnackBar(
            content: Text(
              w.format('status_saved', {'status': _statusLabel(w, status)}),
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
    final w = SavingsGoalsWords.of(context);
    final goals = ref.watch(savingsGoalsProvider);
    final availability = ref.watch(financialAvailabilityProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(w.text('detail'))),
      body: goals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(w.format('goal_read_error', {'error': error}))),
        data: (items) {
          final matches = items.where((item) => item.goal.id == goalId);
          if (matches.isEmpty) {
            return Center(child: Text(w.text('not_found')));
          }
          final item = matches.single;
          final history = ref.watch(savingsGoalHistoryProvider(goalId));
          return DesktopPageContainer(
            child: ListView(
              children: [
                _GoalSummary(
                  item: item,
                  projection: availability?.goals[item.goal.id],
                ),
                const SizedBox(height: AppSpacing.md),
                DesktopSection(
                  title: w.text('information'),
                  subtitle: w.text('no_financial_entry'),
                  action: item.goal.status.isClosed
                      ? null
                      : FilledButton.tonalIcon(
                          onPressed: () => _openEdit(context, ref, item),
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(w.text('edit')),
                        ),
                  child: _GoalDetails(
                    item: item,
                    projection: availability?.goals[item.goal.id],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (!item.goal.status.isClosed)
                  DesktopSection(
                    title: w.text('actions'),
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
                                  ? w.text('resume')
                                  : w.text('activate'),
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
                            label: Text(w.text('pause')),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _changeStatus(
                            context,
                            ref,
                            item,
                            SavingsGoalStatus.completed,
                          ),
                          icon: const Icon(Icons.task_alt_outlined),
                          label: Text(w.text('complete')),
                        ),
                        TextButton.icon(
                          onPressed: () => _changeStatus(
                            context,
                            ref,
                            item,
                            SavingsGoalStatus.cancelled,
                          ),
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(w.text('cancel')),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                DesktopSection(
                  title: w.text('business_history'),
                  subtitle: w.text('history_notice'),
                  child: history.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: CircularProgressIndicator(),
                    ),
                    error: (error, _) =>
                        Text(w.format('history_error', {'error': error})),
                    data: (entries) => entries.isEmpty
                        ? Text(w.text('history_empty'))
                        : Column(
                            children: [
                              for (final entry in entries)
                                CompactListRow(
                                  title: _historyActionLabel(w, entry.action),
                                  subtitle: [
                                    _dateTime(context, entry.createdAt),
                                    w.format('performed_by', {
                                      'actor': entry.actorName,
                                    }),
                                    if (entry.reason != null)
                                      w.format('reason', {
                                        'reason': entry.reason!,
                                      }),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(SavingsGoalsWords.of(context).text('updated')),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.item, required this.onTap, this.projection});

  final SavingsGoalProgress item;
  final VoidCallback onTap;
  final GoalFundingProjection? projection;

  @override
  Widget build(BuildContext context) {
    final w = SavingsGoalsWords.of(context);
    return Card(
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
              Text(
                w.format('type_envelope', {
                  'type': _typeLabel(w, item.goal.type),
                  'envelope': item.envelopeName,
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                w.format('accumulated', {
                  'amount': _money(context, item.accumulated),
                }),
              ),
              Text(
                w.format('target', {
                  'amount': _money(context, item.goal.targetAmount),
                }),
              ),
              Text(
                w.format('remaining', {
                  'amount': _money(context, item.remaining),
                }),
              ),
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(value: item.progressForIndicator),
              const SizedBox(height: AppSpacing.xs),
              Text(
                NumberFormat.percentPattern(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(item.progressRatio),
              ),
              if (item.isFinancialTargetReached) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  w.text('target_reached'),
                  style: const TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (item.goal.targetDate != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  w.format('due', {
                    'date': _date(context, item.goal.targetDate!),
                  }),
                ),
              ],
              Text(
                w.format('secured', {
                  'amount': _money(
                    context,
                    projection?.securedFunding ?? item.accumulated,
                  ),
                }),
              ),
              Text(
                w.format('remaining_funding', {
                  'amount': _money(
                    context,
                    projection?.remaining ?? item.remaining,
                  ),
                }),
              ),
              if (projection?.completionDate case final date?)
                Text(w.format('fundable_on', {'date': _date(context, date)}))
              else if (projection?.reason case final reason?)
                Text(reason),
              if (projection != null)
                Text(
                  projection!.reliability == ProjectionReliability.estimated
                      ? w.text('estimated_projection')
                      : w.text('unavailable_projection'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalSummary extends StatelessWidget {
  const _GoalSummary({required this.item, this.projection});

  final SavingsGoalProgress item;
  final GoalFundingProjection? projection;

  @override
  Widget build(BuildContext context) {
    final w = SavingsGoalsWords.of(context);
    return DesktopSection(
      title: item.goal.name,
      subtitle: w.format('linked_envelope', {
        'type': _typeLabel(w, item.goal.type),
        'envelope': item.envelopeName,
      }),
      action: _StatusBadge(status: item.goal.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            w.format('progress', {
              'current': _money(context, item.accumulated),
              'target': _money(context, item.goal.targetAmount),
            }),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: item.progressForIndicator),
          const SizedBox(height: AppSpacing.xs),
          Text(
            w.format('progress_remaining', {
              'percent': (item.progressRatio * 100).toStringAsFixed(1),
              'remaining': _money(context, item.remaining),
            }),
          ),
          if (projection != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              w.format('funding_summary', {
                'secured': _money(context, projection!.securedFunding),
                'remaining': _money(context, projection!.remaining),
              }),
            ),
            if (projection!.reason != null) Text(projection!.reason!),
            Text(
              projection!.reliability == ProjectionReliability.estimated
                  ? 'Projection estimée selon le plan PRIOS actif.'
                  : 'Projection non calculable avec les données disponibles.',
            ),
          ],
          if (item.isFinancialTargetReached) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              w.text('reached_explicit'),
              style: const TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GoalDetails extends StatelessWidget {
  const _GoalDetails({required this.item, this.projection});

  final SavingsGoalProgress item;
  final GoalFundingProjection? projection;

  @override
  Widget build(BuildContext context) {
    final w = SavingsGoalsWords.of(context);
    final now = DateTime.now();
    final projected = projection?.completionDate;
    final pace = item.requiredMonthlyPace(now);
    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.md,
      children: [
        _DetailValue(label: w.text('priority'), value: '${item.goal.priority}'),
        _DetailValue(
          label: w.text('monthly_target'),
          value: item.goal.monthlyTarget == null
              ? w.text('not_provided')
              : _money(context, item.goal.monthlyTarget!),
        ),
        _DetailValue(
          label: w.text('due').split(':').first,
          value: item.goal.targetDate == null
              ? w.text('not_provided')
              : _date(context, item.goal.targetDate!),
        ),
        _DetailValue(
          label: w.text('forecast_date'),
          value: projected == null
              ? (projection?.reason ?? w.text('projection_missing'))
              : _date(context, projected),
        ),
        if (pace != null)
          _DetailValue(
            label: w.text('required_pace'),
            value: w.format('per_month', {'amount': _money(context, pace)}),
          ),
        if (item.goal.notes != null)
          _DetailValue(label: w.text('notes'), value: item.goal.notes!),
        if (item.goal.closureReason != null)
          _DetailValue(
            label: w.text('closure_reason'),
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
        _statusLabel(SavingsGoalsWords.of(context), status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final w = SavingsGoalsWords.of(context);
    return DesktopSection(
      title: w.text('empty_title'),
      subtitle: w.text('empty_subtitle'),
      action: FilledButton.icon(
        onPressed: onCreate,
        icon: const Icon(Icons.add),
        label: Text(w.text('create_goal')),
      ),
      child: Text(w.text('empty_body')),
    );
  }
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
      text: goal?.targetDate == null ? '' : _inputDate(goal!.targetDate!),
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
    final w = SavingsGoalsWords.of(context);
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
      setState(() => _error = w.text('form_error'));
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
      setState(() => _error = w.text('form_error'));
      return;
    }
    Navigator.of(
      context,
    ).pop(_GoalEditorResult(draft: draft, initialStatus: _status));
  }

  @override
  Widget build(BuildContext context) {
    final w = SavingsGoalsWords.of(context);
    return AlertDialog(
      title: Text(
        widget.current == null ? w.text('new_goal') : w.text('edit_goal'),
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
                decoration: InputDecoration(labelText: w.text('goal_name')),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<SavingsGoalType>(
                initialValue: _type,
                decoration: InputDecoration(labelText: w.text('type')),
                items: [
                  for (final type in SavingsGoalType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_typeLabel(w, type)),
                    ),
                ],
                onChanged: (value) => setState(() => _type = value!),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: w.text('target_amount')),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _envelopeId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: w.text('dedicated_envelope'),
                ),
                hint: Text(w.text('choose_envelope')),
                items: [
                  for (final envelope in widget.envelopes)
                    DropdownMenuItem(
                      value: envelope.id,
                      child: Text(
                        envelope.name,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                decoration: InputDecoration(
                  labelText: w.text('monthly_amount'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _targetDate,
                decoration: InputDecoration(labelText: w.text('due_format')),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _priority,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: w.text('priority')),
              ),
              if (widget.current == null) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<SavingsGoalStatus>(
                  initialValue: _status,
                  decoration: InputDecoration(
                    labelText: w.text('initial_status'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: SavingsGoalStatus.planned,
                      child: Text(w.text('planned')),
                    ),
                    DropdownMenuItem(
                      value: SavingsGoalStatus.active,
                      child: Text(w.text('active')),
                    ),
                  ],
                  onChanged: (value) => setState(() => _status = value!),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(labelText: w.text('notes')),
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
          child: Text(w.text('cancel')),
        ),
        FilledButton(onPressed: _submit, child: Text(w.text('save'))),
      ],
    );
  }
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
        child: Text(SavingsGoalsWords.of(context).text('back')),
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

String _money(BuildContext context, Money money) => NumberFormat.currency(
  locale: Localizations.localeOf(context).toLanguageTag(),
  symbol: 'MAD',
  decimalDigits: 2,
).format(money.dirhams);

String _date(BuildContext context, DateTime value) => DateFormat.yMd(
  Localizations.localeOf(context).toLanguageTag(),
).format(value);

String _inputDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _dateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  return '${_date(context, local)} • ${DateFormat.Hm(Localizations.localeOf(context).toLanguageTag()).format(local)}';
}

String _historyActionLabel(SavingsGoalsWords w, String action) =>
    switch (action) {
      'created' => w.text('history_created'),
      'updated' => w.text('history_updated'),
      'activated' => w.text('history_activated'),
      'paused' => w.text('history_paused'),
      'resumed' => w.text('history_resumed'),
      'completed' => w.text('history_completed'),
      'cancelled' => w.text('history_cancelled'),
      _ => w.text('history_other'),
    };

String _statusLabel(SavingsGoalsWords w, SavingsGoalStatus status) =>
    w.text('status_${status.name}');

String _typeLabel(SavingsGoalsWords w, SavingsGoalType type) => switch (type) {
  SavingsGoalType.car => w.text('car'),
  SavingsGoalType.travel => w.text('travel'),
  SavingsGoalType.majorPurchase => w.text('major_purchase'),
  SavingsGoalType.homeDownPayment => w.text('home_down_payment'),
  SavingsGoalType.custom => w.text('custom'),
  SavingsGoalType.emergencyFund => w.text('emergency'),
};

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        SavingsGoalsWords.of(context).format('action_error', {'error': error}),
      ),
    ),
  );
}
