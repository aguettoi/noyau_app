import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
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

String _monthLabel(DateTime value) {
  const names = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];
  return '${names[value.month - 1][0].toUpperCase()}${names[value.month - 1].substring(1)} ${value.year}';
}

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

  Future<void> _preparePeriod() async {
    if (_preparingPeriod) return;
    setState(() {
      _preparingPeriod = true;
      _periodError = null;
    });
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      final id = await repository.prepareMonthlyPeriod(_month);
      ref.read(selectedBudgetPeriodIdProvider.notifier).state = id;
      ref.invalidate(remoteBudgetPeriodsProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _periodError = 'Impossible de préparer ce mois.');
      }
    } finally {
      if (mounted) setState(() => _preparingPeriod = false);
    }
  }

  Future<void> _newScenario() async {
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
            notes: 'Version initiale créée depuis la préparation mensuelle.',
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
        title: 'Dupliquer le scénario',
        initialName: '${source.name} — copie',
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
        title: const Text('Préparer mon mois'),
        actions: [
          IconButton(
            tooltip: 'Historique mensuel',
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
            const Center(child: Text('Périodes budgétaires indisponibles.')),
        data: (items) {
          final period = items
              .where(
                (item) =>
                    item.startsOn.year == _month.year &&
                    item.startsOn.month == _month.month,
              )
              .firstOrNull;
          if (period == null) {
            return _UnpreparedMonth(
              month: _month,
              preparing: _preparingPeriod,
              error: _periodError,
              onPrevious: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onPick: _pickMonth,
              onPrepare: _preparePeriod,
            );
          }
          return scenarios.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) =>
                const Center(child: Text('Scénarios indisponibles.')),
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
                                        'Budget — ${period.label}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleLarge,
                                      ),
                                      const Text('Statut : Non préparé'),
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
                                'Utiliser ${defaultScenario.name} pour ${period.label} ?',
                              ),
                              subtitle: const Text(
                                'Scénario mensuel par défaut',
                              ),
                              trailing: FilledButton(
                                key: const Key('use-default-monthly-scenario'),
                                onPressed: () => setState(
                                  () => _scenarioId = defaultScenario.id,
                                ),
                                child: const Text('Utiliser'),
                              ),
                            ),
                          ),
                        DesktopSection(
                          title: 'Choisir un scénario',
                          subtitle:
                              'Sélectionnez le programme à utiliser pour ce mois.',
                          action: TextButton.icon(
                            key: const Key('new-monthly-scenario'),
                            onPressed: _newScenario,
                            icon: const Icon(Icons.add),
                            label: const Text('Nouveau scénario'),
                          ),
                          child: ResponsiveGrid(
                            minItemWidth: 360,
                            children: active
                                .map(
                                  (scenario) => CompactListRow(
                                    title: scenario.name,
                                    subtitle:
                                        '${scenario.isDefault ? 'Scénario mensuel par défaut • ' : ''}${scenario.description ?? 'Sans description'}',
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          tooltip: 'Dupliquer',
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
                                          child: const Text('Utiliser'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                        if (active.isEmpty)
                          const Text(
                            'Aucun scénario actif. Créez votre premier modèle.',
                          ),
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
    this.error,
  });

  final DateTime month;
  final bool preparing;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onPrepare;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final label = _monthLabel(month);
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
            const Text('Aucun budget n’a encore été préparé pour ce mois.'),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              key: const Key('prepare-current-month'),
              onPressed: preparing ? null : onPrepare,
              child: Text(preparing ? 'Préparation…' : 'Préparer $label'),
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
          _monthLabel(month),
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
        const SnackBar(
          content: Text(
            'Le modèle programmable 080006 doit être installé avant l’enregistrement du snapshot.',
          ),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Mois enregistré. Aucune écriture financière n’a été créée.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’enregistrer le mois.')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Mois enregistré. Aucune écriture financière n’a été créée.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible d’enregistrer le mois.')),
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
          title: 'Scénario sélectionné : ${scenario.name}',
          subtitle:
              'Prévisualiser le budget de ${_monthLabel(widget.period.startsOn)}',
          child: ResponsiveGrid(
            minItemWidth: 420,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Version actuelle : ${currentVersion?.version ?? 'à créer'}',
                  ),
                  Text(
                    '${visibleTemplateSources.length} source(s) • ${effectiveSteps.length} étape(s) • ${effectiveSteps.map((step) => step.groupName).toSet().length} groupe(s)',
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
                        child: const Text('Modifier uniquement ce mois'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BudgetScenarioDetailPage(
                              scenarioId: scenario.id,
                            ),
                          ),
                        ),
                        child: const Text('Modifier le scénario modèle'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (usesProgrammableModel)
                    const Text(
                      'Mode programmable : seules les sources et étapes de cette version sont utilisées.',
                    )
                  else ...[
                    Text(
                      'Revenus du mois',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    incomes!.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => const Text('Revenus indisponibles.'),
                      data: (items) => Text(
                        '${items.length} source(s) de revenu à confirmer.',
                      ),
                    ),
                    rules!.when(
                      loading: () => const LinearProgressIndicator(),
                      error: (_, _) => const Text('Programme indisponible.'),
                      data: (items) =>
                          Text('${items.length} étape(s) du programme.'),
                    ),
                  ],
                ],
              ),
              if (visibleTemplateSources.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ressources du mois',
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
                                    ? 'Modifié ce mois • scénario : ${_mad(source.expectedCents)}'
                                    : 'Valeur scénario : ${_mad(source.expectedCents)}',
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
          const Card(
            child: Padding(
              padding: AppSpacing.card,
              child: Text(
                'Programme programmable incomplet : ajoutez au moins une étape avant de simuler et enregistrer le mois.',
              ),
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
          label: Text('Simuler ${_monthLabel(widget.period.startsOn)}'),
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
            label: Text('Prévisualiser ${_monthLabel(widget.period.startsOn)}'),
          ),
        if (_monthlySourceOverridesCents.isNotEmpty ||
            _monthlyStepOverrides.isNotEmpty)
          TextButton(
            onPressed: _resetMonthlyOverrides,
            child: const Text('Réinitialiser les modifications du mois'),
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
            'Synthèse foyer',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Revenus : ${_mad(analysis.incomeCents)}'),
          Text('Charges personnelles : ${_mad(analysis.personalChargesCents)}'),
          Text('Charges communes : ${_mad(analysis.commonChargesCents)}'),
          Text('Épargne : ${_mad(analysis.savingsCents)}'),
          Text('Reste : ${_mad(analysis.remainingCents)}'),
          const SizedBox(height: AppSpacing.sm),
          Text('KPIs', style: Theme.of(context).textTheme.titleMedium),
          Text(
            'Taux charges fixes : ${(analysis.fixedChargeRate * 100).toStringAsFixed(1)} %',
          ),
          Text(
            'Taux épargne : ${(analysis.savingsRate * 100).toStringAsFixed(1)} %',
          ),
          Text('Besoin espèces : ${_mad(analysis.cashNeedCents)}'),
          Text('Budget équilibré : ${analysis.isBalanced ? 'Oui' : 'Non'}'),
          if (previous != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Comparaison au mois précédent',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Revenus : ${_mad(analysis.incomeCents)} | ${_mad(previous!.availableCents)} | ${_delta(analysis.incomeCents - previous!.availableCents)}',
            ),
            Text(
              'Allocations : ${_mad(analysis.commonChargesCents)} | ${_mad(previous!.totalCents)} | ${_delta(analysis.commonChargesCents - previous!.totalCents)}',
            ),
            Text(
              'Reste : ${_mad(analysis.remainingCents)} | ${_mad(previous!.remainingCents)} | ${_delta(analysis.remainingCents - previous!.remainingCents)}',
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Synthèse membres',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...analysis.memberSummaries.map(
            (item) => Text(
              '${labels[item.memberUserId] ?? 'Membre du foyer'} • revenu ${_mad(item.incomeCents)} • charges ${_mad(item.personalChargesCents)} • contribution ${_mad(item.commonContributionCents)} • reste ${_mad(item.remainingCents)}',
            ),
          ),
          if (analysis.transferSuggestion != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Virement suggéré',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${labels[analysis.transferSuggestion!.fromMemberUserId] ?? 'Membre'} → ${labels[analysis.transferSuggestion!.toMemberUserId] ?? 'Membre'} : ${_mad(analysis.transferSuggestion!.amountCents)}',
            ),
            const Text(
              'Suggestion analytique uniquement : aucun virement n’est exécuté.',
            ),
          ],
          if (analysis.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Avertissements',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...analysis.warnings.map(Text.new),
          ],
          if (analysis.blockers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Blocages', style: Theme.of(context).textTheme.titleMedium),
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
            'Synthèse programmable',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Ressources : ${_mad(result.initialResourcesCents)}'),
          Text('Alloué : ${_mad(result.allocatedCents)}'),
          Text('Reste : ${_mad(result.remainingCents)}'),
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
            'Résultat de la prévisualisation',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Ressources : ${_mad(result.initialResourcesCents)}'),
          Text('Alloué : ${_mad(result.allocatedCents)}'),
          Text('Reste : ${_mad(result.remainingCents)}'),
          Text(
            result.isSimulable
                ? 'Budget simulable : Oui'
                : 'Budget simulable : Non',
          ),
          if (result.diagnostics.any(
            (item) =>
                item.severity == ProgrammableBudgetDiagnosticSeverity.warning,
          ))
            const Text(
              'Ce budget peut être enregistré, mais certains éléments méritent votre attention.',
            ),
          if (!result.isSimulable) ...[
            const Text(
              'Le budget ne peut pas être enregistré tant que les blocages suivants ne sont pas corrigés.',
            ),
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
              title: Text('${item.step.order} • ${item.step.groupName}'),
              subtitle: Text(
                '${source ?? 'Source non configurée'} • ${_mad(item.allocatedCents)}',
              ),
              trailing: TextButton(
                onPressed: () => onEditStep(item.step),
                child: const Text('Modifier cette étape'),
              ),
              leading: changed
                  ? const Chip(label: Text('Modifié ce mois'))
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
        snapshot['scenario_name'] as String? ?? 'Scénario préparé';
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
          'Budget préparé',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('Période : ${_monthLabel(month)}'),
        Text('Scénario : $scenarioName'),
        Text('Version : ${version ?? 'historique'}'),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Sources effectives',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (sources.isEmpty) const Text('Aucune source historisée.'),
        ...sources.map((source) {
          final name = source['name'] as String? ?? 'Source';
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
                  ? '${memberName == null ? '' : '$memberName • '}Modifié ce mois • ${_mad(effective)}'
                  : '${memberName == null ? '' : '$memberName • '}Valeur scénario • ${_mad(effective)}',
            ),
          );
        }),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Programme effectif',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (steps.isEmpty) const Text('Aucune étape historisée.'),
        ...steps.map((step) {
          final id = step['id'] as String?;
          final changed = id != null && stepOverrides.containsKey(id);
          final group = step['group'] as String? ?? 'Programme';
          final order = step['order'] as num? ?? 0;
          final method = _budgetMethodLabel(step['method'] as String?);
          final override = id == null
              ? const <String, Object?>{}
              : _snapshotMap(stepOverrides[id]);
          return ListTile(
            title: Text('$order. $group'),
            subtitle: Text(
              changed
                  ? '$method • Modifiée ce mois${_historicalStepOverrideDetails(override)}'
                  : method,
            ),
          );
        }),
        if (result.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text('Capacités', style: Theme.of(context).textTheme.titleMedium),
          ...capacities.map(
            (item) => ListTile(
              title: const Text('Membre du foyer'),
              subtitle: Text(
                'Capacité : ${_mad(_snapshotCents(item['capacity_cents']))} • Clé automatique : ${_snapshotPercent(item['auto_share'])}',
              ),
            ),
          ),
          Text('Résultats', style: Theme.of(context).textTheme.titleMedium),
          ...results.map(
            (item) => Text(
              '${_snapshotStepStatus(item['status'] as String?)} • demandé ${_mad(_snapshotCents(item['requested_cents']))} • alloué ${_mad(_snapshotCents(item['allocated_cents']))}',
            ),
          ),
          Text('Diagnostics', style: Theme.of(context).textTheme.titleMedium),
          if (diagnostics.isEmpty) const Text('Aucun diagnostic.'),
          ...diagnostics.map(
            (item) => Text(
              '${_snapshotDiagnosticLabel(item['severity'] as String?)} : ${item['message'] ?? 'Diagnostic'}',
            ),
          ),
          Text(
            result['simulable'] == true
                ? 'Budget simulable'
                : 'Budget non simulable',
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Consultation historique : aucune nouvelle simulation, sauvegarde ou écriture financière n’est effectuée.',
        ),
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
String _budgetMethodLabel(String? value) => switch (value) {
  'fixed' => 'Montant fixe',
  'percentage' => 'Pourcentage',
  'residual' => 'Reste',
  _ => 'Méthode d’allocation',
};
String _snapshotStepStatus(String? value) => switch (value) {
  'executed' => 'Exécutée',
  'partiallyExecuted' => 'Partiellement exécutée',
  'skipped' => 'Ignorée',
  'blocked' => 'Bloquée',
  'inactive' => 'Inactive',
  _ => 'Étape',
};
String _snapshotDiagnosticLabel(String? value) => switch (value) {
  'info' => 'Information',
  'warning' => 'Avertissement',
  'blocker' => 'Blocage',
  _ => 'Diagnostic',
};
String _historicalStepOverrideDetails(Map<String, Object?> override) {
  final amount = override['amount_cents'];
  if (amount is num) return ' • Montant : ${_mad(amount.toInt())}';
  final percentage = override['percentage'];
  if (percentage is num) return ' • Pourcentage : ${percentage.toString()} %';
  if (override['active'] == false) return ' • Désactivée ce mois';
  return '';
}

class _MonthlyScenarioDialog extends StatefulWidget {
  const _MonthlyScenarioDialog({
    this.title = 'Nouveau scénario',
    this.initialName,
    this.initialDescription,
  });
  final String title;
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
    title: const Text('Modifier uniquement ce mois'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Ces valeurs seront enregistrées dans le snapshot mensuel et ne modifieront pas le scénario modèle.',
          ),
          ...widget.incomes.map(
            (item) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Membre du foyer'),
                TextField(
                  key: Key('monthly-income-recurring-${item.memberUserId}'),
                  controller: _recurring[item.memberUserId],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Salaire réel (MAD)',
                  ),
                ),
                TextField(
                  key: Key('monthly-income-other-${item.memberUserId}'),
                  controller: _other[item.memberUserId],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Autre revenu (MAD)',
                  ),
                ),
                TextField(
                  key: Key('monthly-income-exceptional-${item.memberUserId}'),
                  controller: _exceptional[item.memberUserId],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prime / exceptionnel (MAD)',
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
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _save, child: const Text('Appliquer à ce mois')),
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
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('monthly-scenario-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nom *'),
          onChanged: (_) => setState(() {}),
        ),
        TextField(
          controller: _description,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        SwitchListTile(
          title: const Text('Scénario actif'),
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
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
        child: const Text('Créer'),
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
