import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_design_system.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/domain/financial_account.dart';
import '../../finance/domain/household_member.dart';
import '../application/budget_contribution_calculator.dart';
import '../application/providers/remote_budget_provider.dart';
import '../domain/budget_intelligence.dart';
import 'programmable_budget_program_page.dart';

class BudgetScenariosPage extends ConsumerWidget {
  const BudgetScenariosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scenarios = ref.watch(remoteBudgetScenariosProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scénarios budgétaires')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-budget-scenario'),
        onPressed: () => _openScenarioEditor(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Créer'),
      ),
      body: scenarios.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Impossible de charger les scénarios.')),
        data: (items) => ListView(
          children: [
            DesktopPageContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scénarios budgétaires',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  const Text('Vos programmes de budget réutilisables.'),
                  const SizedBox(height: AppSpacing.md),
                  if (items.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('Aucun scénario'),
                        subtitle: Text(
                          'Créez un scénario pour préparer votre budget.',
                        ),
                      ),
                    ),
                  ...items.map(
                    (scenario) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: CompactListRow(
                        title: scenario.name,
                        subtitle:
                            '${scenario.active ? 'Actif' : 'Inactif'}${scenario.description?.trim().isEmpty ?? true ? '' : ' • ${scenario.description}'}',
                        trailing: scenario.isDefault
                            ? const Chip(label: Text('Par défaut'))
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
                                child: const Text('Définir par défaut'),
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
      error: (_, _) =>
          const Scaffold(body: Center(child: Text('Scénario indisponible.'))),
      data: (all) {
        final scenario = all.where((item) => item.id == scenarioId).firstOrNull;
        if (scenario == null) {
          return const Scaffold(
            body: Center(child: Text('Scénario introuvable.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(scenario.name),
            actions: [
              IconButton(
                key: const Key('edit-programmable-budget'),
                tooltip: 'Programme programmable',
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
                tooltip: 'Modifier',
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
                      subtitle: scenario.description ?? 'Aucune description',
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
                        label: Text(scenario.active ? 'Désactiver' : 'Activer'),
                      ),
                      child: ResponsiveGrid(
                        minItemWidth: 340,
                        children: [
                          const CompactListRow(
                            leading: Icon(Icons.payments_outlined),
                            title: 'Sources de revenus',
                            subtitle:
                                'Configurez les revenus utilisés par ce scénario.',
                          ),
                          CompactListRow(
                            leading: const Icon(Icons.account_tree_outlined),
                            title: 'Programme d’allocation',
                            subtitle:
                                'Définissez l’ordre et les règles de répartition.',
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ProgrammableBudgetProgramPage(
                                  scenario: scenario,
                                ),
                              ),
                            ),
                          ),
                          const CompactListRow(
                            leading: Icon(Icons.auto_graph_outlined),
                            title: 'Aperçu',
                            subtitle:
                                'Testez ce scénario avant de préparer un mois.',
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
                        label: const Text('Configurer sources et programme'),
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
      error: (_, _) => const Text('Enveloppes indisponibles.'),
      data: (all) {
        final names = {for (final envelope in all) envelope.id: envelope.name};
        if (rules.isEmpty) return const Text('Aucune règle configurée.');
        return Column(
          children: rules
              .map(
                (rule) => Card(
                  child: ListTile(
                    title: Text(
                      names[rule.envelopeId] ?? 'Enveloppe indisponible',
                    ),
                    subtitle: Text(
                      '${_ruleLabel(rule)} • ${rule.active ? 'Active' : 'Inactive'}',
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
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Le nom est obligatoire.');
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
            notes: 'Version $nextVersion créée après modification du modèle.',
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
        setState(() => _error = 'Impossible d’enregistrer le scénario.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.scenario == null ? 'Nouveau scénario' : 'Modifier le scénario',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          key: const Key('budget-scenario-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Nom *'),
        ),
        TextField(
          key: const Key('budget-scenario-description'),
          controller: _description,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        SwitchListTile(
          title: const Text('Actif'),
          value: _active,
          onChanged: _saving
              ? null
              : (value) => setState(() => _active = value),
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
        child: const Text('Annuler'),
      ),
      FilledButton(
        key: const Key('save-budget-scenario'),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
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
      setState(() => _error = 'Choisissez une enveloppe ordinaire active.');
      return;
    }
    final duplicate = widget.existingRules.any(
      (rule) => rule.envelopeId == _envelopeId && rule.id != widget.rule?.id,
    );
    if (duplicate) {
      setState(() => _error = 'Une règle existe déjà pour cette enveloppe.');
      return;
    }
    final otherResidual = widget.existingRules.any(
      (rule) =>
          rule.method == BudgetAllocationMethod.residual &&
          rule.id != widget.rule?.id,
    );
    if (_method == BudgetAllocationMethod.residual && otherResidual) {
      setState(() => _error = 'Une seule règle de reste est autorisée.');
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
      setState(
        () => _error = 'Saisissez une valeur strictement positive valide.',
      );
      return;
    }
    if ((_fundingMode == BudgetFundingMode.personalMember ||
            _fundingMode == BudgetFundingMode.exceptionalIncome) &&
        (_fundingMemberId == null ||
            !members.any((member) => member.id == _fundingMemberId))) {
      setState(
        () => _error =
            'Choisissez le membre qui finance cette charge personnelle.',
      );
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
          throw StateError(
            'Le montant fixe par membre requiert une règle à montant fixe.',
          );
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
        setState(() => _error = 'Impossible d’enregistrer la règle.');
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
        widget.rule == null ? 'Ajouter une règle' : 'Modifier la règle',
      ),
      content: envelopes.when(
        loading: () => const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (_, _) => const Text('Les enveloppes sont indisponibles.'),
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
                  decoration: const InputDecoration(labelText: 'Enveloppe *'),
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
                  decoration: const InputDecoration(labelText: 'Méthode *'),
                  items: const [
                    DropdownMenuItem<BudgetAllocationMethod>(
                      value: BudgetAllocationMethod.fixed,
                      child: Text('Montant fixe'),
                    ),
                    DropdownMenuItem<BudgetAllocationMethod>(
                      value: BudgetAllocationMethod.percentage,
                      child: Text('Pourcentage'),
                    ),
                    DropdownMenuItem<BudgetAllocationMethod>(
                      value: BudgetAllocationMethod.residual,
                      child: Text('Reste à répartir'),
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
                  decoration: const InputDecoration(labelText: 'Priorité'),
                ),
                DropdownButtonFormField<BudgetFundingMode>(
                  key: const Key('budget-rule-funding-mode'),
                  initialValue: _fundingMode,
                  decoration: const InputDecoration(
                    labelText: 'Mode de financement',
                  ),
                  items: const [
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.personalMember,
                      child: Text('Personnel'),
                    ),
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.sharedAuto,
                      child: Text('Commun — répartition automatique'),
                    ),
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.sharedCustom,
                      child: Text('Commun — répartition personnalisée'),
                    ),
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.fixedByMember,
                      child: Text('Montant fixe par membre'),
                    ),
                    DropdownMenuItem<BudgetFundingMode>(
                      value: BudgetFundingMode.exceptionalIncome,
                      child: Text('Revenu exceptionnel affecté directement'),
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
                        ? 'Répartition personnalisée (total : 100 %)'
                        : 'Contributions fixes (total : montant de la règle)',
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
                  error: (_, _) =>
                      const Text('Préférence de paiement indisponible.'),
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
                      decoration: const InputDecoration(
                        labelText: 'Compte / moyen de paiement habituel',
                      ),
                      hint: const Text('Aucune préférence'),
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
                  title: const Text('Règle active'),
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
          child: const Text('Annuler'),
        ),
        envelopes.maybeWhen(
          data: (items) => FilledButton(
            key: const Key('save-budget-rule'),
            onPressed: _saving || !members.hasValue
                ? null
                : () => _save(items, members.requireValue),
            child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
          ),
          orElse: () => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

String _ruleLabel(BudgetScenarioRule rule) => switch (rule.method) {
  BudgetAllocationMethod.fixed =>
    'Montant fixe : ${((rule.amountCents ?? 0) / 100).toStringAsFixed(2)} MAD',
  BudgetAllocationMethod.percentage =>
    'Pourcentage : ${rule.percentage ?? 0} %',
  BudgetAllocationMethod.residual => 'Reste à répartir',
  _ => 'Règle',
};

int? _parseMoney(String value) {
  final amount = double.tryParse(value.trim().replaceAll(',', '.'));
  return amount == null ? null : (amount * 100).round();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
