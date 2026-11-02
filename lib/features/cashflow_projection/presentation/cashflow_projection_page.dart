import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/app_locale.dart';
import '../../../core/localization/cashflow_locale.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_design_system.dart';
import '../../budget_intelligence/application/providers/remote_budget_provider.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../application/cashflow_projection_provider.dart';
import '../domain/cashflow_projection.dart';

class CashflowProjectionPage extends ConsumerWidget {
  const CashflowProjectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = CashflowWords.of(context);
    final projection = ref.watch(cashflowProjectionProvider);
    final accounts = ref.watch(remoteAccountsProvider).valueOrNull ?? const [];
    final envelopes =
        ref.watch(remoteEnvelopeBalancesProvider).valueOrNull ?? const [];
    final members =
        ref.watch(remoteHouseholdMembersProvider).valueOrNull ?? const [];
    final scenarios =
        ref.watch(remoteBudgetScenariosProvider).valueOrNull ?? const [];
    final accountNames = {for (final a in accounts) a.id: a.name};
    final envelopeNames = {for (final e in envelopes) e.id: e.name};
    final memberNames = {for (final m in members) m.id: m.displayName};
    return Scaffold(
      appBar: AppBar(title: Text(words.text('cashflow.title'))),
      body: projection.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(words.text('cashflow.error'))),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(cashflowProjectionProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _HorizonSelector(value: ref.watch(projectionHorizonProvider)),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                key: const Key('cashflow-scenario'),
                isExpanded: true,
                initialValue: ref.watch(projectionScenarioIdProvider),
                decoration: InputDecoration(
                  labelText: words.text('cashflow.scenario'),
                  helperText: words.text('cashflow.scenario_help'),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(words.text('cashflow.scenario_auto')),
                  ),
                  for (final scenario in scenarios)
                    DropdownMenuItem<String?>(
                      value: scenario.id,
                      child: Text(scenario.name),
                    ),
                ],
                onChanged: (value) =>
                    ref.read(projectionScenarioIdProvider.notifier).state =
                        value,
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(words.text('cashflow.alternative_title')),
                  subtitle: Text(
                    words.format('cashflow.hypothesis_count', {
                      'count': ref
                          .watch(hypotheticalProjectionFlowsProvider)
                          .length,
                    }),
                  ),
                  trailing: Wrap(
                    children: [
                      if (ref
                          .watch(hypotheticalProjectionFlowsProvider)
                          .isNotEmpty)
                        IconButton(
                          tooltip: words.text('cashflow.clear_hypotheses'),
                          onPressed: () =>
                              ref
                                      .read(
                                        hypotheticalProjectionFlowsProvider
                                            .notifier,
                                      )
                                      .state =
                                  const [],
                          icon: const Icon(Icons.delete_outline),
                        ),
                      FilledButton.tonal(
                        onPressed: () => _addHypothesis(context, ref),
                        child: Text(words.text('cashflow.add')),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _Summary(data: data),
              const SizedBox(height: AppSpacing.md),
              _Risks(data: data),
              _AccountSection(data: data, names: accountNames),
              _MemberSection(data: data, names: memberNames),
              _EnvelopeSection(data: data, names: envelopeNames),
              _FlowSection(
                data: data,
                accountNames: accountNames,
                envelopeNames: envelopeNames,
                memberNames: memberNames,
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.savings_outlined),
                  title: Text(words.text('cashflow.savings_title')),
                  subtitle: Text(words.text('cashflow.savings_text')),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(words.text('cashflow.explainable_title')),
                  subtitle: Text(words.text('cashflow.explainable_text')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _addHypothesis(BuildContext context, WidgetRef ref) async {
  final words = CashflowWords.of(context);
  final label = TextEditingController();
  final amount = TextEditingController();
  var date = DateTime.now().add(const Duration(days: 1));
  var kind = ProjectionFlowKind.expense;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(words.text('cashflow.hypothesis_title')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: label,
                decoration: InputDecoration(
                  labelText: words.text('cashflow.label'),
                ),
              ),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: words.text('cashflow.amount'),
                ),
              ),
              DropdownButtonFormField<ProjectionFlowKind>(
                initialValue: kind,
                decoration: InputDecoration(
                  labelText: words.text('cashflow.effect'),
                ),
                items: [
                  DropdownMenuItem(
                    value: ProjectionFlowKind.income,
                    child: Text(words.text('cashflow.income')),
                  ),
                  DropdownMenuItem(
                    value: ProjectionFlowKind.expense,
                    child: Text(words.text('cashflow.expense')),
                  ),
                ],
                onChanged: (value) => setState(() => kind = value ?? kind),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(words.text('cashflow.business_date')),
                subtitle: Text(_date(context, date)),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    initialDate: date,
                  );
                  if (selected != null) setState(() => date = selected);
                },
              ),
              Text(
                words.text('cashflow.hypothesis_disclaimer'),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(words.text('cashflow.cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(words.text('cashflow.simulate')),
          ),
        ],
      ),
    ),
  );
  if (accepted != true) {
    return;
  }
  final value = double.tryParse(amount.text.trim().replaceAll(',', '.'));
  if (label.text.trim().isEmpty || value == null || value <= 0) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(words.text('cashflow.invalid_hypothesis'))),
      );
    }
    return;
  }
  final current = ref.read(hypotheticalProjectionFlowsProvider);
  ref.read(hypotheticalProjectionFlowsProvider.notifier).state = [
    ...current,
    ProjectionFlow(
      id: 'hypothesis:${DateTime.now().microsecondsSinceEpoch}',
      date: date,
      label: label.text.trim(),
      amount: Money.fromDirhams(value),
      kind: kind,
      certainty: ProjectionCertainty.hypothetical,
      source: 'Simulation locale — trajectoire alternative',
      explanation: ProjectionExplanation(
        rule: 'user_dated_hypothesis',
        sourceKind: 'simulation',
        sourceId: 'local',
        period: DateFormat('yyyy-MM-dd').format(date),
        reason: 'Hypothèse datée saisie explicitement par l’utilisateur.',
      ),
    ),
  ];
}

class _HorizonSelector extends ConsumerWidget {
  const _HorizonSelector({required this.value});
  final ProjectionHorizon value;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = CashflowWords.of(context);
    return DropdownButtonFormField(
      key: const Key('cashflow-horizon'),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: words.text('cashflow.horizon')),
      items: [
        for (final item in ProjectionHorizon.values)
          DropdownMenuItem(value: item, child: Text(_horizon(words, item))),
      ],
      onChanged: (next) {
        if (next != null) {
          ref.read(projectionHorizonProvider.notifier).state = next;
        }
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.data});
  final CashflowProjection data;
  @override
  Widget build(BuildContext context) {
    final words = CashflowWords.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              words.text('cashflow.household_view'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              words.format('cashflow.period', {
                'start': _date(context, data.asOf),
                'end': _date(context, data.through),
              }),
            ),
            if (data.scenarioName != null)
              Text(
                words.format('cashflow.reference_scenario', {
                  'scenario': data.scenarioName!,
                }),
              ),
            const Divider(),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.sm,
              children: [
                _metric(
                  context,
                  words.text('cashflow.current_balance'),
                  data.currentHouseholdBalance,
                ),
                _metric(
                  context,
                  words.text('cashflow.expected_income'),
                  data.income,
                ),
                _metric(
                  context,
                  words.text('cashflow.expected_expenses'),
                  data.expenses,
                ),
                _metric(
                  context,
                  words.text('cashflow.internal_transfers'),
                  data.transfers,
                ),
                _metric(
                  context,
                  words.text('cashflow.projected_balance'),
                  data.projectedHouseholdBalance,
                ),
                _metric(
                  context,
                  words.text('cashflow.unlocated'),
                  data.unlocatedAmount,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Risks extends StatelessWidget {
  const _Risks({required this.data});
  final CashflowProjection data;
  @override
  Widget build(BuildContext context) {
    final words = CashflowWords.of(context);
    return Card(
      color: data.risks.isEmpty
          ? null
          : Theme.of(context).colorScheme.errorContainer,
      child: ExpansionTile(
        initiallyExpanded: data.risks.isNotEmpty,
        leading: Icon(
          data.risks.isEmpty ? Icons.check_circle_outline : Icons.warning_amber,
        ),
        title: Text(
          data.risks.isEmpty
              ? words.text('cashflow.no_risk')
              : words.format('cashflow.risks', {'count': data.risks.length}),
        ),
        children: [
          for (final risk in data.risks)
            ListTile(
              title: Text(_riskMessage(words, risk.message)),
              subtitle: Text(_date(context, risk.date)),
            ),
        ],
      ),
    );
  }
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.data, required this.names});
  final CashflowProjection data;
  final Map<String, String> names;
  @override
  Widget build(BuildContext context) {
    final words = CashflowWords.of(context);
    return _section(
      words.text('cashflow.by_account'),
      data.projectedAccountBalances.entries.map((entry) {
        final start =
            data.accountBalances[entry.key] ?? const Money.fromMinorUnits(0);
        return ListTile(
          title: Text(names[entry.key] ?? words.text('cashflow.account')),
          subtitle: Text(
            words.format('cashflow.current', {
              'amount': _money(context, start),
            }),
          ),
          trailing: Text(_money(context, entry.value)),
        );
      }),
    );
  }
}

class _MemberSection extends StatelessWidget {
  const _MemberSection({required this.data, required this.names});
  final CashflowProjection data;
  final Map<String, String> names;
  @override
  Widget build(BuildContext context) {
    final words = CashflowWords.of(context);
    return _section(
      words.text('cashflow.by_member'),
      data.memberDeltas.isEmpty
          ? [ListTile(title: Text(words.text('cashflow.no_member_flow')))]
          : data.memberDeltas.entries.map(
              (entry) => ListTile(
                title: Text(names[entry.key] ?? words.text('cashflow.member')),
                trailing: Text(_signed(context, entry.value)),
              ),
            ),
    );
  }
}

class _EnvelopeSection extends StatelessWidget {
  const _EnvelopeSection({required this.data, required this.names});
  final CashflowProjection data;
  final Map<String, String> names;
  @override
  Widget build(BuildContext context) {
    final words = CashflowWords.of(context);
    return _section(
      words.text('cashflow.by_envelope'),
      data.projectedEnvelopeBalances.entries.map((entry) {
        final start =
            data.envelopeBalances[entry.key] ?? const Money.fromMinorUnits(0);
        return ListTile(
          title: Text(names[entry.key] ?? words.text('cashflow.envelope')),
          subtitle: Text(
            words.format('cashflow.current_available', {
              'amount': _money(context, start),
            }),
          ),
          trailing: Text(_money(context, entry.value)),
        );
      }),
    );
  }
}

class _FlowSection extends StatelessWidget {
  const _FlowSection({
    required this.data,
    required this.accountNames,
    required this.envelopeNames,
    required this.memberNames,
  });
  final CashflowProjection data;
  final Map<String, String> accountNames, envelopeNames, memberNames;
  @override
  Widget build(BuildContext context) {
    final words = CashflowWords.of(context);
    return _section(
      words.text('cashflow.timeline'),
      data.flows.isEmpty
          ? [ListTile(title: Text(words.text('cashflow.no_future_flow')))]
          : data.flows.map((flow) {
              final details = <String>[
                _sourceLabel(words, flow.source),
                _certainty(words, flow.certainty),
                if (flow.sourceAccountId != null)
                  words.format('cashflow.from', {
                    'account':
                        accountNames[flow.sourceAccountId] ??
                        words.text('cashflow.known_account'),
                  }),
                if (flow.destinationAccountId != null)
                  words.format('cashflow.to', {
                    'account':
                        accountNames[flow.destinationAccountId] ??
                        words.text('cashflow.known_account'),
                  }),
                if (flow.envelopeId != null)
                  words.format('cashflow.envelope_detail', {
                    'envelope':
                        envelopeNames[flow.envelopeId] ??
                        words.text('cashflow.known_envelope'),
                  }),
                if (flow.memberId != null)
                  words.format('cashflow.member_detail', {
                    'member':
                        memberNames[flow.memberId] ??
                        words.text('cashflow.known_member'),
                  }),
                if (flow.kind != ProjectionFlowKind.internalTransfer &&
                    flow.sourceAccountId == null &&
                    flow.destinationAccountId == null)
                  words.text('cashflow.account_unknown'),
                if (flow.envelopeId == null)
                  words.text('cashflow.envelope_unknown'),
              ];
              return ListTile(
                leading: Icon(switch (flow.kind) {
                  ProjectionFlowKind.income => Icons.south_west,
                  ProjectionFlowKind.expense ||
                  ProjectionFlowKind.financing => Icons.north_east,
                  ProjectionFlowKind.internalTransfer => Icons.swap_horiz,
                }),
                title: Text(flow.label),
                subtitle: Text(
                  words.format('cashflow.flow_detail', {
                    'date': _date(context, flow.date),
                    'details': details.join(' • '),
                  }),
                ),
                trailing: Text(
                  flow.kind == ProjectionFlowKind.internalTransfer
                      ? _money(context, flow.amount)
                      : _signed(
                          context,
                          Money.fromMinorUnits(flow.householdDelta),
                        ),
                ),
              );
            }),
    );
  }
}

Widget _section(String title, Iterable<Widget> children) => Card(
  child: ExpansionTile(title: Text(title), children: children.toList()),
);
Widget _metric(BuildContext context, String label, Money value) => SizedBox(
  width: 180,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Text(
        _money(context, value),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    ],
  ),
);
String _money(BuildContext context, Money value) => NumberFormat.currency(
  locale: _intlLocale(CashflowWords.of(context).language),
  symbol: 'MAD',
  decimalDigits: 2,
).format(value.dirhams);
String _signed(BuildContext context, Money value) =>
    '${value.minorUnits >= 0 ? '+' : ''}${_money(context, value)}';
String _date(BuildContext context, DateTime value) => DateFormat.yMMMd(
  _intlLocale(CashflowWords.of(context).language),
).format(value);
String _certainty(CashflowWords words, ProjectionCertainty value) =>
    switch (value) {
      ProjectionCertainty.certain => words.text('cashflow.certainty.certain'),
      ProjectionCertainty.estimated => words.text(
        'cashflow.certainty.estimated',
      ),
      ProjectionCertainty.hypothetical => words.text(
        'cashflow.certainty.hypothetical',
      ),
    };
String _horizon(CashflowWords words, ProjectionHorizon value) =>
    switch (value) {
      ProjectionHorizon.endOfMonth => words.text('cashflow.horizon.month_end'),
      ProjectionHorizon.nextMonth => words.text('cashflow.horizon.next_month'),
      ProjectionHorizon.threeMonths => words.text(
        'cashflow.horizon.three_months',
      ),
      ProjectionHorizon.sixMonths => words.text('cashflow.horizon.six_months'),
      ProjectionHorizon.year => words.text('cashflow.horizon.year'),
    };

String _intlLocale(AppLanguage language) => switch (language) {
  AppLanguage.french => 'fr_MA',
  AppLanguage.english => 'en',
  AppLanguage.arabic || AppLanguage.darija => 'ar_MA',
};

String _sourceLabel(CashflowWords words, String source) => switch (source) {
  'Simulation locale — trajectoire alternative' => words.text(
    'cashflow.source.local',
  ),
  'R3.1 — opération attendue' => words.text('cashflow.source.expected'),
  'Obligations — solde dérivé et échéance canonique' => words.text(
    'cashflow.source.obligation',
  ),
  'F6 — coût automobile planifié' => words.text('cashflow.source.vehicle'),
  'F5 — échéancier de financement' => words.text('cashflow.source.financing'),
  _ => source,
};

String _riskMessage(CashflowWords words, String message) {
  final match = RegExp(r'« (.+) »').firstMatch(message);
  if (match == null) return message;
  final label = match.group(1)!;
  if (message.startsWith('Un compte')) {
    return words.format('cashflow.risk.account', {'label': label});
  }
  if (message.startsWith('La trésorerie')) {
    return words.format('cashflow.risk.household', {'label': label});
  }
  return message;
}
