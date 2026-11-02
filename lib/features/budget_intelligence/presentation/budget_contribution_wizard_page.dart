import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/budget_contribution_locale.dart';

import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/domain/household_member.dart';
import '../application/budget_contribution_calculator.dart';
import '../application/providers/remote_budget_provider.dart';
import '../domain/budget_intelligence.dart';

String _ct(BuildContext c, String k) => BudgetContributionWords.of(c).text(k);
String _cf(BuildContext c, String k, Map<String, Object> v) =>
    BudgetContributionWords.of(c).format(k, v);

/// A five-step, non-financial configuration flow for household contributions.
class BudgetContributionWizardPage extends ConsumerStatefulWidget {
  const BudgetContributionWizardPage({super.key, required this.scenarioId});

  final String scenarioId;

  @override
  ConsumerState<BudgetContributionWizardPage> createState() =>
      _BudgetContributionWizardPageState();
}

class _BudgetContributionWizardPageState
    extends ConsumerState<BudgetContributionWizardPage> {
  int _step = 0;
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  final _net = <String, TextEditingController>{};
  final _other = <String, TextEditingController>{};
  final _exceptional = <String, TextEditingController>{};
  final _treatments = <String, ExceptionalIncomeTreatment>{};

  @override
  void dispose() {
    for (final controller in [
      ..._net.values,
      ..._other.values,
      ..._exceptional.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _cents(TextEditingController? controller) =>
      ((double.tryParse((controller?.text ?? '').replaceAll(',', '.')) ?? 0) *
              100)
          .round();

  String _money(int cents) => '${(cents / 100).toStringAsFixed(2)} MAD';

  void _initialize(
    List<HouseholdMember> members,
    List<BudgetScenarioMemberIncome> stored,
  ) {
    if (_loaded) return;
    final byMember = {for (final income in stored) income.memberUserId: income};
    for (final member in members) {
      final income = byMember[member.id];
      _net[member.id] = TextEditingController(
        text: income == null
            ? ''
            : (income.netRecurringCents / 100).toStringAsFixed(2),
      );
      _other[member.id] = TextEditingController(
        text: income == null
            ? ''
            : (income.otherRecurringCents / 100).toStringAsFixed(2),
      );
      _exceptional[member.id] = TextEditingController(
        text: income == null
            ? ''
            : (income.exceptionalCents / 100).toStringAsFixed(2),
      );
      _treatments[member.id] =
          income?.exceptionalTreatment ?? ExceptionalIncomeTreatment.excluded;
    }
    _loaded = true;
  }

  List<BudgetScenarioMemberIncome> _incomes(List<HouseholdMember> members) =>
      List.unmodifiable(
        members.map(
          (member) => BudgetScenarioMemberIncome(
            memberUserId: member.id,
            netRecurringCents: _cents(_net[member.id]),
            otherRecurringCents: _cents(_other[member.id]),
            exceptionalCents: _cents(_exceptional[member.id]),
            exceptionalTreatment:
                _treatments[member.id] ?? ExceptionalIncomeTreatment.excluded,
          ),
        ),
      );

  Future<bool> _saveIncomes(List<HouseholdMember> members) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = await ref.read(
        budgetSupabaseRepositoryProvider.future,
      );
      for (final income in _incomes(members)) {
        await repository.saveMemberIncome(income, widget.scenarioId);
      }
      ref.invalidate(budgetScenarioMemberIncomesProvider(widget.scenarioId));
      return true;
    } catch (_) {
      if (mounted) {
        setState(() => _error = _ct(context, 'contribution.save_error'));
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, int> _directCharges(List<BudgetScenarioRule> rules) {
    final direct = <String, int>{};
    for (final rule in rules.where(
      (item) =>
          item.active &&
          item.fundingMode == BudgetFundingMode.personalMember &&
          item.fundingMemberUserId != null,
    )) {
      final memberId = rule.fundingMemberUserId!;
      direct[memberId] = (direct[memberId] ?? 0) + (rule.amountCents ?? 0);
    }
    return direct;
  }

  String _fundingLabel(BudgetFundingMode value) => switch (value) {
    BudgetFundingMode.personalMember => _ct(context, 'contribution.personal'),
    BudgetFundingMode.sharedAuto => _ct(context, 'contribution.shared_auto'),
    BudgetFundingMode.sharedCustom => _ct(
      context,
      'contribution.shared_custom',
    ),
    BudgetFundingMode.fixedByMember => _ct(
      context,
      'contribution.fixed_member',
    ),
    BudgetFundingMode.exceptionalIncome => _ct(
      context,
      'contribution.exceptional',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(remoteHouseholdMembersProvider);
    final rulesAsync = ref.watch(
      budgetScenarioRulesProvider(widget.scenarioId),
    );
    final incomesAsync = ref.watch(
      budgetScenarioMemberIncomesProvider(widget.scenarioId),
    );
    final envelopesAsync = ref.watch(remoteEnvelopeBalancesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_ct(context, 'contribution.title'))),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            Center(child: Text(_ct(context, 'contribution.members_error'))),
        data: (members) => incomesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              budgetContributionLoadMessage(
                error,
                productionFallback: _ct(context, 'contribution.incomes_error'),
              ),
            ),
          ),
          data: (storedIncomes) {
            _initialize(members, storedIncomes);
            final rules =
                rulesAsync.valueOrNull ?? const <BudgetScenarioRule>[];
            final Map<String, String> names = <String, String>{
              for (final member in members) member.id: member.displayName,
            };
            final Map<String, String> envelopeNames = <String, String>{
              for (final envelope
                  in envelopesAsync.valueOrNull ??
                      const <RemoteEnvelopeBalance>[])
                envelope.id: envelope.name,
            };
            final capacities = const BudgetContributionCalculator().calculate(
              incomes: _incomes(members),
              directChargesByMember: _directCharges(rules),
            );
            return Stepper(
              currentStep: _step,
              onStepContinue: _saving
                  ? null
                  : () async {
                      if (_step == 0 && !await _saveIncomes(members)) {
                        return;
                      }
                      if (mounted) {
                        setState(() => _step = (_step + 1).clamp(0, 4));
                      }
                    },
              onStepCancel: _step == 0
                  ? null
                  : () => setState(() => _step = (_step - 1).clamp(0, 4)),
              controlsBuilder: (context, details) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    FilledButton(
                      onPressed: details.onStepContinue,
                      child: Text(
                        _ct(
                          context,
                          _step == 4
                              ? 'contribution.finish'
                              : 'contribution.continue',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_step > 0)
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: Text(_ct(context, 'contribution.previous')),
                      ),
                  ],
                ),
              ),
              steps: [
                Step(
                  title: Text(_ct(context, 'contribution.incomes')),
                  isActive: _step >= 0,
                  content: _IncomeStep(
                    members: members,
                    net: _net,
                    other: _other,
                    exceptional: _exceptional,
                    treatments: _treatments,
                    onTreatmentChanged: (id, treatment) =>
                        setState(() => _treatments[id] = treatment),
                    error: _error,
                  ),
                ),
                Step(
                  title: Text(_ct(context, 'contribution.personal_charges')),
                  isActive: _step >= 1,
                  content: rulesAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) =>
                        Text(_ct(context, 'contribution.rules_error')),
                    data: (items) => _PersonalChargesStep(
                      rules: items,
                      names: names,
                      envelopeNames: envelopeNames,
                      fundingLabel: _fundingLabel,
                    ),
                  ),
                ),
                Step(
                  title: Text(_ct(context, 'contribution.shared_distribution')),
                  isActive: _step >= 2,
                  content: _ContributionCapacityStep(
                    capacities: capacities,
                    names: names,
                    money: _money,
                  ),
                ),
                Step(
                  title: Text(_ct(context, 'contribution.simulation')),
                  isActive: _step >= 3,
                  content: _SharedChargesStep(
                    rules: rules,
                    capacities: capacities,
                    names: names,
                    envelopeNames: envelopeNames,
                    fundingLabel: _fundingLabel,
                    money: _money,
                  ),
                ),
                Step(
                  title: Text(_ct(context, 'contribution.summary')),
                  isActive: _step >= 4,
                  content: _HouseholdSummaryStep(
                    incomes: _incomes(members),
                    capacities: capacities,
                    rules: rules,
                    names: names,
                    money: _money,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _IncomeStep extends StatelessWidget {
  const _IncomeStep({
    required this.members,
    required this.net,
    required this.other,
    required this.exceptional,
    required this.treatments,
    required this.onTreatmentChanged,
    required this.error,
  });
  final List<HouseholdMember> members;
  final Map<String, TextEditingController> net;
  final Map<String, TextEditingController> other;
  final Map<String, TextEditingController> exceptional;
  final Map<String, ExceptionalIncomeTreatment> treatments;
  final void Function(String, ExceptionalIncomeTreatment) onTreatmentChanged;
  final String? error;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(_ct(context, 'contribution.bonus_hint')),
      ...members.map(
        (member) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextField(
                  key: Key('income-net-${member.id}'),
                  controller: net[member.id],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _ct(context, 'contribution.salary'),
                  ),
                ),
                TextField(
                  key: Key('income-other-${member.id}'),
                  controller: other[member.id],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _ct(context, 'contribution.other_income'),
                  ),
                ),
                TextField(
                  key: Key('income-exceptional-${member.id}'),
                  controller: exceptional[member.id],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: _ct(context, 'contribution.exceptional_income'),
                  ),
                ),
                DropdownButtonFormField<ExceptionalIncomeTreatment>(
                  key: Key('exceptional-treatment-${member.id}'),
                  initialValue:
                      treatments[member.id] ??
                      ExceptionalIncomeTreatment.excluded,
                  decoration: InputDecoration(
                    labelText: _ct(
                      context,
                      'contribution.exceptional_treatment',
                    ),
                  ),
                  items: [
                    DropdownMenuItem<ExceptionalIncomeTreatment>(
                      value:
                          ExceptionalIncomeTreatment.includedInSharedCapacity,
                      child: Text(_ct(context, 'contribution.include_shared')),
                    ),
                    DropdownMenuItem<ExceptionalIncomeTreatment>(
                      value: ExceptionalIncomeTreatment.excluded,
                      child: Text(_ct(context, 'contribution.exclude_monthly')),
                    ),
                    DropdownMenuItem<ExceptionalIncomeTreatment>(
                      value: ExceptionalIncomeTreatment.directAllocation,
                      child: Text(_ct(context, 'contribution.direct_envelope')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) onTreatmentChanged(member.id, value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}

class _PersonalChargesStep extends StatelessWidget {
  const _PersonalChargesStep({
    required this.rules,
    required this.names,
    required this.envelopeNames,
    required this.fundingLabel,
  });
  final List<BudgetScenarioRule> rules;
  final Map<String, String> names;
  final Map<String, String> envelopeNames;
  final String Function(BudgetFundingMode) fundingLabel;
  @override
  Widget build(BuildContext context) {
    final personal = rules
        .where((rule) => rule.fundingMode == BudgetFundingMode.personalMember)
        .toList();
    if (personal.isEmpty) {
      return Text(_ct(context, 'contribution.no_personal'));
    }
    return Column(
      children: personal
          .map(
            (rule) => ListTile(
              title: Text(
                envelopeNames[rule.envelopeId] ??
                    _ct(context, 'contribution.envelope'),
              ),
              subtitle: Text(
                _cf(context, 'contribution.funding_member', {
                  'mode': fundingLabel(rule.fundingMode),
                  'member':
                      names[rule.fundingMemberUserId] ??
                      _ct(context, 'contribution.member_choose'),
                }),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ContributionCapacityStep extends StatelessWidget {
  const _ContributionCapacityStep({
    required this.capacities,
    required this.names,
    required this.money,
  });
  final List<BudgetMemberContribution> capacities;
  final Map<String, String> names;
  final String Function(int) money;
  @override
  Widget build(BuildContext context) {
    final showDistributionKey = capacities.length > 1;
    return Column(
      children: capacities
          .map(
            (member) => Card(
              child: ListTile(
                title: Text(
                  names[member.memberUserId] ??
                      _ct(context, 'contribution.household_member'),
                ),
                subtitle: Text(
                  _cf(context, 'contribution.capacity', {
                    'income': money(member.eligibleIncomeCents),
                    'charges': money(member.directChargesCents),
                    'capacity': money(member.contributionCapacityCents),
                    'deficit': member.rawCapacityCents < 0
                        ? _cf(context, 'contribution.deficit', {
                            'value': money(-member.rawCapacityCents),
                          })
                        : '',
                    'share': showDistributionKey
                        ? _cf(context, 'contribution.auto_share', {
                            'value': (member.autoShare * 100).toStringAsFixed(
                              2,
                            ),
                          })
                        : '',
                  }),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SharedChargesStep extends StatelessWidget {
  const _SharedChargesStep({
    required this.rules,
    required this.capacities,
    required this.names,
    required this.envelopeNames,
    required this.fundingLabel,
    required this.money,
  });
  final List<BudgetScenarioRule> rules;
  final List<BudgetMemberContribution> capacities;
  final Map<String, String> names;
  final Map<String, String> envelopeNames;
  final String Function(BudgetFundingMode) fundingLabel;
  final String Function(int) money;
  @override
  Widget build(BuildContext context) {
    final shared = rules
        .where((rule) => rule.fundingMode != BudgetFundingMode.personalMember)
        .toList();
    if (shared.isEmpty) return Text(_ct(context, 'contribution.no_shared'));
    return Column(
      children: shared.map((rule) {
        final total = rule.amountCents ?? 0;
        final contributions = _previewContributions(rule, total, capacities);
        return Card(
          child: ListTile(
            title: Text(
              envelopeNames[rule.envelopeId] ??
                  _ct(context, 'contribution.envelope'),
            ),
            subtitle: Text(
              _cf(context, 'contribution.shared_rule', {
                'budget': money(total),
                'mode': fundingLabel(rule.fundingMode),
                'payment': rule.fundingSourcePreference == null
                    ? ''
                    : _ct(context, 'contribution.usual_payment'),
                'members': contributions.entries
                    .map(
                      (entry) => _cf(context, 'contribution.member_amount', {
                        'member':
                            names[entry.key] ??
                            _ct(context, 'contribution.household_member'),
                        'amount': money(entry.value),
                      }),
                    )
                    .join('\n'),
              }),
            ),
          ),
        );
      }).toList(),
    );
  }

  Map<String, int> _previewContributions(
    BudgetScenarioRule rule,
    int total,
    List<BudgetMemberContribution> capacities,
  ) {
    if (rule.fundingMode == BudgetFundingMode.sharedAuto) {
      return const BudgetContributionCalculator().allocateSharedAuto(
        amountCents: total,
        members: capacities,
      );
    }
    if (rule.fundingMode == BudgetFundingMode.sharedCustom) {
      return _fromPercentages(rule.fundingDefinition, total);
    }
    if (rule.fundingMode == BudgetFundingMode.fixedByMember) {
      return {
        for (final entry in rule.fundingDefinition.entries)
          entry.key: (entry.value as num).toInt(),
      };
    }
    return const {};
  }

  Map<String, int> _fromPercentages(Map<String, Object?> shares, int total) {
    var assigned = 0;
    final entries = shares.entries.toList();
    final result = <String, int>{};
    for (var index = 0; index < entries.length; index++) {
      final amount = index == entries.length - 1
          ? total - assigned
          : (total * (entries[index].value as num).toDouble() / 100).round();
      result[entries[index].key] = amount;
      assigned += amount;
    }
    return result;
  }
}

class _HouseholdSummaryStep extends StatelessWidget {
  const _HouseholdSummaryStep({
    required this.incomes,
    required this.capacities,
    required this.rules,
    required this.names,
    required this.money,
  });
  final List<BudgetScenarioMemberIncome> incomes;
  final List<BudgetMemberContribution> capacities;
  final List<BudgetScenarioRule> rules;
  final Map<String, String> names;
  final String Function(int) money;
  @override
  Widget build(BuildContext context) {
    final recurring = incomes.fold<int>(
      0,
      (sum, item) => sum + item.netRecurringCents + item.otherRecurringCents,
    );
    final exceptional = incomes
        .where(
          (item) =>
              item.exceptionalTreatment ==
              ExceptionalIncomeTreatment.includedInSharedCapacity,
        )
        .fold<int>(0, (sum, item) => sum + item.exceptionalCents);
    final direct = capacities.fold<int>(
      0,
      (sum, item) => sum + item.directChargesCents,
    );
    final shared = rules
        .where((item) => item.fundingMode != BudgetFundingMode.personalMember)
        .fold<int>(0, (sum, item) => sum + (item.amountCents ?? 0));
    final resources = recurring + exceptional;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _ct(context, 'contribution.by_member'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        ...capacities.map(
          (item) => ListTile(
            title: Text(
              names[item.memberUserId] ??
                  _ct(context, 'contribution.household_member'),
            ),
            subtitle: Text(
              _cf(context, 'contribution.member_summary', {
                'income': money(item.eligibleIncomeCents),
                'charges': money(item.directChargesCents),
                'capacity': money(item.rawCapacityCents),
              }),
            ),
          ),
        ),
        const Divider(),
        Text(
          _ct(context, 'contribution.household_summary'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          _cf(context, 'contribution.recurring_total', {
            'value': money(recurring),
          }),
        ),
        Text(
          _cf(context, 'contribution.exceptional_total', {
            'value': money(exceptional),
          }),
        ),
        Text(
          _cf(context, 'contribution.resources_total', {
            'value': money(resources),
          }),
        ),
        Text(
          _cf(context, 'contribution.personal_total', {'value': money(direct)}),
        ),
        Text(
          _cf(context, 'contribution.shared_total', {'value': money(shared)}),
        ),
        Text(
          _cf(context, 'contribution.remaining', {
            'value': money(resources - direct - shared),
          }),
        ),
        const SizedBox(height: 12),
        Text(_ct(context, 'contribution.no_write_hint')),
      ],
    );
  }
}
