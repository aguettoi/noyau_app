import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/budget_runs_locale.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_account_balances_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/application/providers/remote_transactions_provider.dart';
import '../../finance/domain/financial_account.dart';
import '../application/providers/remote_budget_provider.dart';
import '../domain/budget_intelligence.dart';

String _rt(BuildContext context, String key) =>
    BudgetRunWords.of(context).text(key);
String _rf(BuildContext context, String key, Map<String, Object> values) =>
    BudgetRunWords.of(context).format(key, values);

class BudgetRunsPage extends ConsumerWidget {
  const BudgetRunsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(remoteBudgetRunsProvider);
    final periods = ref.watch(remoteBudgetPeriodsProvider);
    final scenarios = ref.watch(remoteBudgetScenariosProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_rt(context, 'run.history'))),
      body: runs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(_rt(context, 'run.load_error'))),
        data: (items) => ListView(
          padding: AppSpacing.page,
          children: [
            if (items.isEmpty) Text(_rt(context, 'run.empty')),
            ...items.map(
              (run) => Card(
                child: ListTile(
                  title: Text(_status(context, run.status)),
                  subtitle: Text(
                    _rf(context, 'run.summary', {
                      'period': _periodLabel(
                        context,
                        periods.valueOrNull,
                        run.periodId,
                      ),
                      'scenario': _scenarioLabel(
                        context,
                        scenarios.valueOrNull,
                        run.scenarioId,
                      ),
                      'version': run.scenarioVersionId == null
                          ? ''
                          : _rt(context, 'run.programmed'),
                      'available': _money(run.availableCents),
                      'total': _money(run.totalCents),
                      'remaining': _money(run.remainingCents),
                    }),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BudgetRunDetailPage(runId: run.id),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BudgetRunDetailPage extends ConsumerStatefulWidget {
  const BudgetRunDetailPage({super.key, required this.runId});
  final String runId;

  @override
  ConsumerState<BudgetRunDetailPage> createState() =>
      _BudgetRunDetailPageState();
}

class _BudgetRunDetailPageState extends ConsumerState<BudgetRunDetailPage> {
  bool _loading = false;
  bool _approved = false;
  bool _applied = false;
  String? _error;
  String? _applyKey;

  Future<void> _approve(RemoteBudgetRun run) async {
    if (_loading) return;
    final accepted = await _confirm(
      title: _rt(context, 'run.approve_title'),
      body: _rt(context, 'run.approve_hint'),
      action: _rt(context, 'run.approve'),
    );
    if (!accepted || !mounted) return;
    setState(() => _loading = true);
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      await repository.approveRun(run.id);
      if (mounted) setState(() => _approved = true);
      ref.invalidate(remoteBudgetRunsProvider);
      ref.invalidate(budgetApprovalProgressProvider(run.id));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_rt(context, 'run.approved'))));
      }
    } catch (_) {
      if (mounted) setState(() => _error = _rt(context, 'run.approve_error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _apply(RemoteBudgetRun run) async {
    if (_loading) return;
    final accounts = await ref.read(remoteAccountsProvider.future);
    final balances = await ref.read(remoteAccountBalancesProvider.future);
    final lines = await ref.read(remoteBudgetRunLinesProvider(run.id).future);
    final envelopes = await ref.read(remoteEnvelopeHistoryProvider.future);
    if (!mounted) return;
    final ordinary = accounts
        .where((account) => !account.isSystem && !account.isArchived)
        .toList();
    if (ordinary.isEmpty) {
      setState(() => _error = _rt(context, 'run.no_account'));
      return;
    }
    final funding = await showDialog<List<BudgetRunFunding>>(
      context: context,
      builder: (_) => BudgetFundingDistributionDialog(
        lines: lines.where((line) => line.plannedCents > 0).toList(),
        accounts: ordinary,
        balancesCents: {
          for (final entry in balances.entries)
            entry.key: entry.value.minorUnits,
        },
        envelopeNames: {
          for (final envelope in envelopes) envelope.id: envelope.name,
        },
      ),
    );
    if (funding == null || !mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BudgetFundingConfirmationDialog(
        funding: funding,
        accounts: ordinary,
        envelopeNames: {
          for (final envelope in envelopes) envelope.id: envelope.name,
        },
        totalCents: run.totalCents,
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _applyKey ??= _uuid();
    });
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      await repository.applyRunWithFunding(
        runId: run.id,
        funding: funding,
        idempotencyKey: _applyKey!,
      );
      if (mounted) setState(() => _applied = true);
      _refreshAfterApply();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_rt(context, 'run.applied'))));
      }
    } catch (_) {
      if (mounted) setState(() => _error = _rt(context, 'run.apply_error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_rt(context, 'run.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _refreshAfterApply() {
    ref.invalidate(remoteBudgetRunsProvider);
    ref.invalidate(remoteBudgetRunLinesProvider(widget.runId));
    ref.invalidate(remoteBudgetReportingProvider);
    ref.invalidate(remoteEnvelopeBalancesProvider);
    ref.invalidate(remoteEnvelopeHistoryProvider);
    ref.invalidate(remoteTransactionsProvider);
    ref.invalidate(remoteAccountBalancesProvider);
    ref.invalidate(remoteAccountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final runs = ref.watch(remoteBudgetRunsProvider);
    final lines = ref.watch(remoteBudgetRunLinesProvider(widget.runId));
    final envelopes = ref.watch(remoteEnvelopeHistoryProvider);
    final periods = ref.watch(remoteBudgetPeriodsProvider);
    final scenarios = ref.watch(remoteBudgetScenariosProvider);
    final approval = ref.watch(budgetApprovalProgressProvider(widget.runId));
    return runs.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) =>
          Scaffold(body: Center(child: Text(_rt(context, 'run.unavailable')))),
      data: (all) {
        final run = all.where((item) => item.id == widget.runId).firstOrNull;
        if (run == null) {
          return Scaffold(
            body: Center(child: Text(_rt(context, 'run.not_found'))),
          );
        }
        final blocked = run.remainingCents < 0;
        return Scaffold(
          appBar: AppBar(title: Text(_rt(context, 'run.detail'))),
          body: ListView(
            padding: AppSpacing.page,
            children: [
              Text(
                _status(context, run.status),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                _rf(context, 'run.period', {
                  'value': _periodLabel(
                    context,
                    periods.valueOrNull,
                    run.periodId,
                  ),
                }),
              ),
              Text(
                _rf(context, 'run.scenario', {
                  'value': _scenarioLabel(
                    context,
                    scenarios.valueOrNull,
                    run.scenarioId,
                  ),
                }),
              ),
              if (run.scenarioVersionId != null)
                Text(_rt(context, 'run.snapshot_version')),
              Text(
                _rf(context, 'run.resources', {
                  'value': _money(run.availableCents),
                }),
              ),
              Text(
                _rf(context, 'run.allocated', {
                  'value': _money(run.totalCents),
                }),
              ),
              Text(
                _rf(context, 'run.remaining', {
                  'value': _money(run.remainingCents),
                }),
              ),
              Text(
                _rf(context, 'run.simulation', {'value': _date(run.createdAt)}),
              ),
              if (run.summary['monthly_snapshot'] == true) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _rt(context, 'run.monthly_snapshot'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                _SnapshotSummary(summary: run.summary),
              ],
              if (run.approvedAt != null)
                Text(
                  _rf(context, 'run.validation', {
                    'value': _date(run.approvedAt!),
                  }),
                ),
              if (run.status == 'simulated')
                Text(
                  approval.when(
                    data: (value) => value.complete
                        ? _rt(context, 'run.validations_complete')
                        : _rf(context, 'run.validations_pending', {
                            'approved': value.approved,
                            'required': value.required,
                          }),
                    loading: () => _rt(context, 'run.validations_loading'),
                    error: (_, _) =>
                        _rt(context, 'run.validations_unavailable'),
                  ),
                ),
              if (run.appliedAt != null)
                Text(
                  _rf(context, 'run.application', {
                    'value': _date(run.appliedAt!),
                  }),
                ),
              if (blocked) Text(_rt(context, 'run.overallocated')),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _rt(context, 'run.lines'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _RunLines(lines: lines, envelopes: envelopes),
              const SizedBox(height: AppSpacing.md),
              if (run.status == 'simulated' && !_approved)
                FilledButton(
                  key: const Key('approve-budget-run'),
                  onPressed: _loading || blocked ? null : () => _approve(run),
                  child: Text(
                    _rt(
                      context,
                      _loading ? 'run.approving' : 'run.approve_title',
                    ),
                  ),
                ),
              if (run.status == 'approved' && !_applied)
                FilledButton(
                  key: const Key('apply-budget-run'),
                  onPressed: _loading || blocked ? null : () => _apply(run),
                  child: Text(
                    _rt(
                      context,
                      _loading ? 'run.applying' : 'run.apply_allocations',
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class BudgetFundingDistributionDialog extends StatefulWidget {
  const BudgetFundingDistributionDialog({
    super.key,
    required this.lines,
    required this.accounts,
    required this.balancesCents,
    required this.envelopeNames,
  });

  final List<RemoteBudgetRunLine> lines;
  final List<FinancialAccount> accounts;
  final Map<String, int> balancesCents;
  final Map<String, String> envelopeNames;

  @override
  State<BudgetFundingDistributionDialog> createState() =>
      _BudgetFundingDistributionDialogState();
}

class _BudgetFundingDistributionDialogState
    extends State<BudgetFundingDistributionDialog> {
  late List<_FundingDraft> _drafts;

  @override
  void initState() {
    super.initState();
    _drafts = widget.lines
        .map(
          (line) => _FundingDraft(
            runLineId: line.id,
            envelopeId: line.envelopeId,
            amountCents: line.plannedCents,
          ),
        )
        .toList(growable: true);
  }

  int get _budgetTotal =>
      widget.lines.fold(0, (sum, line) => sum + line.plannedCents);
  int get _fundedTotal =>
      _drafts.fold(0, (sum, draft) => sum + draft.amountCents);
  int get _remaining => _budgetTotal - _fundedTotal;

  Map<String, int> get _requestedCentsByAccount {
    final requested = <String, int>{};
    for (final draft in _drafts) {
      final accountId = draft.accountId;
      if (accountId != null) {
        requested[accountId] = (requested[accountId] ?? 0) + draft.amountCents;
      }
    }
    return requested;
  }

  bool get _hasInsufficientAccountBalance => _requestedCentsByAccount.entries
      .any((entry) => entry.value > (widget.balancesCents[entry.key] ?? 0));

  bool get _isValid {
    if (_drafts.isEmpty || _remaining != 0) return false;
    for (final line in widget.lines) {
      final funded = _drafts
          .where((draft) => draft.runLineId == line.id)
          .fold(0, (sum, draft) => sum + draft.amountCents);
      if (funded != line.plannedCents) return false;
    }
    return !_hasInsufficientAccountBalance &&
        _drafts.every(
          (draft) => draft.accountId != null && draft.amountCents > 0,
        );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_rt(context, 'run.funding')),
      content: SizedBox(
        width: 860,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_rf(context, 'run.budget', {'value': _money(_budgetTotal)})),
              Text(_rf(context, 'run.funded', {'value': _money(_fundedTotal)})),
              Text(
                _rf(context, 'run.to_fund', {'value': _money(_remaining)}),
                style: TextStyle(
                  color: _remaining == 0
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ..._drafts.asMap().entries.map((entry) {
                final index = entry.key;
                final draft = entry.value;
                final account = draft.accountId == null
                    ? null
                    : widget.accounts
                          .where((item) => item.id == draft.accountId)
                          .firstOrNull;
                final requested = draft.accountId == null
                    ? 0
                    : _requestedCentsByAccount[draft.accountId] ?? 0;
                final available = draft.accountId == null
                    ? 0
                    : widget.balancesCents[draft.accountId] ?? 0;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 330,
                          child: DropdownButtonFormField<String>(
                            key: Key('funding-account-$index'),
                            initialValue: draft.accountId,
                            isExpanded: true,
                            itemHeight: 76,
                            menuMaxHeight: 360,
                            decoration: InputDecoration(
                              labelText: _rt(context, 'run.account'),
                            ),
                            items: widget.accounts
                                .map(
                                  (account) => DropdownMenuItem(
                                    value: account.id,
                                    child: _FundingAccountMenuItem(
                                      account: account,
                                      balanceCents:
                                          widget.balancesCents[account.id] ?? 0,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            selectedItemBuilder: (context) => widget.accounts
                                .map(
                                  (account) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      _rf(context, 'run.account_balance', {
                                        'account': account.name,
                                        'balance': _money(
                                          widget.balancesCents[account.id] ?? 0,
                                        ),
                                      }),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) => setState(
                              () => _drafts[index] = draft.copyWith(
                                accountId: value,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 190,
                          child: DropdownButtonFormField<String>(
                            key: Key('funding-envelope-$index'),
                            initialValue: draft.runLineId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: _rt(context, 'run.envelope'),
                            ),
                            items: widget.lines
                                .map(
                                  (line) => DropdownMenuItem(
                                    value: line.id,
                                    child: Text(
                                      _rf(context, 'run.planned', {
                                        'envelope':
                                            widget.envelopeNames[line
                                                .envelopeId] ??
                                            _rt(context, 'run.envelope'),
                                        'value': _money(line.plannedCents),
                                      }),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            selectedItemBuilder: (context) => widget.lines
                                .map(
                                  (line) => Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      widget.envelopeNames[line.envelopeId] ??
                                          _rt(context, 'run.envelope'),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (lineId) {
                              if (lineId == null) return;
                              final line = widget.lines.firstWhere(
                                (candidate) => candidate.id == lineId,
                              );
                              setState(
                                () => _drafts[index] = draft.copyWith(
                                  runLineId: line.id,
                                  envelopeId: line.envelopeId,
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(
                          width: 125,
                          child: TextFormField(
                            key: Key('funding-amount-$index'),
                            initialValue: (draft.amountCents / 100).toString(),
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _rt(context, 'run.amount'),
                            ),
                            onChanged: (value) => setState(
                              () => _drafts[index] = draft.copyWith(
                                amountCents: _fundingCents(value),
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          key: Key('remove-funding-$index'),
                          onPressed: _drafts.length == 1
                              ? null
                              : () => setState(() => _drafts.removeAt(index)),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        if (account != null)
                          SizedBox(
                            width: 640,
                            child: _FundingAccountAvailability(
                              accountName: account.name,
                              availableCents: available,
                              requestedCents: requested,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              TextButton.icon(
                key: const Key('add-funding-line'),
                onPressed: () => setState(
                  () => _drafts.add(
                    _FundingDraft(
                      runLineId: widget.lines.first.id,
                      envelopeId: widget.lines.first.envelopeId,
                      amountCents: 0,
                    ),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: Text(_rt(context, 'run.add_line')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_rt(context, 'run.cancel')),
        ),
        FilledButton(
          key: const Key('confirm-funding-distribution'),
          onPressed: !_isValid
              ? null
              : () => Navigator.of(context).pop(
                  _drafts
                      .map(
                        (draft) => BudgetRunFunding(
                          runLineId: draft.runLineId,
                          sourceAccountId: draft.accountId!,
                          envelopeId: draft.envelopeId,
                          amountCents: draft.amountCents,
                        ),
                      )
                      .toList(growable: false),
                ),
          child: Text(
            _rf(context, 'run.confirm_apply', {'value': _money(_budgetTotal)}),
          ),
        ),
      ],
    );
  }
}

class BudgetFundingConfirmationDialog extends StatelessWidget {
  const BudgetFundingConfirmationDialog({
    super.key,
    required this.funding,
    required this.accounts,
    required this.envelopeNames,
    required this.totalCents,
    required this.onCancel,
    required this.onConfirm,
  });

  final List<BudgetRunFunding> funding;
  final List<FinancialAccount> accounts;
  final Map<String, String> envelopeNames;
  final int totalCents;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final accountsById = {for (final account in accounts) account.id: account};
    return AlertDialog(
      title: Text(
        _rf(context, 'run.confirm_apply', {'value': _money(totalCents)}),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _rt(context, 'run.distribution'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              ...funding.map((item) {
                final account = accountsById[item.sourceAccountId];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(account?.name ?? _rt(context, 'run.account')),
                      Text(
                        _rf(context, 'run.to_envelope', {
                          'envelope':
                              envelopeNames[item.envelopeId] ??
                              _rt(context, 'run.envelope'),
                        }),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        _money(item.amountCents),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                );
              }),
              const Divider(),
              Text(
                _rf(context, 'run.total_apply', {'value': _money(totalCents)}),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(_rt(context, 'run.cancel')),
        ),
        FilledButton(
          onPressed: onConfirm,
          child: Text(_rt(context, 'run.apply')),
        ),
      ],
    );
  }
}

class _FundingAccountMenuItem extends StatelessWidget {
  const _FundingAccountMenuItem({
    required this.account,
    required this.balanceCents,
  });

  final FinancialAccount account;
  final int balanceCents;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(account.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          _accountType(context, account.type),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          _rf(context, 'run.available_balance', {
            'value': _money(balanceCents),
          }),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _FundingAccountAvailability extends StatelessWidget {
  const _FundingAccountAvailability({
    required this.accountName,
    required this.availableCents,
    required this.requestedCents,
  });

  final String accountName;
  final int availableCents;
  final int requestedCents;

  @override
  Widget build(BuildContext context) {
    final missing = requestedCents - availableCents;
    final insufficient = missing > 0;
    final color = insufficient
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      container: true,
      label: insufficient
          ? _rf(context, 'run.insufficient_label', {'account': accountName})
          : _rf(context, 'run.available_label', {'account': accountName}),
      child: Text(
        insufficient
            ? _rf(context, 'run.insufficient', {
                'account': accountName,
                'available': _money(availableCents),
                'requested': _money(requestedCents),
                'missing': _money(missing),
              })
            : _rf(context, 'run.requested', {
                'available': _money(availableCents),
                'requested': _money(requestedCents),
              }),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

class _FundingDraft {
  const _FundingDraft({
    required this.runLineId,
    required this.envelopeId,
    required this.amountCents,
    this.accountId,
  });
  final String runLineId;
  final String envelopeId;
  final int amountCents;
  final String? accountId;

  _FundingDraft copyWith({
    String? runLineId,
    String? envelopeId,
    int? amountCents,
    String? accountId,
  }) => _FundingDraft(
    runLineId: runLineId ?? this.runLineId,
    envelopeId: envelopeId ?? this.envelopeId,
    amountCents: amountCents ?? this.amountCents,
    accountId: accountId ?? this.accountId,
  );
}

int _fundingCents(String value) {
  final amount = double.tryParse(value.replaceAll(',', '.'));
  return amount == null ? 0 : (amount * 100).round();
}

String _accountType(BuildContext context, FinancialAccountType type) =>
    switch (type) {
      FinancialAccountType.bank => _rt(context, 'run.bank'),
      FinancialAccountType.cash => _rt(context, 'run.cash'),
      FinancialAccountType.savings => _rt(context, 'run.savings'),
      FinancialAccountType.debt => _rt(context, 'run.debt'),
    };

class _SnapshotSummary extends StatelessWidget {
  const _SnapshotSummary({required this.summary});
  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context) {
    final kpis = summary['kpis'] is Map
        ? Map<String, Object?>.from(summary['kpis'] as Map)
        : const <String, Object?>{};
    final warnings = summary['warnings'] is List
        ? List<Object?>.from(summary['warnings'] as List)
        : const <Object?>[];
    final blockers = summary['blockers'] is List
        ? List<Object?>.from(summary['blockers'] as List)
        : const <Object?>[];
    int cents(String key) => (kpis[key] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _rf(context, 'run.income', {'value': _money(cents('income_cents'))}),
        ),
        Text(
          _rf(context, 'run.personal', {
            'value': _money(cents('personal_charges_cents')),
          }),
        ),
        Text(
          _rf(context, 'run.common', {
            'value': _money(cents('common_charges_cents')),
          }),
        ),
        Text(
          _rf(context, 'run.savings_kpi', {
            'value': _money(cents('savings_cents')),
          }),
        ),
        Text(
          _rf(context, 'run.remaining_kpi', {
            'value': _money(cents('remaining_cents')),
          }),
        ),
        if (warnings.isNotEmpty)
          Text(_rf(context, 'run.warnings', {'value': warnings.join(' • ')})),
        if (blockers.isNotEmpty)
          Text(_rf(context, 'run.blockers', {'value': blockers.join(' • ')})),
      ],
    );
  }
}

class _RunLines extends StatelessWidget {
  const _RunLines({required this.lines, required this.envelopes});
  final AsyncValue<List<RemoteBudgetRunLine>> lines;
  final AsyncValue<List<dynamic>> envelopes;

  @override
  Widget build(BuildContext context) => lines.when(
    loading: () => const LinearProgressIndicator(),
    error: (_, _) => Text(_rt(context, 'run.lines_error')),
    data: (items) => envelopes.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(_rt(context, 'run.envelopes_error')),
      data: (all) {
        final names = {for (final envelope in all) envelope.id: envelope.name};
        return Column(
          children: items
              .map(
                (line) => Card(
                  child: ListTile(
                    title: Text(
                      names[line.envelopeId] ?? _rt(context, 'run.envelope'),
                    ),
                    subtitle: Text(
                      _rf(context, 'run.line_summary', {
                        'before': _money(line.previousBalanceCents),
                        'rollover': _money(line.rolloverCents),
                        'allocation': _money(line.plannedCents),
                        'projected': _money(line.resultingCents),
                        'warning': line.warning == null
                            ? ''
                            : _rf(context, 'run.warning_suffix', {
                                'warning': line.warning!,
                              }),
                      }),
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    ),
  );
}

String _status(BuildContext context, String value) => switch (value) {
  'simulated' => _rt(context, 'run.simulated'),
  'approved' => _rt(context, 'run.status_approved'),
  'applied' => _rt(context, 'run.status_applied'),
  'cancelled' => _rt(context, 'run.cancelled'),
  _ => _rt(context, 'run.status'),
};

String _money(int cents) {
  final sign = cents < 0 ? '-' : '';
  final absolute = cents.abs();
  final whole = absolute ~/ 100;
  final decimals = (absolute % 100).toString().padLeft(2, '0');
  final digits = whole.toString();
  final grouped = <String>[];
  for (var index = digits.length; index > 0; index -= 3) {
    grouped.add(digits.substring(index > 3 ? index - 3 : 0, index));
  }
  return '$sign${grouped.reversed.join(' ')},$decimals MAD';
}

String _date(DateTime value) =>
    value.toLocal().toIso8601String().substring(0, 10);

String _periodLabel(
  BuildContext context,
  List<RemoteBudgetPeriod>? periods,
  String id,
) =>
    periods?.where((item) => item.id == id).firstOrNull?.label ??
    _rt(context, 'run.period_fallback');
String _scenarioLabel(
  BuildContext context,
  List<dynamic>? scenarios,
  String id,
) =>
    scenarios?.where((item) => item.id == id).firstOrNull?.name as String? ??
    _rt(context, 'run.scenario_fallback');

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
