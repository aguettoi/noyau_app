import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../application/recurring_finance_provider.dart';
import '../domain/recurring_finance.dart';

class RecurringFinancePage extends ConsumerWidget {
  const RecurringFinancePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Opérations attendues'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Récurrences'),
            Tab(text: 'Prochaines occurrences'),
            Tab(text: 'Suggestions'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-recurring-intention'),
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Planifier'),
      ),
      body: TabBarView(
        children: [_Intentions(), _Occurrences(), _Suggestions()],
      ),
    ),
  );
}

class _Suggestions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(recurringPatternSuggestionsProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Suggestions indisponibles.')),
        data: (items) => items.isEmpty
            ? const Center(
                child: Text('Aucune récurrence suffisamment stable détectée.'),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.auto_graph_outlined),
                      title: Text('Détection assistée'),
                      subtitle: Text(
                        'Ces propositions sont explicables et ne créent aucune opération. Confirmez-les avant planification.',
                      ),
                    ),
                  ),
                  for (final item in items)
                    Card(
                      child: ListTile(
                        title: Text(item.label),
                        subtitle: Text(
                          '${item.typicalAmount.dirhams.toStringAsFixed(2)} MAD · ${_frequency(item.frequency)}\n${item.reasons.join(' • ')}',
                        ),
                        isThreeLine: true,
                        trailing: FilledButton.tonal(
                          onPressed: () =>
                              _createFromSuggestion(context, ref, item),
                          child: const Text('Examiner'),
                        ),
                      ),
                    ),
                ],
              ),
      );
}

Future<void> _createFromSuggestion(
  BuildContext context,
  WidgetRef ref,
  RecurringPatternSuggestion suggestion,
) => _create(context, ref, suggestion: suggestion);

class _Intentions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(remoteAccountsProvider).valueOrNull ?? const [];
    final envelopes =
        ref.watch(remoteEnvelopeBalancesProvider).valueOrNull ?? const [];
    final members =
        ref.watch(remoteHouseholdMembersProvider).valueOrNull ?? const [];
    final accountNames = {for (final item in accounts) item.id: item.name};
    final envelopeNames = {for (final item in envelopes) item.id: item.name};
    final memberNames = {for (final item in members) item.id: item.displayName};
    return ref
        .watch(recurringIntentionsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Récurrences indisponibles.')),
          data: (items) => items.isEmpty
              ? const Center(
                  child: Text('Aucune opération récurrente planifiée.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final i = items[index];
                    final details = <String>[
                      if (i.sourceAccountId != null)
                        '${i.type == RecurringEconomicType.accountTransfer ? 'Source' : 'Compte'} : ${accountNames[i.sourceAccountId] ?? 'Compte connu'}',
                      if (i.destinationAccountId != null)
                        '${i.type == RecurringEconomicType.accountTransfer ? 'Destination' : 'Compte'} : ${accountNames[i.destinationAccountId] ?? 'Compte connu'}',
                      if (i.envelopeId != null)
                        'Enveloppe : ${envelopeNames[i.envelopeId] ?? 'Enveloppe connue'}',
                      if (i.memberId != null)
                        'Membre : ${memberNames[i.memberId] ?? 'Membre du foyer'}',
                    ];
                    return Card(
                      child: ListTile(
                        title: Text(i.label),
                        subtitle: Text(
                          '${_kind(i.type)} · ${i.amount.dirhams.toStringAsFixed(2)} MAD · ${_frequency(i.frequency)}\n${i.certainty == RecurringCertainty.certain ? 'Engagement certain' : 'Estimation'} · ${_status(i.status)}${details.isEmpty ? '' : '\n${details.join(' • ')}'}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: details.isNotEmpty,
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: 'Modifier les prochaines occurrences',
                              onPressed: () =>
                                  _create(context, ref, current: i),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            PopupMenuButton<RecurringStatus>(
                              onSelected: (s) => ref
                                  .read(recurringFinanceActionsProvider)
                                  .status(i.id, s),
                              itemBuilder: (_) => [
                                if (i.status != RecurringStatus.active)
                                  const PopupMenuItem(
                                    value: RecurringStatus.active,
                                    child: Text('Réactiver'),
                                  ),
                                if (i.status == RecurringStatus.active)
                                  const PopupMenuItem(
                                    value: RecurringStatus.suspended,
                                    child: Text('Suspendre'),
                                  ),
                                if (i.status != RecurringStatus.stopped)
                                  const PopupMenuItem(
                                    value: RecurringStatus.stopped,
                                    child: Text('Arrêter'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
  }
}

class _Occurrences extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(expectedOccurrencesProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Occurrences indisponibles.')),
        data: (items) => items.isEmpty
            ? const Center(
                child: Text('Aucune occurrence dans la fenêtre actuelle.'),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final o = items[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(_icon(o.status)),
                      title: Text(o.label),
                      subtitle: Text(
                        '${DateFormat.yMMMd('fr').format(o.expectedOn)} · ${o.expectedAmount.dirhams.toStringAsFixed(2)} MAD\n${_occurrenceLabel(o)}',
                      ),
                      isThreeLine: true,
                      onTap: () => _reviewMatches(context, ref, o),
                      trailing:
                          o.status == ExpectedOccurrenceStatus.ignored ||
                              o.status == ExpectedOccurrenceStatus.realized
                          ? null
                          : IconButton(
                              tooltip: 'Ignorer cette occurrence',
                              onPressed: () =>
                                  _ignoreOccurrence(context, ref, o),
                              icon: const Icon(Icons.visibility_off_outlined),
                            ),
                    ),
                  );
                },
              ),
      );
}

Future<void> _ignoreOccurrence(
  BuildContext context,
  WidgetRef ref,
  ExpectedFinancialOccurrence occurrence,
) async {
  final reason = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Ignorer cette occurrence ?'),
      content: TextField(
        controller: reason,
        decoration: const InputDecoration(labelText: 'Motif obligatoire'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Ignorer'),
        ),
      ],
    ),
  );
  if (confirmed != true || reason.text.trim().isEmpty) return;
  await ref
      .read(recurringFinanceActionsProvider)
      .ignoreOccurrence(occurrence.id, reason.text);
}

Future<void> _reviewMatches(
  BuildContext context,
  WidgetRef ref,
  ExpectedFinancialOccurrence occurrence,
) async {
  final candidates = await ref.read(actualRecurringCandidatesProvider.future);
  final assessed = [
    for (final candidate in candidates)
      (
        candidate: candidate,
        assessment: assessExpectedMatch(
          occurrence,
          candidate,
          const MatchingTolerance(),
        ),
      ),
  ]..sort((a, b) => b.assessment.score.compareTo(a.assessment.score));
  final eligible = assessed.where((item) => item.assessment.eligible).toList();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Rapprochement attendu ↔ réalisé'),
      content: SizedBox(
        width: 520,
        child: eligible.isEmpty
            ? const Text(
                'Aucune opération réelle suffisamment proche. L’attente reste inchangée.',
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: eligible.length.clamp(0, 8),
                itemBuilder: (_, index) {
                  final item = eligible[index];
                  return Card(
                    child: ListTile(
                      title: Text(item.candidate.description),
                      subtitle: Text(
                        '${DateFormat.yMMMd('fr').format(item.candidate.occurredAt)} · ${item.candidate.amount.dirhams.toStringAsFixed(2)} MAD\n${item.assessment.reasons.join(' · ')}',
                      ),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Refuser ce candidat',
                            onPressed: () async {
                              await ref
                                  .read(recurringFinanceActionsProvider)
                                  .decideMatch(
                                    occurrence,
                                    item.candidate,
                                    MatchDecision.rejected,
                                  );
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            },
                            icon: const Icon(Icons.close),
                          ),
                          IconButton(
                            tooltip: 'Confirmer ce rapprochement',
                            onPressed: () async {
                              await ref
                                  .read(recurringFinanceActionsProvider)
                                  .decideMatch(
                                    occurrence,
                                    item.candidate,
                                    MatchDecision.confirmed,
                                  );
                              if (dialogContext.mounted) {
                                Navigator.pop(dialogContext);
                              }
                            },
                            icon: const Icon(Icons.check),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}

Future<void> _create(
  BuildContext context,
  WidgetRef ref, {
  RecurringFinancialIntention? current,
  RecurringPatternSuggestion? suggestion,
}) async {
  final accounts = await ref.read(remoteAccountsProvider.future);
  final envelopes = await ref.read(remoteEnvelopeBalancesProvider.future);
  final members = await ref.read(remoteHouseholdMembersProvider.future);
  if (!context.mounted) return;
  final activeAccounts = accounts
      .where((account) => !account.isArchived)
      .toList();
  final label = TextEditingController(
        text: current?.label ?? suggestion?.label ?? '',
      ),
      amount = TextEditingController(
        text:
            current?.amount.dirhams.toStringAsFixed(2) ??
            suggestion?.typicalAmount.dirhams.toStringAsFixed(2) ??
            '',
      );
  var type = current?.type ?? suggestion?.type ?? RecurringEconomicType.expense,
      frequency =
          current?.frequency ??
          suggestion?.frequency ??
          RecurringFrequency.monthly,
      certainty = current?.certainty ?? RecurringCertainty.certain;
  var starts =
      current?.startsOn ?? suggestion?.nextExpectedOn ?? DateTime.now();
  var sourceAccountId = current?.sourceAccountId;
  var destinationAccountId = current?.destinationAccountId;
  var concernedAccountId =
      suggestion?.accountId ??
      switch (current?.type) {
        RecurringEconomicType.income => current?.destinationAccountId,
        RecurringEconomicType.expense => current?.sourceAccountId,
        _ => null,
      };
  var envelopeId = current?.envelopeId ?? suggestion?.envelopeId;
  var memberId = current?.memberId ?? suggestion?.memberId;
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          current == null
              ? 'Planifier une opération'
              : 'Modifier la récurrence',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'Libellé'),
                ),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Montant attendu (MAD)',
                  ),
                ),
                DropdownButtonFormField<RecurringEconomicType>(
                  isExpanded: true,
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Nature'),
                  items: RecurringEconomicType.values
                      .map(
                        (v) =>
                            DropdownMenuItem(value: v, child: Text(_kind(v))),
                      )
                      .toList(),
                  onChanged: current == null
                      ? (v) => setState(() => type = v!)
                      : null,
                ),
                DropdownButtonFormField<RecurringFrequency>(
                  isExpanded: true,
                  initialValue: frequency,
                  decoration: const InputDecoration(labelText: 'Fréquence'),
                  items: RecurringFrequency.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(_frequency(v)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => frequency = v!),
                ),
                if (type == RecurringEconomicType.accountTransfer) ...[
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: sourceAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Compte source',
                    ),
                    items: activeAccounts
                        .map(
                          (account) => DropdownMenuItem(
                            value: account.id,
                            child: Text(account.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => sourceAccountId = value),
                  ),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: destinationAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Compte destination',
                    ),
                    items: activeAccounts
                        .map(
                          (account) => DropdownMenuItem(
                            value: account.id,
                            child: Text(account.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => destinationAccountId = value),
                  ),
                ] else
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: concernedAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Compte concerné (facultatif)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Non précisé'),
                      ),
                      ...activeAccounts.map(
                        (account) => DropdownMenuItem<String?>(
                          value: account.id,
                          child: Text(account.name),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => concernedAccountId = value),
                  ),
                if (type != RecurringEconomicType.accountTransfer)
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: envelopeId,
                    decoration: const InputDecoration(
                      labelText: 'Enveloppe (facultative)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Non précisée'),
                      ),
                      ...envelopes.map(
                        (envelope) => DropdownMenuItem<String?>(
                          value: envelope.id,
                          child: Text(envelope.name),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => envelopeId = value),
                  ),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: memberId,
                  decoration: const InputDecoration(
                    labelText: 'Membre concerné (facultatif)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Non précisé'),
                    ),
                    ...members.map(
                      (member) => DropdownMenuItem<String?>(
                        value: member.id,
                        child: Text(member.displayName),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => memberId = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Montant certain'),
                  subtitle: Text(
                    certainty == RecurringCertainty.certain
                        ? 'Engagement confirmé'
                        : 'Estimation ou dépense incertaine',
                  ),
                  value: certainty == RecurringCertainty.certain,
                  onChanged: (v) => setState(
                    () => certainty = v
                        ? RecurringCertainty.certain
                        : RecurringCertainty.estimated,
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Première occurrence'),
                  subtitle: Text(DateFormat.yMMMd('fr').format(starts)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: current != null
                      ? null
                      : () async {
                          final d = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            initialDate: starts,
                          );
                          if (d != null) setState(() => starts = d);
                        },
                ),
                const Text(
                  'Compte, enveloppe et membre peuvent rester inconnus. Aucun mouvement financier ne sera créé.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(current == null ? 'Planifier' : 'Enregistrer'),
          ),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) return;
  final parsed = double.tryParse(amount.text.replaceAll(',', '.'));
  if (label.text.trim().isEmpty || parsed == null || parsed <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Libellé et montant positif requis.')),
    );
    return;
  }
  if (type == RecurringEconomicType.accountTransfer &&
      (sourceAccountId == null ||
          destinationAccountId == null ||
          sourceAccountId == destinationAccountId)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Deux comptes distincts sont requis pour un transfert.'),
      ),
    );
    return;
  }
  final actions = ref.read(recurringFinanceActionsProvider);
  final effectiveSourceAccountId = switch (type) {
    RecurringEconomicType.expense => concernedAccountId,
    RecurringEconomicType.accountTransfer => sourceAccountId,
    RecurringEconomicType.income => null,
  };
  final effectiveDestinationAccountId = switch (type) {
    RecurringEconomicType.income => concernedAccountId,
    RecurringEconomicType.accountTransfer => destinationAccountId,
    RecurringEconomicType.expense => null,
  };
  if (current == null) {
    await actions.create(
      type: type,
      label: label.text,
      amount: Money.fromDirhams(parsed),
      frequency: frequency,
      startsOn: starts,
      certainty: certainty,
      sourceAccountId: effectiveSourceAccountId,
      destinationAccountId: effectiveDestinationAccountId,
      envelopeId: type == RecurringEconomicType.accountTransfer
          ? null
          : envelopeId,
      memberId: memberId,
    );
  } else {
    await actions.update(
      current: current,
      label: label.text,
      amount: Money.fromDirhams(parsed),
      frequency: frequency,
      certainty: certainty,
      sourceAccountId: effectiveSourceAccountId,
      destinationAccountId: effectiveDestinationAccountId,
      envelopeId: type == RecurringEconomicType.accountTransfer
          ? null
          : envelopeId,
      memberId: memberId,
    );
  }
}

String _kind(RecurringEconomicType v) => switch (v) {
  RecurringEconomicType.income => 'Revenu',
  RecurringEconomicType.expense => 'Dépense',
  RecurringEconomicType.accountTransfer => 'Transfert bancaire',
};
String _frequency(RecurringFrequency v) => switch (v) {
  RecurringFrequency.weekly => 'Chaque semaine',
  RecurringFrequency.monthly => 'Chaque mois',
  RecurringFrequency.yearly => 'Chaque année',
};
String _status(RecurringStatus v) => switch (v) {
  RecurringStatus.active => 'Active',
  RecurringStatus.suspended => 'Suspendue',
  RecurringStatus.stopped => 'Arrêtée',
};
String _occurrenceLabel(ExpectedFinancialOccurrence o) => switch (o.status) {
  ExpectedOccurrenceStatus.expected => 'Attendue — aucune écriture créée',
  ExpectedOccurrenceStatus.partiallyRealized =>
    'Partiellement réalisée · reste ${o.remaining.dirhams.toStringAsFixed(2)} MAD',
  ExpectedOccurrenceStatus.realized => 'Réalisée',
  ExpectedOccurrenceStatus.ignored => 'Ignorée',
  ExpectedOccurrenceStatus.overdue => 'Échue non réalisée',
};
IconData _icon(ExpectedOccurrenceStatus s) => switch (s) {
  ExpectedOccurrenceStatus.realized => Icons.check_circle,
  ExpectedOccurrenceStatus.partiallyRealized => Icons.timelapse,
  ExpectedOccurrenceStatus.overdue => Icons.warning_amber,
  ExpectedOccurrenceStatus.ignored => Icons.block,
  ExpectedOccurrenceStatus.expected => Icons.schedule,
};
