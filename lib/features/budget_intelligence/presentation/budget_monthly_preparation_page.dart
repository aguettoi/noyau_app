import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/budget_monthly_locale.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/domain/financial_account.dart';
import '../../finance/domain/household_member.dart';
import '../application/budget_simulator.dart';
import '../application/monthly_budget_analysis.dart';
import '../application/programmable_budget_engine.dart';
import '../application/providers/remote_budget_provider.dart';
import '../domain/budget_intelligence.dart';
import 'budget_runs_page.dart';
import 'budget_scenarios_page.dart';
import 'programmable_budget_program_page.dart';

String _mt(BuildContext context, String key) =>
    BudgetMonthlyWords.of(context).text(key);
String _mf(BuildContext context, String key, Map<String, Object> values) =>
    BudgetMonthlyWords.of(context).format(key, values);

String _monthLabel(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatMonthYear(value);

class BudgetMonthlyPreparationPage extends ConsumerStatefulWidget {
  const BudgetMonthlyPreparationPage({super.key, this.initialMonth});

  /// Optional initial period used by callers that already selected a month.
  /// It never creates a period or a budget run by itself.
  final DateTime? initialMonth;

  @override
  ConsumerState<BudgetMonthlyPreparationPage> createState() =>
      _BudgetMonthlyPreparationPageState();
}

class _BudgetMonthlyPreparationPageState
    extends ConsumerState<BudgetMonthlyPreparationPage> {
  String? _scenarioId;
  late DateTime _month;
  bool _preparingPeriod = false;
  String? _periodError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? DateTime.now();
    _month = DateTime(initial.year, initial.month);
  }

  void _shiftMonth(int offset) {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
  }

  Future<void> _pickMonth() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected != null && mounted) {
      setState(() => _month = DateTime(selected.year, selected.month));
    }
  }

  Future<void> _preparePeriod({
    String mode = 'empty',
    String? sourcePeriodId,
  }) async {
    if (_preparingPeriod) return;
    setState(() {
      _preparingPeriod = true;
      _periodError = null;
    });
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      final id = mode == 'empty'
          ? await repository.prepareMonthlyPeriod(_month)
          : await repository.prepareMonthlyPeriodV2(
              _month,
              mode: mode,
              sourcePeriodId: sourcePeriodId,
            );
      ref.read(selectedBudgetPeriodIdProvider.notifier).state = id;
      ref.invalidate(remoteBudgetPeriodsProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _periodError = _mt(context, 'monthly.prepare_error'));
      }
    } finally {
      if (mounted) setState(() => _preparingPeriod = false);
    }
  }

  Future<void> _newScenario() async {
    final initialVersionNote = _mt(context, 'monthly.initial_version');
    final result = await showDialog<BudgetScenario>(
      context: context,
      builder: (_) => const _MonthlyScenarioDialog(),
    );
    if (result == null) return;
    final repository = await ref.read(budgetSupabaseRepositoryProvider.future);
    final id = await repository.saveScenario(result);
    if (id != null) {
      try {
        final versionId = await repository.saveScenarioVersion(
          BudgetScenarioVersion(
            id: '',
            scenarioId: id,
            version: 1,
            createdAt: DateTime.now(),
            notes: initialVersionNote,
          ),
        );
        if (versionId != null) {
          await repository.saveScenario(
            BudgetScenario(
              id: id,
              householdId: repository.householdId,
              name: result.name,
              description: result.description,
              active: result.active,
              currentVersionId: versionId,
            ),
          );
        }
      } on Object {
        // 080006 has not been deployed in every development environment yet.
      }
    }
    ref.invalidate(remoteBudgetScenariosProvider);
    if (mounted) setState(() => _scenarioId = id);
  }

  Future<void> _duplicateScenario(BudgetScenario source) async {
    final result = await showDialog<BudgetScenario>(
      context: context,
      builder: (_) => _MonthlyScenarioDialog(
        title: _mt(context, 'monthly.duplicate'),
        initialName: '${source.name}${_mt(context, 'monthly.copy_suffix')}',
        initialDescription: source.description,
      ),
    );
    if (result == null) return;
    final repository = await ref.read(budgetSupabaseRepositoryProvider.future);
    final newId = await repository.saveScenario(result);
    if (newId == null) return;
    final rules = await ref.read(budgetScenarioRulesProvider(source.id).future);
    final incomes = await ref.read(
      budgetScenarioMemberIncomesProvider(source.id).future,
    );
    for (final rule in rules) {
      await repository.saveRule(
        BudgetScenarioRule(
          id: '',
          scenarioId: newId,
          envelopeId: rule.envelopeId,
          method: rule.method,
          priority: rule.priority,
          rolloverPolicy: rule.rolloverPolicy,
          amountCents: rule.amountCents,
          percentage: rule.percentage,
          minimumCents: rule.minimumCents,
          maximumCents: rule.maximumCents,
          rolloverCapCents: rule.rolloverCapCents,
          fundingSourcePreference: rule.fundingSourcePreference,
          contributionRule: rule.contributionRule,
          notes: rule.notes,
          active: rule.active,
          fundingMode: rule.fundingMode,
          fundingMemberUserId: rule.fundingMemberUserId,
          fundingDefinition: rule.fundingDefinition,
        ),
      );
    }
    for (final income in incomes) {
      await repository.saveMemberIncome(income, newId);
    }
    try {
      final sourceVersions = await ref.read(
        budgetScenarioVersionsProvider(source.id).future,
      );
      final sourceVersion = sourceVersions.firstOrNull;
      if (sourceVersion != null) {
        final versionId = await repository.saveScenarioVersion(
          BudgetScenarioVersion(
            id: '',
            scenarioId: newId,
            version: 1,
            createdAt: DateTime.now(),
            notes: 'Copie de ${source.name}',
          ),
        );
        if (versionId != null) {
          final sourceIds = <String, String>{};
          for (final value in await ref.read(
            budgetScenarioSourcesProvider(sourceVersion.id).future,
          )) {
            final copiedId = await repository.saveSource(
              BudgetSource(
                id: '',
                scenarioVersionId: versionId,
                type: value.type,
                name: value.name,
                expectedCents: value.expectedCents,
                memberUserId: value.memberUserId,
                exceptionalTreatment: value.exceptionalTreatment,
                active: value.active,
              ),
            );
            if (copiedId != null) sourceIds[value.id] = copiedId;
          }
          for (final value in await ref.read(
            budgetScenarioStepsProvider(sourceVersion.id).future,
          )) {
            final newSourceId = sourceIds[value.sourceId];
            if (newSourceId == null) continue;
            await repository.saveStep(
              BudgetAllocationStep(
                id: '',
                scenarioVersionId: versionId,
                order: value.order,
                groupName: value.groupName,
                sourceId: newSourceId,
                envelopeId: value.envelopeId,
                method: value.method,
                contributionKey: value.contributionKey,
                insufficientFundsPolicy: value.insufficientFundsPolicy,
                amountCents: value.amountCents,
                percentage: value.percentage,
                memberUserId: value.memberUserId,
                keyDefinition: value.keyDefinition,
                fundingSourcePreference: value.fundingSourcePreference,
                active: value.active,
              ),
            );
          }
          await repository.saveScenario(
            BudgetScenario(
              id: newId,
              householdId: repository.householdId,
              name: result.name,
              description: result.description,
              active: result.active,
              isDefault: false,
              currentVersionId: versionId,
            ),
          );
        }
      }
    } on Object {
      // The legacy portion remains duplicable before 080006 is deployed.
    }
    ref.invalidate(remoteBudgetScenariosProvider);
    if (mounted) setState(() => _scenarioId = newId);
  }

  @override
  Widget build(BuildContext context) {
    final periods = ref.watch(remoteBudgetPeriodsProvider);
    final scenarios = ref.watch(remoteBudgetScenariosProvider);
    final runs = ref.watch(remoteBudgetRunsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_mt(context, 'monthly.title')),
        actions: [
          IconButton(
            tooltip: _mt(context, 'monthly.history'),
            icon: const Icon(Icons.history_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BudgetRunsPage()),
            ),
          ),
        ],
      ),
      body: periods.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            Center(child: Text(_mt(context, 'monthly.periods_error'))),
        data: (items) {
          final period = items
              .where(
                (item) =>
                    item.startsOn.year == _month.year &&
                    item.startsOn.month == _month.month,
              )
              .firstOrNull;
          if (period == null) {
            final previous = items
                .where((item) => item.startsOn.isBefore(_month))
                .firstOrNull;
            return _UnpreparedMonth(
              month: _month,
              preparing: _preparingPeriod,
              error: _periodError,
              onPrevious: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onPick: _pickMonth,
              onPrepare: () => _preparePeriod(),
              onCopyPrevious: previous == null
                  ? null
                  : () => _preparePeriod(
                      mode: 'copy_previous',
                      sourcePeriodId: previous.id,
                    ),
            );
          }
          return scenarios.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                Center(child: Text(_mt(context, 'monthly.scenarios_error'))),
            data: (all) {
              final active = all
                  .where((item) => item.active)
                  .toList(growable: false);
              final defaultScenario = active
                  .where((item) => item.isDefault)
                  .firstOrNull;
              final currentId = _scenarioId ?? defaultScenario?.id;
              final selected = active
                  .where((item) => item.id == currentId)
                  .firstOrNull;
              final savedRun = runs.valueOrNull
                  ?.where(
                    (item) =>
                        item.periodId == period.id &&
                        item.summary['monthly_snapshot'] == true,
                  )
                  .firstOrNull;
              if (savedRun != null) {
                return _PreparedMonthlySnapshot(
                  run: savedRun,
                  month: period.startsOn,
                  onPrevious: () => _shiftMonth(-1),
                  onNext: () => _shiftMonth(1),
                  onPick: _pickMonth,
                );
              }
              return ListView(
                children: [
                  DesktopPageContainer(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MonthNavigation(
                          month: _month,
                          onPrevious: () => _shiftMonth(-1),
                          onNext: () => _shiftMonth(1),
                          onPick: _pickMonth,
                        ),
                        Card(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_month_outlined),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _mf(context, 'monthly.budget', {
                                          'period': period.label,
                                        }),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      Text(
                                        _mt(context, 'monthly.not_prepared'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (_scenarioId == null && defaultScenario != null)
                          Card(
                            key: const Key('monthly-default-scenario-prompt'),
                            child: ListTile(
                              title: Text(
                                _mf(context, 'monthly.use_default', {
                                  'scenario': defaultScenario.name,
                                  'period': period.label,
                                }),
                              ),
                              subtitle: Text(
                                _mt(context, 'monthly.default_scenario'),
                              ),
                              trailing: FilledButton(
                                key: const Key('use-default-monthly-scenario'),
                                onPressed: () => setState(
                                  () => _scenarioId = defaultScenario.id,
                                ),
                                child: Text(_mt(context, 'monthly.use')),
                              ),
                            ),
                          ),
                        DesktopSection(
                          title: _mt(context, 'monthly.choose'),
                          subtitle: _mt(context, 'monthly.choose_hint'),
                          action: TextButton.icon(
                            key: const Key('new-monthly-scenario'),
                            onPressed: _newScenario,
                            icon: const Icon(Icons.add),
                            label: Text(_mt(context, 'monthly.new_scenario')),
                          ),
                          child: ResponsiveGrid(
                            minItemWidth: 360,
                            children: active
                                .map(
                                  (scenario) => CompactListRow(
                                    title: scenario.name,
                                    subtitle: _mf(
                                      context,
                                      'monthly.scenario_summary',
                                      {
                                        'prefix': scenario.isDefault
                                            ? _mt(
                                                context,
                                                'monthly.default_prefix',
                                              )
                                            : '',
                                        'description':
                                            scenario.description ??
                                            _mt(
                                              context,
                                              'monthly.no_description',
                                            ),
                                      },
                                    ),
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          tooltip: _mt(
                                            context,
                                            'monthly.duplicate_action',
                                          ),
                                          key: Key(
                                            'duplicate-monthly-scenario-${scenario.id}',
                                          ),
                                          onPressed: () =>
                                              _duplicateScenario(scenario),
                                          icon: const Icon(Icons.copy_outlined),
                                        ),
                                        FilledButton(
                                          onPressed: () => setState(
                                            () => _scenarioId = scenario.id,
                                          ),
                                          child: Text(
                                            _mt(context, 'monthly.use'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                        if (active.isEmpty)
                          Text(_mt(context, 'monthly.no_active')),
                        if (selected != null)
                          _MonthlyScenarioContent(
                            key: ValueKey(
                              'monthly-scenario-${period.id}-${selected.id}',
                            ),
                            period: period,
                            scenario: selected,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _UnpreparedMonth extends StatelessWidget {
  const _UnpreparedMonth({
    required this.month,
    required this.preparing,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
    required this.onPrepare,
    this.onCopyPrevious,
    this.error,
  });

  final DateTime month;
  final bool preparing;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onPrepare;
  final VoidCallback? onCopyPrevious;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final label = _monthLabel(context, month);
    return Center(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MonthNavigation(
              month: month,
              onPrevious: onPrevious,
              onNext: onNext,
              onPick: onPick,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(_mt(context, 'monthly.empty')),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  key: const Key('prepare-current-month'),
                  onPressed: preparing ? null : onPrepare,
                  child: Text(
                    _mf(context, 'monthly.empty_month', {'month': label}),
                  ),
                ),
                if (onCopyPrevious != null)
                  FilledButton.icon(
                    key: const Key('copy-previous-month'),
                    onPressed: preparing ? null : onCopyPrevious,
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(
                      preparing
                          ? _mt(context, 'monthly.preparing')
                          : _mt(context, 'monthly.resume'),
                    ),
                  ),
              ],
            ),
            if (error != null) Text(error!),
          ],
        ),
      ),
    );
  }
}

class _MonthNavigation extends StatelessWidget {
  const _MonthNavigation({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        key: const Key('previous-budget-month'),
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left),
      ),
      TextButton(
        key: const Key('pick-budget-month'),
        onPressed: onPick,
        child: Text(
          _monthLabel(context, month),
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      IconButton(
        key: const Key('next-budget-month'),
        onPressed: onNext,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class _MonthlyScenarioContent extends ConsumerStatefulWidget {
  const _MonthlyScenarioContent({
    super.key,
    required this.period,
    required this.scenario,
  });
  final RemoteBudgetPeriod period;
  final BudgetScenario scenario;

  @override
  ConsumerState<_MonthlyScenarioContent> createState() =>
      _MonthlyScenarioContentState();
}

class _MonthlyScenarioContentState
    extends ConsumerState<_MonthlyScenarioContent> {
  bool _saving = false;
  List<BudgetScenarioMemberIncome>? _monthlyIncomeOverrides;
  final Map<String, int> _monthlySourceOverridesCents = {};
  final Map<String, BudgetAllocationStep> _monthlyStepOverrides = {};
  ProgrammableBudgetResult? _programmableResult;
  BudgetAllocationRun? _programmableRun;

  Future<void> _editMonthOnly(List<BudgetScenarioMemberIncome> incomes) async {
    final result = await showDialog<List<BudgetScenarioMemberIncome>>(
      context: context,
      builder: (_) => _MonthlyIncomeOverridesDialog(incomes: incomes),
    );
    if (result != null && mounted) {
      setState(() => _monthlyIncomeOverrides = result);
    }
  }

  void _simulate(
    List<BudgetScenarioMemberIncome> incomes,
    List<BudgetScenarioRule> rules,
    List<dynamic> envelopes,
  ) {
    final total = incomes.fold<int>(
      0,
      (sum, income) => sum + income.eligibleIncomeCents,
    );
    final run = const BudgetSimulator().simulate(
      runId: _uuid(),
      householdId: widget.scenario.householdId,
      periodId: widget.period.id,
      scenarioId: widget.scenario.id,
      availableResourcesCents: total,
      previousBalancesCents: {
        for (final item in envelopes) item.id: item.balance.minorUnits,
      },
      rules: rules,
      memberIncomes: incomes,
    );
    ref.read(budgetSimulationStateProvider.notifier).state =
        BudgetSimulationState(run: run);
  }

  List<BudgetSource> _effectiveSources(List<BudgetSource> sources) => sources
      .map(
        (source) => BudgetSource(
          id: source.id,
          scenarioVersionId: source.scenarioVersionId,
          type: source.type,
          name: source.name,
          expectedCents:
              _monthlySourceOverridesCents[source.id] ?? source.expectedCents,
          memberUserId: source.memberUserId,
          exceptionalTreatment: source.exceptionalTreatment,
          active: source.active,
        ),
      )
      .toList(growable: false);

  List<BudgetAllocationStep> _effectiveSteps(
    List<BudgetAllocationStep> steps,
  ) => steps
      .map((step) => _monthlyStepOverrides[step.id] ?? step)
      .toList(growable: false);

  void _simulateProgrammable(
    List<BudgetSource> sources,
    List<BudgetAllocationStep> steps,
    List<dynamic> members,
    Map<String, int> previousBalancesCents,
  ) {
    setState(() {
      final result = const ProgrammableBudgetEngine().simulate(
        sources: _effectiveSources(sources),
        steps: _effectiveSteps(steps),
        memberIds: members
            .map<String>((member) => member.id as String)
            .toList(),
      );
      _programmableResult = result;
      _programmableRun = BudgetAllocationRun(
        id: _uuid(),
        householdId: widget.scenario.householdId,
        periodId: widget.period.id,
        scenarioId: widget.scenario.id,
        availableResourcesCents: result.initialResourcesCents,
        status: BudgetAllocationRunStatus.simulated,
        warnings: result.warnings,
        lines: result.stepResults
            .where((item) => item.step.active)
            .map(
              (item) => BudgetAllocationRunLine(
                envelopeId: item.step.envelopeId,
                previousBalanceCents:
                    previousBalancesCents[item.step.envelopeId] ?? 0,
                rolloverCents: 0,
                plannedAllocationCents: item.allocatedCents,
                resultingAvailableCents:
                    (previousBalancesCents[item.step.envelopeId] ?? 0) +
                    item.allocatedCents,
                priority: item.step.order,
                state: BudgetEnvelopeState.available,
                warning: item.diagnostics
                    .where(
                      (diagnostic) =>
                          diagnostic.severity ==
                          ProgrammableBudgetDiagnosticSeverity.warning,
                    )
                    .map((diagnostic) => diagnostic.message)
                    .firstOrNull,
                contributions: item.memberContributions,
                fundingSourcePreference: item.step.fundingSourcePreference,
              ),
            )
            .toList(growable: false),
      );
    });
  }

  void _resetMonthlyOverrides() {
    setState(() {
      _monthlySourceOverridesCents.clear();
      _monthlyStepOverrides.clear();
      _programmableResult = null;
      _programmableRun = null;
    });
  }

  Future<void> _editMonthlyStep(
    BudgetAllocationStep step,
    List<BudgetSource> sources,
    List<dynamic> envelopes,
    List<HouseholdMember> members,
  ) async {
    await showDialog<BudgetAllocationStep>(
      context: context,
      builder: (_) => BudgetAllocationStepDialog(
        versionId: step.scenarioVersionId,
        scenarioId: widget.scenario.id,
        sources: sources,
        envelopes: envelopes,
        members: members,
        step: step,
        onSaved: (updated) {
          if (mounted) {
            setState(() {
              _monthlyStepOverrides[step.id] = updated;
              _programmableResult = null;
              _programmableRun = null;
            });
          }
        },
      ),
    );
  }

  Future<void> _save(
    BudgetAllocationRun run,
    BudgetScenarioVersion? version,
    List<BudgetScenarioMemberIncome> incomes,
    List<BudgetScenarioRule> rules,
    List<BudgetSource> sources,
    List<BudgetAllocationStep> steps,
    ProgrammableBudgetResult? programmableResult,
    Map<String, String> memberNames,
  ) async {
    if (version == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mt(context, 'monthly.model_required'))),
      );
      return;
    }
    final analysis = const MonthlyBudgetAnalyzer().analyze(
      run: run,
      incomes: incomes,
      rules: rules,
    );
    if (analysis.blockers.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      await repository.persistProgrammableRun(
        run: run,
        scenarioVersionId: version.id,
        snapshot: _snapshot(
          version,
          analysis,
          incomes,
          rules,
          sources,
          steps,
          programmableResult,
          memberNames,
        ),
      );
      ref.invalidate(remoteBudgetRunsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mt(context, 'monthly.saved'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mt(context, 'monthly.save_error'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _saveProgrammable(
    BudgetAllocationRun run,
    BudgetScenarioVersion version,
    List<BudgetSource> sources,
    List<BudgetAllocationStep> steps,
    ProgrammableBudgetResult result,
    Map<String, String> memberNames,
  ) async {
    if (!result.isSimulable) return;
    setState(() => _saving = true);
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      await repository.persistProgrammableRun(
        run: run,
        scenarioVersionId: version.id,
        snapshot: {
          'monthly_snapshot': true,
          'scenario_id': widget.scenario.id,
          'scenario_name': widget.scenario.name,
          'scenario_version_id': version.id,
          'scenario_version': version.version,
          'sources': sources
              .map(
                (source) => {
                  'id': source.id,
                  'name': source.name,
                  'expected_cents': source.expectedCents,
                  'member_user_id': source.memberUserId,
                  'member_name': memberNames[source.memberUserId],
                },
              )
              .toList(growable: false),
          'steps': steps
              .map(
                (step) => {
                  'id': step.id,
                  'order': step.order,
                  'group': step.groupName,
                  'method': step.method.name,
                },
              )
              .toList(growable: false),
          'source_overrides_cents': _monthlySourceOverridesCents,
          'step_overrides': _monthlyStepOverrides.map(
            (id, step) => MapEntry(id, <String, Object?>{
              'amount_cents': step.amountCents,
            }),
          ),
          'programmable_result': {
            'simulable': result.isSimulable,
            'initial_resources_cents': result.initialResourcesCents,
            'allocated_cents': result.allocatedCents,
            'remaining_cents': result.remainingCents,
          },
        },
      );
      ref.invalidate(remoteBudgetRunsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_mt(context, 'monthly.saved'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_mt(context, 'monthly.save_error'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  BudgetScenarioVersion? _selectedVersion(
    BudgetScenario scenario,
    List<BudgetScenarioVersion>? versions,
  ) {
    if (versions == null || versions.isEmpty) return null;
    final configuredId = scenario.currentVersionId;
    if (configuredId != null) {
      final selected = versions
          .where((version) => version.id == configuredId)
          .firstOrNull;
      if (selected != null) return selected;
    }
    return versions.first;
  }

  Map<String, Object?> _snapshot(
    BudgetScenarioVersion version,
    MonthlyBudgetAnalysis analysis,
    List<BudgetScenarioMemberIncome> incomes,
    List<BudgetScenarioRule> rules,
    List<BudgetSource> sources,
    List<BudgetAllocationStep> steps,
    ProgrammableBudgetResult? programmableResult,
    Map<String, String> memberNames,
  ) => {
    'monthly_snapshot': true,
    // These descriptive values are deliberately repeated in the monthly
    // snapshot.  A saved month must remain readable even after its template
    // has been renamed or superseded.
    'scenario_id': widget.scenario.id,
    'scenario_name': widget.scenario.name,
    'scenario_version_id': version.id,
    'scenario_version': version.version,
    'incomes': incomes
        .map(
          (income) => {
            'member_user_id': income.memberUserId,
            'recurring_cents': income.netRecurringCents,
            'other_cents': income.otherRecurringCents,
            'exceptional_cents': income.exceptionalCents,
            'exceptional_treatment': income.exceptionalTreatment.name,
          },
        )
        .toList(growable: false),
    'rules': rules
        .map(
          (rule) => {
            'envelope_id': rule.envelopeId,
            'method': rule.method.name,
            'funding_mode': rule.fundingMode.name,
            'funding_preference': rule.fundingSourcePreference,
          },
        )
        .toList(growable: false),
    'sources': sources
        .map(
          (source) => {
            'id': source.id,
            'type': source.type.name,
            'name': source.name,
            'expected_cents': source.expectedCents,
            'member_user_id': source.memberUserId,
            'member_name': source.memberUserId == null
                ? null
                : memberNames[source.memberUserId],
            'active': source.active,
          },
        )
        .toList(growable: false),
    'source_overrides_cents': Map<String, int>.from(
      _monthlySourceOverridesCents,
    ),
    'steps': steps
        .map(
          (step) => {
            'id': step.id,
            'order': step.order,
            'group': step.groupName,
            'source_id': step.sourceId,
            'envelope_id': step.envelopeId,
            'method': step.method.name,
            'contribution_key': step.contributionKey.name,
            'insufficient_funds_policy': step.insufficientFundsPolicy.name,
            'funding_preference': step.fundingSourcePreference,
          },
        )
        .toList(growable: false),
    'step_overrides': _monthlyStepOverrides.map(
      (id, step) => MapEntry(id, {
        'amount_cents': step.amountCents,
        'percentage': step.percentage,
        'active': step.active,
        'contribution_key': step.contributionKey.name,
        'funding_preference': step.fundingSourcePreference,
      }),
    ),
    'kpis': {
      'income_cents': analysis.incomeCents,
      'personal_charges_cents': analysis.personalChargesCents,
      'common_charges_cents': analysis.commonChargesCents,
      'savings_cents': analysis.savingsCents,
      'remaining_cents': analysis.remainingCents,
      'cash_need_cents': analysis.cashNeedCents,
    },
    'warnings': analysis.warnings,
    'blockers': analysis.blockers,
    if (programmableResult != null)
      'programmable_result': {
        'initial_resources_cents': programmableResult.initialResourcesCents,
        'remaining_cents': programmableResult.remainingCents,
        'simulable': programmableResult.isSimulable,
        'capacities': programmableResult.memberCapacities
            .map(
              (item) => {
                'member_user_id': item.memberUserId,
                'resources_cents': item.resourcesCents,
                'direct_charges_cents': item.directChargesCents,
                'capacity_cents': item.contributionCapacityCents,
                'auto_share': item.autoShare,
              },
            )
            .toList(growable: false),
        'steps': programmableResult.stepResults
            .map(
              (item) => {
                'step_id': item.step.id,
                'requested_cents': item.requestedCents,
                'allocated_cents': item.allocatedCents,
                'status': item.status.name,
                'contributions': item.memberContributions,
              },
            )
            .toList(growable: false),
        'diagnostics': programmableResult.diagnostics
            .map(
              (item) => {
                'severity': item.severity.name,
                'code': item.code,
                'message': item.message,
              },
            )
            .toList(growable: false),
      },
  };

  @override
  Widget build(BuildContext context) {
    final scenario = widget.scenario;
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    final versions = ref.watch(budgetScenarioVersionsProvider(scenario.id));
    final members = ref.watch(remoteHouseholdMembersProvider);
    final accounts = ref.watch(remoteAccountsProvider);
    final history = ref.watch(remoteBudgetRunsProvider);
    final currentVersion = _selectedVersion(scenario, versions.valueOrNull);
    final usesProgrammableModel = currentVersion != null;
    final incomes = usesProgrammableModel
        ? null
        : ref.watch(budgetScenarioMemberIncomesProvider(scenario.id));
    final rules = usesProgrammableModel
        ? null
        : ref.watch(budgetScenarioRulesProvider(scenario.id));
    final run = usesProgrammableModel
        ? null
        : ref.watch(budgetSimulationStateProvider).run;
    final sources = currentVersion == null
        ? const AsyncData<List<BudgetSource>>(<BudgetSource>[])
        : ref.watch(budgetScenarioSourcesProvider(currentVersion.id));
    final steps = currentVersion == null
        ? const AsyncData<List<BudgetAllocationStep>>(<BudgetAllocationStep>[])
        : ref.watch(budgetScenarioStepsProvider(currentVersion.id));
    final cashAccountIds =
        accounts.valueOrNull
            ?.where((account) => account.type == FinancialAccountType.cash)
            .map((account) => account.id)
            .toSet() ??
        const <String>{};
    final effectiveIncomes = _monthlyIncomeOverrides ?? incomes?.valueOrNull;
    final analysis =
        run == null || effectiveIncomes == null || rules?.valueOrNull == null
        ? null
        : const MonthlyBudgetAnalyzer().analyze(
            run: run,
            incomes: effectiveIncomes,
            rules: rules!.valueOrNull!,
            cashFundingSourceIds: cashAccountIds,
          );
    final labels = <String, String>{
      for (final member in members.valueOrNull ?? const [])
        member.id: member.displayName,
    };
    final previous = history.valueOrNull
        ?.where(
          (item) =>
              item.scenarioId == scenario.id &&
              item.periodId != widget.period.id,
        )
        .firstOrNull;
    final templateSources = sources.valueOrNull ?? const <BudgetSource>[];
    final visibleTemplateSources = templateSources
        .where((source) => source.type != BudgetSourceType.commonCapacity)
        .toList(growable: false);
    final templateSteps = steps.valueOrNull ?? const <BudgetAllocationStep>[];
    final effectiveSources = _effectiveSources(templateSources);
    final effectiveSteps = _effectiveSteps(templateSteps);
    final hasActiveSources = effectiveSources.any((source) => source.active);
    final hasActiveSteps = effectiveSteps.any((step) => step.active);
    final programIncomplete =
        usesProgrammableModel && hasActiveSources && !hasActiveSteps;
    final programmableReady =
        usesProgrammableModel && hasActiveSources && hasActiveSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        DesktopSection(
          title: _mf(context, 'monthly.selected', {'scenario': scenario.name}),
          subtitle: _mf(context, 'monthly.preview_month', {
            'month': _monthLabel(context, widget.period.startsOn),
          }),
          child: ResponsiveGrid(
            minItemWidth: 420,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _mf(context, 'monthly.current_version', {
                      'version':
                          currentVersion?.version ??
                          _mt(context, 'monthly.to_create'),
                    }),
                  ),
                  Text(
                    _mf(context, 'monthly.program_counts', {
                      'sources': visibleTemplateSources.length,
                      'steps': effectiveSteps.length,
                      'groups': effectiveSteps
                          .map((step) => step.groupName)
                          .toSet()
                          .length,
                    }),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      TextButton(
                        onPressed:
                            usesProgrammableModel ||
                                incomes?.valueOrNull == null
                            ? null
                            : () => _editMonthOnly(incomes!.valueOrNull!),
                        child: Text(_mt(context, 'monthly.edit_month')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BudgetScenarioDetailPage(
                              scenarioId: scenario.id,
                            ),
                          ),
                        ),
                        child: Text(_mt(context, 'monthly.edit_template')),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (usesProgrammableModel)
                    Text(_mt(context, 'monthly.programmable_mode'))
                  else ...[
                    Text(
                      _mt(context, 'monthly.month_income'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    incomes!.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) =>
                          Text(_mt(context, 'monthly.income_error')),
                      data: (items) => Text(
                        _mf(context, 'monthly.income_count', {
                          'count': items.length,
                        }),
                      ),
                    ),
                    rules!.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) =>
                          Text(_mt(context, 'monthly.program_error')),
                      data: (items) => Text(
                        _mf(context, 'monthly.step_count', {
                          'count': items.length,
                        }),
                      ),
                    ),
                  ],
                ],
              ),
              if (visibleTemplateSources.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mt(context, 'monthly.month_resources'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    ResponsiveGrid(
                      minItemWidth: 210,
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: visibleTemplateSources
                          .where((source) => source.active)
                          .map((source) {
                            final effective =
                                _monthlySourceOverridesCents[source.id] ??
                                source.expectedCents;
                            final changed = effective != source.expectedCents;
                            return TextFormField(
                              key: ValueKey(
                                'monthly-source-${source.id}-$effective',
                              ),
                              initialValue: (effective / 100).toString(),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: source.name,
                                helperText: changed
                                    ? _mf(context, 'monthly.changed_value', {
                                        'value': _mad(source.expectedCents),
                                      })
                                    : _mf(context, 'monthly.template_value', {
                                        'value': _mad(source.expectedCents),
                                      }),
                              ),
                              onChanged: (value) {
                                final cents = _cents(value);
                                setState(() {
                                  if (cents == null ||
                                      cents == source.expectedCents) {
                                    _monthlySourceOverridesCents.remove(
                                      source.id,
                                    );
                                  } else {
                                    _monthlySourceOverridesCents[source.id] =
                                        cents;
                                  }
                                  _programmableResult = null;
                                  _programmableRun = null;
                                });
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (programIncomplete)
          Card(
            child: Padding(
              padding: AppSpacing.card,
              child: Text(_mt(context, 'monthly.program_incomplete')),
            ),
          ),
        FilledButton.icon(
          key: const Key('simulate-monthly-budget'),
          onPressed: usesProgrammableModel
              ? !programmableReady || envelopes.valueOrNull == null
                    ? null
                    : () => _simulateProgrammable(
                        templateSources,
                        templateSteps,
                        members.valueOrNull ?? const [],
                        {
                          for (final envelope
                              in envelopes.valueOrNull ?? const [])
                            envelope.id: envelope.balance.minorUnits,
                        },
                      )
              : effectiveIncomes == null ||
                    rules?.valueOrNull == null ||
                    envelopes.valueOrNull == null
              ? null
              : () => _simulate(
                  effectiveIncomes,
                  rules!.valueOrNull!,
                  envelopes.valueOrNull!,
                ),
          icon: const Icon(Icons.calculate_outlined),
          label: Text(
            _mf(context, 'monthly.simulate', {
              'month': _monthLabel(context, widget.period.startsOn),
            }),
          ),
        ),
        if (usesProgrammableModel)
          OutlinedButton.icon(
            key: const Key('simulate-programmable-monthly-budget'),
            onPressed: !programmableReady || envelopes.valueOrNull == null
                ? null
                : () => _simulateProgrammable(
                    templateSources,
                    templateSteps,
                    members.valueOrNull ?? const [],
                    {
                      for (final envelope in envelopes.valueOrNull ?? const [])
                        envelope.id: envelope.balance.minorUnits,
                    },
                  ),
            icon: const Icon(Icons.preview_outlined),
            label: Text(
              _mf(context, 'monthly.preview', {
                'month': _monthLabel(context, widget.period.startsOn),
              }),
            ),
          ),
        if (_monthlySourceOverridesCents.isNotEmpty ||
            _monthlyStepOverrides.isNotEmpty)
          TextButton(
            onPressed: _resetMonthlyOverrides,
            child: Text(_mt(context, 'monthly.reset')),
          ),
        if (usesProgrammableModel && _programmableResult != null)
          _MonthlyProgrammablePreview(
            result: _programmableResult!,
            sources: effectiveSources,
            steps: effectiveSteps,
            memberNames: labels,
            overriddenStepIds: _monthlyStepOverrides.keys.toSet(),
            onEditStep: (step) => _editMonthlyStep(
              step,
              templateSources,
              envelopes.valueOrNull ?? const [],
              members.valueOrNull ?? const [],
            ),
          ),
        if (usesProgrammableModel &&
            _programmableResult != null &&
            _programmableRun != null)
          _ProgrammableMonthlySummary(
            result: _programmableResult!,
            saving: _saving,
            onSave: () => _saveProgrammable(
              _programmableRun!,
              currentVersion,
              effectiveSources,
              effectiveSteps,
              _programmableResult!,
              labels,
            ),
          ),
        if (!usesProgrammableModel && analysis != null)
          _MonthlySummary(
            analysis: analysis,
            labels: labels,
            previous: previous,
            saving: _saving,
            version: currentVersion,
            canSave:
                templateSources.isEmpty ||
                (_programmableResult?.isSimulable ?? false),
            onSave: () => _save(
              run!,
              currentVersion,
              effectiveIncomes!,
              rules!.valueOrNull!,
              effectiveSources,
              effectiveSteps,
              _programmableResult,
              labels,
            ),
          ),
      ],
    );
  }
}

class _MonthlySummary extends StatelessWidget {
  const _MonthlySummary({
    required this.analysis,
    required this.labels,
    required this.previous,
    required this.saving,
    required this.version,
    required this.canSave,
    required this.onSave,
  });
  final MonthlyBudgetAnalysis analysis;
  final Map<String, String> labels;
  final RemoteBudgetRun? previous;
  final bool saving;
  final BudgetScenarioVersion? version;
  final bool canSave;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('monthly-budget-summary'),
    child: Padding(
      padding: AppSpacing.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _mt(context, 'monthly.household_summary'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            _mf(context, 'monthly.income', {
              'value': _mad(analysis.incomeCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.personal', {
              'value': _mad(analysis.personalChargesCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.common', {
              'value': _mad(analysis.commonChargesCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.savings', {
              'value': _mad(analysis.savingsCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.remaining', {
              'value': _mad(analysis.remainingCents),
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _mt(context, 'monthly.kpis'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            _mf(context, 'monthly.fixed_charge_rate', {
              'value': (analysis.fixedChargeRate * 100).toStringAsFixed(1),
            }),
          ),
          Text(
            _mf(context, 'monthly.savings_rate', {
              'value': (analysis.savingsRate * 100).toStringAsFixed(1),
            }),
          ),
          Text(
            _mf(context, 'monthly.cash_need', {
              'value': _mad(analysis.cashNeedCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.balanced', {
              'value': _mt(
                context,
                analysis.isBalanced ? 'monthly.yes' : 'monthly.no',
              ),
            }),
          ),
          if (previous != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _mt(context, 'monthly.previous_comparison'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              _mf(context, 'monthly.compare_income', {
                'current': _mad(analysis.incomeCents),
                'previous': _mad(previous!.availableCents),
                'delta': _delta(
                  analysis.incomeCents - previous!.availableCents,
                ),
              }),
            ),
            Text(
              _mf(context, 'monthly.compare_allocations', {
                'current': _mad(analysis.commonChargesCents),
                'previous': _mad(previous!.totalCents),
                'delta': _delta(
                  analysis.commonChargesCents - previous!.totalCents,
                ),
              }),
            ),
            Text(
              _mf(context, 'monthly.compare_remaining', {
                'current': _mad(analysis.remainingCents),
                'previous': _mad(previous!.remainingCents),
                'delta': _delta(
                  analysis.remainingCents - previous!.remainingCents,
                ),
              }),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            _mt(context, 'monthly.members_summary'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...analysis.memberSummaries.map(
            (item) => Text(
              _mf(context, 'monthly.member_summary', {
                'member':
                    labels[item.memberUserId] ??
                    _mt(context, 'monthly.member_fallback'),
                'income': _mad(item.incomeCents),
                'charges': _mad(item.personalChargesCents),
                'contribution': _mad(item.commonContributionCents),
                'remaining': _mad(item.remainingCents),
              }),
            ),
          ),
          if (analysis.transferSuggestion != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _mt(context, 'monthly.transfer'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              _mf(context, 'monthly.transfer_row', {
                'from':
                    labels[analysis.transferSuggestion!.fromMemberUserId] ??
                    _mt(context, 'monthly.member_short'),
                'to':
                    labels[analysis.transferSuggestion!.toMemberUserId] ??
                    _mt(context, 'monthly.member_short'),
                'value': _mad(analysis.transferSuggestion!.amountCents),
              }),
            ),
            Text(_mt(context, 'monthly.transfer_hint')),
          ],
          if (analysis.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _mt(context, 'monthly.warnings'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...analysis.warnings.map(Text.new),
          ],
          if (analysis.blockers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _mt(context, 'monthly.blockers'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...analysis.blockers.map(Text.new),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            key: const Key('save-monthly-budget'),
            onPressed:
                saving ||
                    version == null ||
                    analysis.blockers.isNotEmpty ||
                    !canSave
                ? null
                : onSave,
            icon: const Icon(Icons.save_outlined),
            label: Text(saving ? 'Enregistrement…' : 'Enregistrer le mois'),
          ),
        ],
      ),
    ),
  );
}

class _ProgrammableMonthlySummary extends StatelessWidget {
  const _ProgrammableMonthlySummary({
    required this.result,
    required this.saving,
    required this.onSave,
  });

  final ProgrammableBudgetResult result;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('monthly-budget-summary'),
    child: Padding(
      padding: AppSpacing.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _mt(context, 'monthly.program_summary'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            _mf(context, 'monthly.resources', {
              'value': _mad(result.initialResourcesCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.allocated', {
              'value': _mad(result.allocatedCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.remaining', {
              'value': _mad(result.remainingCents),
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            key: const Key('save-monthly-budget'),
            onPressed: saving || !result.isSimulable ? null : onSave,
            icon: const Icon(Icons.save_outlined),
            label: Text(saving ? 'Enregistrement…' : 'Enregistrer le mois'),
          ),
        ],
      ),
    ),
  );
}

class _MonthlyProgrammablePreview extends StatelessWidget {
  const _MonthlyProgrammablePreview({
    required this.result,
    required this.sources,
    required this.steps,
    required this.memberNames,
    required this.overriddenStepIds,
    required this.onEditStep,
  });
  final ProgrammableBudgetResult result;
  final List<BudgetSource> sources;
  final List<BudgetAllocationStep> steps;
  final Map<String, String> memberNames;
  final Set<String> overriddenStepIds;
  final ValueChanged<BudgetAllocationStep> onEditStep;

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('monthly-programmable-preview'),
    child: Padding(
      padding: AppSpacing.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _mt(context, 'monthly.preview_result'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            _mf(context, 'monthly.resources', {
              'value': _mad(result.initialResourcesCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.allocated', {
              'value': _mad(result.allocatedCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.remaining', {
              'value': _mad(result.remainingCents),
            }),
          ),
          Text(
            _mf(context, 'monthly.simulable_value', {
              'value': _mt(
                context,
                result.isSimulable ? 'monthly.yes' : 'monthly.no',
              ),
            }),
          ),
          if (result.diagnostics.any(
            (item) =>
                item.severity == ProgrammableBudgetDiagnosticSeverity.warning,
          ))
            Text(_mt(context, 'monthly.warning_attention')),
          if (!result.isSimulable) ...[
            Text(_mt(context, 'monthly.blocked_attention')),
            ...result.diagnostics
                .where(
                  (item) =>
                      item.severity ==
                      ProgrammableBudgetDiagnosticSeverity.blocker,
                )
                .map((item) => Text(item.message)),
          ],
          const SizedBox(height: AppSpacing.sm),
          ...result.stepResults.map((item) {
            final source = sources
                .where((source) => source.id == item.step.sourceId)
                .map((source) => source.name)
                .firstOrNull;
            final changed = overriddenStepIds.contains(item.step.id);
            return ListTile(
              title: Text(
                _mf(context, 'monthly.ordered_group', {
                  'order': item.step.order,
                  'group': item.step.groupName,
                }),
              ),
              subtitle: Text(
                _mf(context, 'monthly.step_summary', {
                  'source': source ?? _mt(context, 'monthly.source_missing'),
                  'value': _mad(item.allocatedCents),
                }),
              ),
              trailing: TextButton(
                onPressed: () => onEditStep(item.step),
                child: Text(_mt(context, 'monthly.edit_step')),
              ),
              leading: changed
                  ? Chip(label: Text(_mt(context, 'monthly.changed_month')))
                  : null,
            );
          }),
        ],
      ),
    ),
  );
}

/// Read-only projection of a saved monthly budget.  It deliberately consumes
/// only [RemoteBudgetRun.summary], never the current scenario version: a
/// template can evolve after the month has been recorded.
class _PreparedMonthlySnapshot extends StatelessWidget {
  const _PreparedMonthlySnapshot({
    required this.run,
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });

  final RemoteBudgetRun run;
  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final snapshot = run.summary;
    final sources = _snapshotList(snapshot['sources']);
    final steps = _snapshotList(snapshot['steps']);
    final sourceOverrides = _snapshotMap(snapshot['source_overrides_cents']);
    final stepOverrides = _snapshotMap(snapshot['step_overrides']);
    final result = _snapshotMap(snapshot['programmable_result']);
    final capacities = _snapshotList(result['capacities']);
    final results = _snapshotList(result['steps']);
    final diagnostics = _snapshotList(result['diagnostics']);
    final scenarioName =
        snapshot['scenario_name'] as String? ??
        _mt(context, 'monthly.prepared_scenario');
    final version = snapshot['scenario_version'];

    return ListView(
      key: const Key('prepared-month-snapshot'),
      padding: AppSpacing.page,
      children: [
        _MonthNavigation(
          month: month,
          onPrevious: onPrevious,
          onNext: onNext,
          onPick: onPick,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _mt(context, 'monthly.prepared_budget'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          _mf(context, 'monthly.period', {
            'value': _monthLabel(context, month),
          }),
        ),
        Text(_mf(context, 'monthly.scenario', {'value': scenarioName})),
        Text(
          _mf(context, 'monthly.version', {
            'value': version ?? _mt(context, 'monthly.historical'),
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _mt(context, 'monthly.sources_effective'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (sources.isEmpty) Text(_mt(context, 'monthly.no_sources')),
        ...sources.map((source) {
          final name =
              source['name'] as String? ?? _mt(context, 'monthly.source');
          final expected = _snapshotCents(source['expected_cents']);
          final sourceId = source['id'] as String?;
          final memberName = source['member_name'] as String?;
          final overridden =
              sourceId != null && sourceOverrides.containsKey(sourceId);
          final effective = overridden
              ? _snapshotCents(sourceOverrides[sourceId])
              : expected;
          return ListTile(
            title: Text(name),
            subtitle: Text(
              overridden
                  ? _mf(context, 'monthly.history_source_changed', {
                      'member': memberName == null
                          ? ''
                          : _mf(context, 'monthly.member_prefix', {
                              'member': memberName,
                            }),
                      'value': _mad(effective),
                    })
                  : _mf(context, 'monthly.history_source_template', {
                      'member': memberName == null
                          ? ''
                          : _mf(context, 'monthly.member_prefix', {
                              'member': memberName,
                            }),
                      'value': _mad(effective),
                    }),
            ),
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _mt(context, 'monthly.program_effective'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (steps.isEmpty) Text(_mt(context, 'monthly.no_steps')),
        ...steps.map((step) {
          final id = step['id'] as String?;
          final changed = id != null && stepOverrides.containsKey(id);
          final group =
              step['group'] as String? ?? _mt(context, 'monthly.program');
          final order = step['order'] as num? ?? 0;
          final method = _budgetMethodLabel(context, step['method'] as String?);
          final override = id == null
              ? const <String, Object?>{}
              : _snapshotMap(stepOverrides[id]);
          return ListTile(
            title: Text(
              _mf(context, 'monthly.numbered_group', {
                'order': order,
                'group': group,
              }),
            ),
            subtitle: Text(
              changed
                  ? _mf(context, 'monthly.history_step_changed', {
                      'method': method,
                      'details': _historicalStepOverrideDetails(
                        context,
                        override,
                      ),
                    })
                  : method,
            ),
          );
        }),
        if (result.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _mt(context, 'monthly.capacities'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...capacities.map(
            (item) => ListTile(
              title: Text(_mt(context, 'monthly.household_member')),
              subtitle: Text(
                _mf(context, 'monthly.capacity', {
                  'capacity': _mad(_snapshotCents(item['capacity_cents'])),
                  'share': _snapshotPercent(item['auto_share']),
                }),
              ),
            ),
          ),
          Text(
            _mt(context, 'monthly.results'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...results.map(
            (item) => Text(
              _mf(context, 'monthly.result', {
                'status': _snapshotStepStatus(
                  context,
                  item['status'] as String?,
                ),
                'requested': _mad(_snapshotCents(item['requested_cents'])),
                'allocated': _mad(_snapshotCents(item['allocated_cents'])),
              }),
            ),
          ),
          Text(
            _mt(context, 'monthly.diagnostics'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (diagnostics.isEmpty) Text(_mt(context, 'monthly.no_diagnostic')),
          ...diagnostics.map(
            (item) => Text(
              _mf(context, 'monthly.diagnostic_row', {
                'severity': _snapshotDiagnosticLabel(
                  context,
                  item['severity'] as String?,
                ),
                'message':
                    item['message'] ?? _mt(context, 'monthly.diagnostic'),
              }),
            ),
          ),
          Text(
            result['simulable'] == true
                ? _mt(context, 'monthly.simulable')
                : _mt(context, 'monthly.not_simulable'),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(_mt(context, 'monthly.history_notice')),
      ],
    );
  }
}

List<Map<String, Object?>> _snapshotList(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, Object?>.from(item))
          .toList(growable: false)
    : const [];

Map<String, Object?> _snapshotMap(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

int _snapshotCents(Object? value) => (value as num?)?.toInt() ?? 0;
String _snapshotPercent(Object? value) =>
    '${(((value as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)} %';
String _budgetMethodLabel(BuildContext context, String? value) =>
    switch (value) {
      'fixed' => _mt(context, 'monthly.fixed'),
      'percentage' => _mt(context, 'monthly.percentage'),
      'residual' => _mt(context, 'monthly.residual'),
      _ => _mt(context, 'monthly.method'),
    };
String _snapshotStepStatus(BuildContext context, String? value) =>
    switch (value) {
      'executed' => _mt(context, 'monthly.executed'),
      'partiallyExecuted' => _mt(context, 'monthly.partial'),
      'skipped' => _mt(context, 'monthly.skipped'),
      'blocked' => _mt(context, 'monthly.blocked'),
      'inactive' => _mt(context, 'monthly.inactive'),
      _ => _mt(context, 'monthly.step'),
    };
String _snapshotDiagnosticLabel(BuildContext context, String? value) =>
    switch (value) {
      'info' => _mt(context, 'monthly.info'),
      'warning' => _mt(context, 'monthly.warning'),
      'blocker' => _mt(context, 'monthly.blocker'),
      _ => _mt(context, 'monthly.diagnostic'),
    };
String _historicalStepOverrideDetails(
  BuildContext context,
  Map<String, Object?> override,
) {
  final amount = override['amount_cents'];
  if (amount is num) {
    return _mf(context, 'monthly.amount_suffix', {
      'value': _mad(amount.toInt()),
    });
  }
  final percentage = override['percentage'];
  if (percentage is num) {
    return _mf(context, 'monthly.percentage_suffix', {
      'value': percentage.toString(),
    });
  }
  if (override['active'] == false) {
    return _mt(context, 'monthly.disabled_suffix');
  }
  return '';
}

class _MonthlyScenarioDialog extends StatefulWidget {
  const _MonthlyScenarioDialog({
    this.title,
    this.initialName,
    this.initialDescription,
  });
  final String? title;
  final String? initialName;
  final String? initialDescription;
  @override
  State<_MonthlyScenarioDialog> createState() => _MonthlyScenarioDialogState();
}

class _MonthlyIncomeOverridesDialog extends StatefulWidget {
  const _MonthlyIncomeOverridesDialog({required this.incomes});
  final List<BudgetScenarioMemberIncome> incomes;

  @override
  State<_MonthlyIncomeOverridesDialog> createState() =>
      _MonthlyIncomeOverridesDialogState();
}

class _MonthlyIncomeOverridesDialogState
    extends State<_MonthlyIncomeOverridesDialog> {
  late final Map<String, TextEditingController> _recurring;
  late final Map<String, TextEditingController> _other;
  late final Map<String, TextEditingController> _exceptional;

  @override
  void initState() {
    super.initState();
    _recurring = {
      for (final item in widget.incomes)
        item.memberUserId: TextEditingController(
          text: (item.netRecurringCents / 100).toString(),
        ),
    };
    _other = {
      for (final item in widget.incomes)
        item.memberUserId: TextEditingController(
          text: (item.otherRecurringCents / 100).toString(),
        ),
    };
    _exceptional = {
      for (final item in widget.incomes)
        item.memberUserId: TextEditingController(
          text: (item.exceptionalCents / 100).toString(),
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in [
      ..._recurring.values,
      ..._other.values,
      ..._exceptional.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_mt(context, 'monthly.edit_month_title')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_mt(context, 'monthly.edit_month_hint')),
          ...widget.incomes.map(
            (item) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_mt(context, 'monthly.member')),
                TextField(
                  key: Key('monthly-income-recurring-${item.memberUserId}'),
                  controller: _recurring[item.memberUserId],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _mt(context, 'monthly.salary'),
                  ),
                ),
                TextField(
                  key: Key('monthly-income-other-${item.memberUserId}'),
                  controller: _other[item.memberUserId],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _mt(context, 'monthly.other_income'),
                  ),
                ),
                TextField(
                  key: Key('monthly-income-exceptional-${item.memberUserId}'),
                  controller: _exceptional[item.memberUserId],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _mt(context, 'monthly.bonus'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_mt(context, 'monthly.cancel')),
      ),
      FilledButton(
        onPressed: _save,
        child: Text(_mt(context, 'monthly.apply_month')),
      ),
    ],
  );

  void _save() {
    final values = <BudgetScenarioMemberIncome>[];
    for (final item in widget.incomes) {
      final recurring = _moneyCents(_recurring[item.memberUserId]!.text);
      final other = _moneyCents(_other[item.memberUserId]!.text);
      final exceptional = _moneyCents(_exceptional[item.memberUserId]!.text);
      if (recurring == null ||
          other == null ||
          exceptional == null ||
          recurring < 0 ||
          other < 0 ||
          exceptional < 0) {
        return;
      }
      values.add(
        BudgetScenarioMemberIncome(
          memberUserId: item.memberUserId,
          netRecurringCents: recurring,
          otherRecurringCents: other,
          exceptionalCents: exceptional,
          exceptionalTreatment: item.exceptionalTreatment,
          notes: item.notes,
        ),
      );
    }
    Navigator.pop(context, List.unmodifiable(values));
  }
}

class _MonthlyScenarioDialogState extends State<_MonthlyScenarioDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  bool _active = true;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _description = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title ?? _mt(context, 'monthly.new_scenario_title')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('monthly-scenario-name'),
          controller: _name,
          decoration: InputDecoration(
            labelText: _mt(context, 'monthly.name_required'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _description,
          decoration: InputDecoration(
            labelText: _mt(context, 'monthly.description'),
          ),
        ),
        SwitchListTile(
          title: Text(_mt(context, 'monthly.active_scenario')),
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_mt(context, 'monthly.cancel')),
      ),
      FilledButton(
        key: const Key('save-monthly-scenario'),
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(
                context,
                BudgetScenario(
                  id: '',
                  householdId: '',
                  name: _name.text.trim(),
                  description: _description.text.trim().isEmpty
                      ? null
                      : _description.text.trim(),
                  active: _active,
                ),
              ),
        child: Text(_mt(context, 'monthly.create')),
      ),
    ],
  );
}

String _mad(int cents) => '${(cents / 100).toStringAsFixed(2)} MAD';
int? _cents(String value) {
  final amount = double.tryParse(value.trim().replaceAll(',', '.'));
  return amount == null ? null : (amount * 100).round();
}

String _delta(int cents) => '${cents >= 0 ? '+' : ''}${_mad(cents)}';
int? _moneyCents(String input) {
  final value = double.tryParse(input.trim().replaceAll(',', '.'));
  return value == null ? null : (value * 100).round();
}

String _uuid() {
  final values = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  values[6] = (values[6] & 0x0f) | 0x40;
  values[8] = (values[8] & 0x3f) | 0x80;
  final hex = values
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
