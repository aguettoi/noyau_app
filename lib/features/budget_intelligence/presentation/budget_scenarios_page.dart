import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../../core/localization/budget_scenarios_locale.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/domain/financial_account.dart';
import '../../finance/domain/household_member.dart';
import '../application/budget_contribution_calculator.dart';
import '../application/providers/remote_budget_provider.dart';
import '../domain/budget_intelligence.dart';
import 'programmable_budget_program_page.dart';

String _st(BuildContext c, String k) => BudgetScenarioWords.of(c).text(k);
String _sf(BuildContext c, String k, Map<String, Object> v) =>
    BudgetScenarioWords.of(c).format(k, v);

class BudgetScenariosPage extends ConsumerWidget {
  const BudgetScenariosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenarios = ref.watch(remoteBudgetScenariosProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_st(context, 'scenario.title'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-budget-scenario'),
        onPressed: () => _openScenarioEditor(context, ref),
        icon: const Icon(Icons.add),
        label: Text(_st(context, 'scenario.create')),
      ),
      body: scenarios.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            Center(child: Text(_st(context, 'scenario.load_error'))),
        data: (items) => ListView(
          children: [
            DesktopPageContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _st(context, 'scenario.title'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(_st(context, 'scenario.hint')),
                  const SizedBox(height: AppSpacing.md),
                  if (items.isEmpty)
                    Card(
                      child: ListTile(
                        title: Text(_st(context, 'scenario.empty')),
                        subtitle: Text(_st(context, 'scenario.empty_hint')),
                      ),
                    ),
                  ...items.map(
                    (scenario) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: CompactListRow(
                        title: scenario.name,
                        subtitle: _sf(context, 'scenario.summary', {
                          'state': _st(
                            context,
                            scenario.active
                                ? 'scenario.active'
                                : 'scenario.inactive',
                          ),
                          'description':
                              scenario.description?.trim().isEmpty ?? true
                              ? ''
                              : _sf(context, 'scenario.description_suffix', {
                                  'description': scenario.description!,
                                }),
                        }),
                        trailing: scenario.isDefault
                            ? Chip(
                                label: Text(_st(context, 'scenario.default')),
                              )
                            : TextButton(
                                key: Key(
                                  'set-default-budget-scenario-${scenario.id}',
                                ),
                                onPressed: () async {
                                  final repository = await ref.read(
                                    budgetSupabaseRepositoryProvider.future,
                                  );
                                  await repository.setScenarioDefault(
                                    scenarioId: scenario.id,
                                    isDefault: true,
                                  );
                                  ref.invalidate(remoteBudgetScenariosProvider);
                                },
                                child: Text(
                                  _st(context, 'scenario.set_default'),
                                ),
                              ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => BudgetScenarioDetailPage(
                              scenarioId: scenario.id,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openScenarioEditor(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ScenarioEditorDialog(),
    );
    if (result == true) {
      ref.invalidate(remoteBudgetScenariosProvider);
    }
  }
}

class BudgetScenarioDetailPage extends ConsumerWidget {
  const BudgetScenarioDetailPage({super.key, required this.scenarioId});
  final String scenarioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenarios = ref.watch(remoteBudgetScenariosProvider);
    return scenarios.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => Scaffold(
        body: Center(child: Text(_st(context, 'scenario.unavailable'))),
      ),
      data: (all) {
        final scenario = all.where((item) => item.id == scenarioId).firstOrNull;
        if (scenario == null) {
          return Scaffold(
            body: Center(child: Text(_st(context, 'scenario.not_found'))),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(scenario.name),
            actions: [
              IconButton(
                key: const Key('edit-programmable-budget'),
                tooltip: _st(context, 'scenario.program'),
                icon: const Icon(Icons.account_tree_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ProgrammableBudgetProgramPage(scenario: scenario),
                  ),
                ),
              ),
              IconButton(
                key: const Key('edit-budget-scenario'),
                tooltip: _st(context, 'scenario.edit'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final saved = await showDialog<bool>(
                    context: context,
                    builder: (_) => _ScenarioEditorDialog(scenario: scenario),
                  );
                  if (saved == true) {
                    ref.invalidate(remoteBudgetScenariosProvider);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            children: [
              DesktopPageContainer(
                maxWidth: AppLayout.formMaxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DesktopSection(
                      title: scenario.name,
                      subtitle:
                          scenario.description ??
                          _st(context, 'scenario.no_description'),
                      action: FilledButton.tonalIcon(
                        key: const Key('toggle-budget-scenario'),
                        onPressed: () async {
                          final repository = await ref.read(
                            budgetSupabaseRepositoryProvider.future,
                          );
                          await repository.saveScenario(
                            BudgetScenario(
                              id: scenario.id,
                              householdId: scenario.householdId,
                              name: scenario.name,
                              description: scenario.description,
                              active: !scenario.active,
                              priority: scenario.priority,
                              validFrom: scenario.validFrom,
                              validTo: scenario.validTo,
                              notes: scenario.notes,
                            ),
                          );
                          ref.invalidate(remoteBudgetScenariosProvider);
                        },
                        icon: Icon(
                          scenario.active
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                        label: Text(
                          _st(
                            context,
                            scenario.active
                                ? 'scenario.deactivate'
                                : 'scenario.activate',
                          ),
                        ),
                      ),
                      child: ResponsiveGrid(
                        minItemWidth: 340,
                        children: [
                          CompactListRow(
                            leading: Icon(Icons.payments_outlined),
                            title: _st(context, 'scenario.income_sources'),
                            subtitle: _st(
                              context,
                              'scenario.income_sources_hint',
                            ),
                          ),
                          CompactListRow(
                            leading: const Icon(Icons.account_tree_outlined),
                            title: _st(context, 'scenario.allocation_program'),
                            subtitle: _st(context, 'scenario.allocation_hint'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ProgrammableBudgetProgramPage(
                                  scenario: scenario,
                                ),
                              ),
                            ),
                          ),
                          CompactListRow(
                            leading: const Icon(Icons.auto_graph_outlined),
                            title: _st(context, 'scenario.preview'),
                            subtitle: _st(context, 'scenario.preview_hint'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        key: const Key('open-canonical-budget-program'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ProgrammableBudgetProgramPage(
                              scenario: scenario,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.account_tree_outlined),
                        label: Text(_st(context, 'scenario.configure_program')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compatibility-only renderer for legacy scenarios; not part of the canonical UI.
class LegacyRulesList extends ConsumerWidget {
  const LegacyRulesList({
    super.key,
    required this.scenario,
    required this.rules,
  });
  final BudgetScenario scenario;
  final List<BudgetScenarioRule> rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    return envelopes.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(_st(context, 'scenario.envelopes_error')),
      data: (all) {
        final names = {for (final envelope in all) envelope.id: envelope.name};
        if (rules.isEmpty) return Text(_st(context, 'scenario.no_rule'));
        return Column(
          children: rules
              .map(
                (rule) => Card(
                  child: ListTile(
                    title: Text(
                      names[rule.envelopeId] ??
                          _st(context, 'scenario.envelope_unavailable'),
                    ),
                    subtitle: Text(
                      _sf(context, 'scenario.rule_status', {
                        'rule': _ruleLabel(context, rule),
                        'state': _st(
                          context,
                          rule.active ? 'scenario.active' : 'scenario.inactive',
                        ),
                      }),
                    ),
                    trailing: IconButton(
                      key: Key('edit-budget-rule-${rule.id}'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final saved = await showDialog<bool>(
                          context: context,
                          builder: (_) => _RuleEditorDialog(
                            scenarioId: scenario.id,
                            rule: rule,
                            existingRules: rules,
                          ),
                        );
                        if (saved == true) {
                          ref.invalidate(
                            budgetScenarioRulesProvider(scenario.id),
                          );
                        }
                      },
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _ScenarioEditorDialog extends ConsumerStatefulWidget {
  const _ScenarioEditorDialog({this.scenario});
  final BudgetScenario? scenario;

  @override
  ConsumerState<_ScenarioEditorDialog> createState() =>
      _ScenarioEditorDialogState();
}

class _ScenarioEditorDialogState extends ConsumerState<_ScenarioEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late bool _active;
  late String _triggerType;
  DateTime? _effectiveOn;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.scenario?.name ?? '');
    _description = TextEditingController(
      text: widget.scenario?.description ?? '',
    );
    _active = widget.scenario?.active ?? true;
    _triggerType = widget.scenario?.triggerType ?? 'manual';
    _effectiveOn = DateTime.tryParse(
      widget.scenario?.triggerDefinition?['effective_on']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final words = BudgetScenarioWords.of(context);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = _st(context, 'scenario.name_error'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      final previous = widget.scenario;
      String? currentVersionId = previous?.currentVersionId;
      if (previous?.currentVersionId != null) {
        final versions = await ref.read(
          budgetScenarioVersionsProvider(previous!.id).future,
        );
        final nextVersion =
            versions.fold<int>(
              0,
              (highest, value) =>
                  value.version > highest ? value.version : highest,
            ) +
            1;
        currentVersionId = await repository.saveScenarioVersion(
          BudgetScenarioVersion(
            id: '',
            scenarioId: previous.id,
            version: nextVersion,
            createdAt: DateTime.now(),
            notes: words.format('scenario.version_note', {
              'version': nextVersion,
            }),
          ),
        );
      }
      await repository.saveScenario(
        BudgetScenario(
          id: previous?.id ?? '',
          householdId: repository.householdId,
          name: _name.text,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
          active: _active,
          priority: previous?.priority ?? 0,
          validFrom: previous?.validFrom,
          validTo: previous?.validTo,
          triggerType: _triggerType,
          triggerDefinition:
              _triggerType == 'date_reached' && _effectiveOn != null
              ? {
                  'effective_on': _effectiveOn!.toIso8601String().substring(
                    0,
                    10,
                  ),
                }
              : const {},
          notes: previous?.notes,
          isDefault: previous?.isDefault ?? false,
          currentVersionId: currentVersionId,
        ),
      );
      if (previous?.currentVersionId != null) {
        ref.invalidate(budgetScenarioVersionsProvider(previous!.id));
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = _st(context, 'scenario.scenario_save_error'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _st(
        context,
        widget.scenario == null ? 'scenario.new_title' : 'scenario.edit_title',
      ),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('budget-scenario-name'),
          controller: _name,
          decoration: InputDecoration(
            labelText: _st(context, 'scenario.name_required'),
          ),
        ),
        TextField(
          key: const Key('budget-scenario-description'),
          controller: _description,
          decoration: InputDecoration(
            labelText: _st(context, 'scenario.description'),
          ),
        ),
        SwitchListTile(
          title: Text(_st(context, 'scenario.active_label')),
          value: _active,
          onChanged: _saving
              ? null
              : (value) => setState(() => _active = value),
        ),
        DropdownButtonFormField<String>(
          key: const Key('budget-scenario-trigger'),
          initialValue: _triggerType,
          decoration: InputDecoration(
            labelText: _st(context, 'scenario.trigger'),
          ),
          items: [
            DropdownMenuItem(
              value: 'manual',
              child: Text(_st(context, 'scenario.manual')),
            ),
            DropdownMenuItem(
              value: 'date_reached',
              child: Text(_st(context, 'scenario.from_date')),
            ),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() => _triggerType = value ?? 'manual'),
        ),
        if (_triggerType == 'date_reached')
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_st(context, 'scenario.effective_date')),
            subtitle: Text(
              _effectiveOn == null
                  ? _st(context, 'scenario.undefined')
                  : MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(_effectiveOn!),
            ),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: _saving
                ? null
                : () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: _effectiveOn ?? DateTime.now(),
                    );
                    if (date != null) setState(() => _effectiveOn = date);
                  },
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: Text(_st(context, 'scenario.cancel')),
      ),
      FilledButton(
        key: const Key('save-budget-scenario'),
        onPressed: _saving ? null : _save,
        child: Text(
          _st(context, _saving ? 'scenario.saving' : 'scenario.save'),
        ),
      ),
    ],
  );
}

class _RuleEditorDialog extends ConsumerStatefulWidget {
  const _RuleEditorDialog({
    required this.scenarioId,
    this.rule,
    this.existingRules = const [],
  });
  final String scenarioId;
  final BudgetScenarioRule? rule;
  final List<BudgetScenarioRule> existingRules;

  @override
  ConsumerState<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends ConsumerState<_RuleEditorDialog> {
  String? _envelopeId;
  late BudgetAllocationMethod _method;
  late BudgetFundingMode _fundingMode;
  String? _fundingMemberId;
  String? _fundingPreference;
  final Map<String, TextEditingController> _memberValues =
      <String, TextEditingController>{};
  late final TextEditingController _value;
  late final TextEditingController _priority;
  late bool _active;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _envelopeId = widget.rule?.envelopeId;
    _method = widget.rule?.method ?? BudgetAllocationMethod.fixed;
    _value = TextEditingController(
      text: widget.rule?.method == BudgetAllocationMethod.percentage
          ? '${widget.rule?.percentage ?? ''}'
          : widget.rule?.amountCents == null
          ? ''
          : ((widget.rule!.amountCents!) / 100).toStringAsFixed(2),
    );
    _priority = TextEditingController(text: '${widget.rule?.priority ?? 0}');
    _active = widget.rule?.active ?? true;
    _fundingMode = widget.rule?.fundingMode ?? BudgetFundingMode.sharedAuto;
    _fundingMemberId = widget.rule?.fundingMemberUserId;
    _fundingPreference = widget.rule?.fundingSourcePreference;
  }

  @override
  void dispose() {
    _value.dispose();
    _priority.dispose();
    for (final controller in _memberValues.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save(
    List<RemoteEnvelopeBalance> envelopes,
    List<HouseholdMember> members,
  ) async {
    final selected = envelopes
        .where((item) => item.id == _envelopeId)
        .firstOrNull;
    if (selected == null || selected.isSystem || selected.isArchived) {
      setState(() => _error = _st(context, 'scenario.select_envelope'));
      return;
    }
    final duplicate = widget.existingRules.any(
      (rule) => rule.envelopeId == _envelopeId && rule.id != widget.rule?.id,
    );
    if (duplicate) {
      setState(() => _error = _st(context, 'scenario.duplicate_rule'));
      return;
    }
    final otherResidual = widget.existingRules.any(
      (rule) =>
          rule.method == BudgetAllocationMethod.residual &&
          rule.id != widget.rule?.id,
    );
    if (_method == BudgetAllocationMethod.residual && otherResidual) {
      setState(() => _error = _st(context, 'scenario.single_residual'));
      return;
    }
    final amount = _method == BudgetAllocationMethod.fixed
        ? _parseMoney(_value.text)
        : null;
    final percentage = _method == BudgetAllocationMethod.percentage
        ? double.tryParse(_value.text.replaceAll(',', '.'))
        : null;
    if ((_method == BudgetAllocationMethod.fixed &&
            (amount == null || amount <= 0)) ||
        (_method == BudgetAllocationMethod.percentage &&
            (percentage == null || percentage <= 0 || percentage > 100))) {
      setState(() => _error = _st(context, 'scenario.invalid_value'));
      return;
    }
    if ((_fundingMode == BudgetFundingMode.personalMember ||
            _fundingMode == BudgetFundingMode.exceptionalIncome) &&
        (_fundingMemberId == null ||
            !members.any((member) => member.id == _fundingMemberId))) {
      setState(() => _error = _st(context, 'scenario.select_member'));
      return;
    }
    final definition = _memberFundingDefinition(members);
    try {
      if (_fundingMode == BudgetFundingMode.sharedCustom) {
        BudgetContributionCalculator.validateCustomPercentages(
          definition.map(
            (id, value) => MapEntry(id, (value as num).toDouble()),
          ),
        );
      }
      if (_fundingMode == BudgetFundingMode.fixedByMember) {
        if (_method != BudgetAllocationMethod.fixed || amount == null) {
          throw StateError(_st(context, 'scenario.fixed_member_error'));
        }
        BudgetContributionCalculator.validateFixedContributions(
          definition.map((id, value) => MapEntry(id, (value as num).toInt())),
          amount,
        );
      }
    } on StateError catch (error) {
      setState(() => _error = error.message.toString());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      await repository.saveRule(
        BudgetScenarioRule(
          id: widget.rule?.id ?? '',
          scenarioId: widget.scenarioId,
          envelopeId: _envelopeId!,
          method: _method,
          priority: int.tryParse(_priority.text) ?? 0,
          rolloverPolicy:
              widget.rule?.rolloverPolicy ?? RolloverPolicy.reportTotal,
          amountCents: amount,
          percentage: percentage,
          minimumCents: widget.rule?.minimumCents,
          maximumCents: widget.rule?.maximumCents,
          rolloverCapCents: widget.rule?.rolloverCapCents,
          fundingSourcePreference: _fundingPreference,
          fundingMode: _fundingMode,
          fundingMemberUserId:
              _fundingMode == BudgetFundingMode.personalMember ||
                  _fundingMode == BudgetFundingMode.exceptionalIncome
              ? _fundingMemberId
              : null,
          fundingDefinition:
              _fundingMode == BudgetFundingMode.sharedCustom ||
                  _fundingMode == BudgetFundingMode.fixedByMember
              ? definition
              : const {},
          notes: widget.rule?.notes,
          active: _active,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = _st(context, 'scenario.rule_save_error'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, Object?> _memberFundingDefinition(List<HouseholdMember> members) {
    final definition = <String, Object?>{};
    for (final member in members) {
      final controller = _memberValues[member.id];
      // A controller may not yet exist while the asynchronous member list is
      // being mounted. An absent value means no contribution was entered.
      if (controller == null || controller.text.trim().isEmpty) continue;
      definition[member.id] = _fundingMode == BudgetFundingMode.sharedCustom
          ? double.tryParse(controller.text.replaceAll(',', '.')) ?? -1
          : _parseMoney(controller.text) ?? -1;
    }
    return Map.unmodifiable(definition);
  }

  @override
  Widget build(BuildContext context) {
    final envelopes = ref.watch(remoteEnvelopeBalancesProvider);
    final members = ref.watch(remoteHouseholdMembersProvider);
    final accounts = ref.watch(remoteAccountsProvider);
    return AlertDialog(
      title: Text(
        _st(
          context,
          widget.rule == null ? 'scenario.rule_add' : 'scenario.rule_edit',
        ),
      ),
      content: envelopes.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => Text(_st(context, 'scenario.envelopes_error')),
        data: (items) {
          final List<HouseholdMember> householdMembers =
              members.valueOrNull ?? const <HouseholdMember>[];
          for (final member in householdMembers) {
            _memberValues.putIfAbsent(
              member.id,
              () => TextEditingController(
                text:
                    widget.rule?.fundingDefinition[member.id]?.toString() ?? '',
              ),
            );
          }
          final eligible = items
              .where((item) => !item.isSystem && !item.isArchived)
              .toList();
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('budget-rule-envelope'),
                  initialValue: eligible.any((item) => item.id == _envelopeId)
                      ? _envelopeId
                      : null,
                  decoration: InputDecoration(
                    labelText: _st(context, 'scenario.envelope_required'),
                  ),
                  items: eligible
                      .map<DropdownMenuItem<String>>(
                        (item) => DropdownMenuItem<String>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _envelopeId = value),
                ),
                DropdownButtonFormField<BudgetAllocationMethod>(
                  key: const Key('budget-rule-method'),
                  initialValue: _method,
                  decoration: InputDecoration(
                    labelText: _st(context, 'scenario.method_required'),
                  ),
                  items: [
                    DropdownMenuItem<BudgetAllocationMethod>(
                      value: BudgetAllocationMethod.fixed,
                      child: Text(_st(context, 'scenario.fixed')),
                    ),
                    DropdownMenuItem<BudgetAllocationMethod>(
                      value: BudgetAllocationMethod.percentage,
                      child: Text(_st(context, 'scenario.percentage')),
                    ),
                    DropdownMenuItem<BudgetAllocationMethod>(
                      value: BudgetAllocationMethod.residual,
                      child: Text(_st(context, 'scenario.residual')),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _method = value!),
                ),
                if (_method != BudgetAllocationMethod.residual)
                  TextField(
                    key: const Key('budget-rule-value'),
                    controller: _value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _method == BudgetAllocationMethod.fixed
                          ? 'Montant MAD *'
                          : 'Pourcentage *',
                    ),
                  ),
                TextField(
                  controller: _priority,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _st(context, 'scenario.priority'),
                  ),
                ),
                DropdownButtonFormField<BudgetFundingMode>(
                  key: const Key('budget-rule-funding-mode'),
                  initialValue: _fundingMode,
                  decoration: InputDecoration(
                    labelText: _st(context, 'scenario.funding_mode'),
                  ),
                  items: [
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.personalMember,
                      child: Text(_st(context, 'scenario.personal')),
                    ),
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.sharedAuto,
                      child: Text(_st(context, 'scenario.shared_auto')),
                    ),
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.sharedCustom,
                      child: Text(_st(context, 'scenario.shared_custom')),
                    ),
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.fixedByMember,
                      child: Text(_st(context, 'scenario.fixed_member')),
                    ),
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.exceptionalIncome,
                      child: Text(_st(context, 'scenario.exceptional_direct')),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _fundingMode = value!),
                ),
                if (_fundingMode == BudgetFundingMode.personalMember ||
                    _fundingMode == BudgetFundingMode.exceptionalIncome)
                  DropdownButtonFormField<String>(
                    key: const Key('budget-rule-funding-member'),
                    initialValue:
                        householdMembers.any(
                          (member) => member.id == _fundingMemberId,
                        )
                        ? _fundingMemberId
                        : null,
                    decoration: InputDecoration(
                      labelText:
                          _fundingMode == BudgetFundingMode.exceptionalIncome
                          ? 'Membre qui affecte son revenu exceptionnel *'
                          : 'Membre *',
                    ),
                    items: householdMembers
                        .map<DropdownMenuItem<String>>(
                          (member) => DropdownMenuItem<String>(
                            value: member.id,
                            child: Text(member.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _fundingMemberId = value),
                  ),
                if (_fundingMode == BudgetFundingMode.sharedCustom ||
                    _fundingMode == BudgetFundingMode.fixedByMember) ...[
                  Text(
                    _fundingMode == BudgetFundingMode.sharedCustom
                        ? _st(context, 'scenario.custom_total')
                        : _st(context, 'scenario.fixed_total'),
                  ),
                  ...householdMembers.map(
                    (member) => TextField(
                      key: Key('budget-rule-member-value-${member.id}'),
                      controller: _memberValues[member.id],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '${member.displayName} ${_fundingMode == BudgetFundingMode.sharedCustom ? '(%)' : '(MAD)'}',
                      ),
                    ),
                  ),
                ],
                accounts.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => Text(_st(context, 'scenario.payment_error')),
                  data: (items) {
                    final List<FinancialAccount> eligibleAccounts = items
                        .where(
                          (account) => !account.isArchived && !account.isSystem,
                        )
                        .toList(growable: false);
                    return DropdownButtonFormField<String>(
                      key: const Key('budget-rule-funding-preference'),
                      initialValue:
                          eligibleAccounts.any(
                            (account) => account.id == _fundingPreference,
                          )
                          ? _fundingPreference
                          : null,
                      decoration: InputDecoration(
                        labelText: _st(context, 'scenario.payment_preference'),
                      ),
                      hint: Text(_st(context, 'scenario.no_preference')),
                      items: eligibleAccounts
                          .map<DropdownMenuItem<String>>(
                            (account) => DropdownMenuItem<String>(
                              value: account.id,
                              child: Text(account.name),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (value) =>
                                setState(() => _fundingPreference = value),
                    );
                  },
                ),
                SwitchListTile(
                  title: Text(_st(context, 'scenario.rule_active')),
                  value: _active,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _active = value),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(_st(context, 'scenario.cancel')),
        ),
        envelopes.maybeWhen(
          data: (items) => FilledButton(
            key: const Key('save-budget-rule'),
            onPressed: _saving || !members.hasValue
                ? null
                : () => _save(items, members.requireValue),
            child: Text(
              _st(context, _saving ? 'scenario.saving' : 'scenario.save'),
            ),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

String _ruleLabel(BuildContext context, BudgetScenarioRule rule) =>
    switch (rule.method) {
      BudgetAllocationMethod.fixed => _sf(context, 'scenario.fixed_value', {
        'value': '${((rule.amountCents ?? 0) / 100).toStringAsFixed(2)} MAD',
      }),
      BudgetAllocationMethod.percentage => _sf(
        context,
        'scenario.percentage_value',
        {'value': rule.percentage ?? 0},
      ),
      BudgetAllocationMethod.residual => _st(context, 'scenario.residual'),
      _ => _st(context, 'scenario.rule'),
    };

int? _parseMoney(String value) {
  final amount = double.tryParse(value.trim().replaceAll(',', '.'));
  return amount == null ? null : (amount * 100).round();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
