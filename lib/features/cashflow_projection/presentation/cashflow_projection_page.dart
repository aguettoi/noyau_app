import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
      appBar: AppBar(title: const Text('Prévisions de trésorerie')),
      body: projection.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Impossible de calculer la projection.')),
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
                decoration: const InputDecoration(
                  labelText: 'Scénario budgétaire',
                  helperText:
                      'Le scénario explique les allocations ; seules les opérations datées affectent la trésorerie.',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Scénario applicable automatiquement'),
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
              const Card(
                child: ListTile(
                  leading: Icon(Icons.savings_outlined),
                  title: Text('Épargne et fin de mois'),
                  subtitle: Text(
                    'Le reliquat de Navette, Nourriture et Sorties WE peut alimenter Epargne. '
                    'L’effet reste budgétaire tant qu’aucun transfert bancaire réel n’est confirmé.',
                  ),
                ),
              ),
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Projection explicable et sans écriture'),
                  subtitle: Text(
                    'Les allocations du budget ne sont pas additionnées aux opérations attendues. '
                    'FinancialAvailability reste la référence pour décider si une dépense est finançable.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HorizonSelector extends ConsumerWidget {
  const _HorizonSelector({required this.value});
  final ProjectionHorizon value;
  @override
  Widget build(BuildContext context, WidgetRef ref) => DropdownButtonFormField(
    key: const Key('cashflow-horizon'),
    isExpanded: true,
    initialValue: value,
    decoration: const InputDecoration(labelText: 'Horizon'),
    items: [
      for (final item in ProjectionHorizon.values)
        DropdownMenuItem(value: item, child: Text(_horizon(item))),
    ],
    onChanged: (next) {
      if (next != null) {
        ref.read(projectionHorizonProvider.notifier).state = next;
      }
    },
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.data});
  final CashflowProjection data;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Vue foyer', style: Theme.of(context).textTheme.titleLarge),
          Text('Du ${_date(data.asOf)} au ${_date(data.through)}'),
          if (data.scenarioName != null)
            Text('Scénario de référence : ${data.scenarioName}'),
          const Divider(),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _metric('Solde actuel', data.currentHouseholdBalance),
              _metric('Entrées attendues', data.income),
              _metric('Sorties attendues', data.expenses),
              _metric('Transferts internes', data.transfers),
              _metric('Solde projeté', data.projectedHouseholdBalance),
              _metric('À localiser', data.unlocatedAmount),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Risks extends StatelessWidget {
  const _Risks({required this.data});
  final CashflowProjection data;
  @override
  Widget build(BuildContext context) => Card(
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
            ? 'Aucun risque déterministe détecté'
            : 'Risques de trésorerie (${data.risks.length})',
      ),
      children: [
        for (final risk in data.risks)
          ListTile(title: Text(risk.message), subtitle: Text(_date(risk.date))),
      ],
    ),
  );
}

class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.data, required this.names});
  final CashflowProjection data;
  final Map<String, String> names;
  @override
  Widget build(BuildContext context) => _section(
    'Par compte',
    data.projectedAccountBalances.entries.map((entry) {
      final start =
          data.accountBalances[entry.key] ?? const Money.fromMinorUnits(0);
      return ListTile(
        title: Text(names[entry.key] ?? 'Compte'),
        subtitle: Text('Actuel ${_money(start)}'),
        trailing: Text(_money(entry.value)),
      );
    }),
  );
}

class _MemberSection extends StatelessWidget {
  const _MemberSection({required this.data, required this.names});
  final CashflowProjection data;
  final Map<String, String> names;
  @override
  Widget build(BuildContext context) => _section(
    'Par membre',
    data.memberDeltas.isEmpty
        ? [const ListTile(title: Text('Aucun flux attribué à un membre.'))]
        : data.memberDeltas.entries.map(
            (entry) => ListTile(
              title: Text(names[entry.key] ?? 'Membre'),
              trailing: Text(_signed(entry.value)),
            ),
          ),
  );
}

class _EnvelopeSection extends StatelessWidget {
  const _EnvelopeSection({required this.data, required this.names});
  final CashflowProjection data;
  final Map<String, String> names;
  @override
  Widget build(BuildContext context) => _section(
    'Par enveloppe',
    data.projectedEnvelopeBalances.entries.map((entry) {
      final start =
          data.envelopeBalances[entry.key] ?? const Money.fromMinorUnits(0);
      return ListTile(
        title: Text(names[entry.key] ?? 'Enveloppe'),
        subtitle: Text('Disponible actuellement ${_money(start)}'),
        trailing: Text(_money(entry.value)),
      );
    }),
  );
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
  Widget build(BuildContext context) => _section(
    'Chronologie et explications',
    data.flows.isEmpty
        ? [const ListTile(title: Text('Aucune opération future connue.'))]
        : data.flows.map((flow) {
            final details = <String>[
              flow.source,
              _certainty(flow.certainty),
              if (flow.sourceAccountId != null)
                'Depuis ${accountNames[flow.sourceAccountId] ?? 'compte connu'}',
              if (flow.destinationAccountId != null)
                'Vers ${accountNames[flow.destinationAccountId] ?? 'compte connu'}',
              if (flow.envelopeId != null)
                'Enveloppe ${envelopeNames[flow.envelopeId] ?? 'connue'}',
              if (flow.memberId != null)
                'Membre ${memberNames[flow.memberId] ?? 'connu'}',
              if (flow.kind != ProjectionFlowKind.internalTransfer &&
                  flow.sourceAccountId == null &&
                  flow.destinationAccountId == null)
                'Compte à déterminer',
              if (flow.envelopeId == null) 'Enveloppe à déterminer',
            ];
            return ListTile(
              leading: Icon(switch (flow.kind) {
                ProjectionFlowKind.income => Icons.south_west,
                ProjectionFlowKind.expense ||
                ProjectionFlowKind.financing => Icons.north_east,
                ProjectionFlowKind.internalTransfer => Icons.swap_horiz,
              }),
              title: Text(flow.label),
              subtitle: Text('${_date(flow.date)} • ${details.join(' • ')}'),
              trailing: Text(
                flow.kind == ProjectionFlowKind.internalTransfer
                    ? _money(flow.amount)
                    : _signed(Money.fromMinorUnits(flow.householdDelta)),
              ),
            );
          }),
  );
}

Widget _section(String title, Iterable<Widget> children) => Card(
  child: ExpansionTile(title: Text(title), children: children.toList()),
);
Widget _metric(String label, Money value) => SizedBox(
  width: 180,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Text(_money(value), style: const TextStyle(fontWeight: FontWeight.bold)),
    ],
  ),
);
String _money(Money value) => NumberFormat.currency(
  locale: 'fr_MA',
  symbol: 'MAD',
  decimalDigits: 2,
).format(value.dirhams);
String _signed(Money value) =>
    '${value.minorUnits >= 0 ? '+' : ''}${_money(value)}';
String _date(DateTime value) => DateFormat.yMMMd('fr').format(value);
String _certainty(ProjectionCertainty value) => switch (value) {
  ProjectionCertainty.certain => 'Certain',
  ProjectionCertainty.estimated => 'Estimé',
  ProjectionCertainty.hypothetical => 'Hypothèse',
};
String _horizon(ProjectionHorizon value) => switch (value) {
  ProjectionHorizon.endOfMonth => 'Fin du mois courant',
  ProjectionHorizon.nextMonth => 'Mois suivant',
  ProjectionHorizon.threeMonths => '3 mois',
  ProjectionHorizon.sixMonths => '6 mois',
  ProjectionHorizon.year => '12 mois',
};
