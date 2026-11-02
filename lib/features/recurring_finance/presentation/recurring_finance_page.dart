import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money/money.dart';
import '../../../core/localization/recurring_finance_locale.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../finance/application/providers/remote_household_members_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../application/recurring_finance_provider.dart';
import '../domain/recurring_finance.dart';

class RecurringFinancePage extends ConsumerWidget {
  const RecurringFinancePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = RecurringFinanceWords.of(context);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(w.text('title')),
          bottom: TabBar(
            tabs: [
              Tab(text: w.text('recurrences')),
              Tab(text: w.text('occurrences')),
              Tab(text: w.text('suggestions')),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('add-recurring-intention'),
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.add),
          label: Text(w.text('plan')),
        ),
        body: TabBarView(
          children: [_Intentions(), _Occurrences(), _Suggestions()],
        ),
      ),
    );
  }
}

class _Suggestions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = RecurringFinanceWords.of(context);
    return ref
        .watch(recurringPatternSuggestionsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(w.text('suggestions_error'))),
          data: (items) => items.isEmpty
              ? Center(child: Text(w.text('suggestions_empty')))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.auto_graph_outlined),
                        title: Text(w.text('assisted')),
                        subtitle: Text(w.text('assisted_detail')),
                      ),
                    ),
                    for (final item in items)
                      Card(
                        child: ListTile(
                          title: Text(item.label),
                          subtitle: Text(
                            w.format('suggestion_detail', {
                              'amount':
                                  '${item.typicalAmount.dirhams.toStringAsFixed(2)} MAD',
                              'frequency': _frequency(w, item.frequency),
                              'reasons': item.reasons.join(' • '),
                            }),
                          ),
                          isThreeLine: true,
                          trailing: FilledButton.tonal(
                            onPressed: () =>
                                _createFromSuggestion(context, ref, item),
                            child: Text(w.text('review')),
                          ),
                        ),
                      ),
                  ],
                ),
        );
  }
}

Future<void> _createFromSuggestion(
  BuildContext context,
  WidgetRef ref,
  RecurringPatternSuggestion suggestion,
) => _create(context, ref, suggestion: suggestion);

class _Intentions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = RecurringFinanceWords.of(context);
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
          error: (_, _) => Center(child: Text(w.text('intentions_error'))),
          data: (items) => items.isEmpty
              ? Center(child: Text(w.text('intentions_empty')))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final i = items[index];
                    final details = <String>[
                      if (i.sourceAccountId != null)
                        '${w.text(i.type == RecurringEconomicType.accountTransfer ? 'source' : 'account')} : ${accountNames[i.sourceAccountId] ?? w.text('known_account')}',
                      if (i.destinationAccountId != null)
                        '${w.text(i.type == RecurringEconomicType.accountTransfer ? 'destination' : 'account')} : ${accountNames[i.destinationAccountId] ?? w.text('known_account')}',
                      if (i.envelopeId != null)
                        '${w.text('envelope')} : ${envelopeNames[i.envelopeId] ?? w.text('known_envelope')}',
                      if (i.memberId != null)
                        '${w.text('member')} : ${memberNames[i.memberId] ?? w.text('household_member')}',
                    ];
                    return Card(
                      child: ListTile(
                        title: Text(i.label),
                        subtitle: Text(
                          w.format('detail', {
                            'kind': _kind(w, i.type),
                            'amount':
                                '${i.amount.dirhams.toStringAsFixed(2)} MAD',
                            'frequency': _frequency(w, i.frequency),
                            'certainty': w.text(
                              i.certainty == RecurringCertainty.certain
                                  ? 'certain'
                                  : 'estimate',
                            ),
                            'status': _status(w, i.status),
                            'links': details.isEmpty
                                ? ''
                                : w.format('links', {
                                    'details': details.join(' • '),
                                  }),
                          }),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: details.isNotEmpty,
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: w.text('edit'),
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
                                  PopupMenuItem(
                                    value: RecurringStatus.active,
                                    child: Text(w.text('reactivate')),
                                  ),
                                if (i.status == RecurringStatus.active)
                                  PopupMenuItem(
                                    value: RecurringStatus.suspended,
                                    child: Text(w.text('suspend')),
                                  ),
                                if (i.status != RecurringStatus.stopped)
                                  PopupMenuItem(
                                    value: RecurringStatus.stopped,
                                    child: Text(w.text('stop')),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final w = RecurringFinanceWords.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return ref
        .watch(expectedOccurrencesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(w.text('occurrences_error'))),
          data: (items) => items.isEmpty
              ? Center(child: Text(w.text('occurrences_empty')))
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
                          w.format('occurrence_detail', {
                            'date': DateFormat.yMMMd(
                              locale,
                            ).format(o.expectedOn),
                            'amount':
                                '${o.expectedAmount.dirhams.toStringAsFixed(2)} MAD',
                            'status': _occurrenceLabel(w, o),
                          }),
                        ),
                        isThreeLine: true,
                        onTap: () => _reviewMatches(context, ref, o),
                        trailing:
                            o.status == ExpectedOccurrenceStatus.ignored ||
                                o.status == ExpectedOccurrenceStatus.realized
                            ? null
                            : IconButton(
                                tooltip: w.text('ignore_tooltip'),
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
}

Future<void> _ignoreOccurrence(
  BuildContext context,
  WidgetRef ref,
  ExpectedFinancialOccurrence occurrence,
) async {
  final w = RecurringFinanceWords.of(context);
  final reason = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(w.text('ignore_title')),
      content: TextField(
        controller: reason,
        decoration: InputDecoration(labelText: w.text('required_reason')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(w.text('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(w.text('ignore')),
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
  final w = RecurringFinanceWords.of(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
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
      title: Text(w.text('matching_title')),
      content: SizedBox(
        width: 520,
        child: eligible.isEmpty
            ? Text(w.text('no_match'))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: eligible.length.clamp(0, 8),
                itemBuilder: (_, index) {
                  final item = eligible[index];
                  return Card(
                    child: ListTile(
                      title: Text(item.candidate.description),
                      subtitle: Text(
                        w.format('candidate_detail', {
                          'date': DateFormat.yMMMd(
                            locale,
                          ).format(item.candidate.occurredAt),
                          'amount':
                              '${item.candidate.amount.dirhams.toStringAsFixed(2)} MAD',
                          'reasons': item.assessment.reasons.join(' · '),
                        }),
                      ),
                      isThreeLine: true,
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: w.text('reject_candidate'),
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
                            tooltip: w.text('confirm_match'),
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
          child: Text(w.text('close')),
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
  final w = RecurringFinanceWords.of(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
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
        title: Text(current == null ? w.text('create') : w.text('modify')),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  decoration: InputDecoration(labelText: w.text('label')),
                ),
                TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: w.text('expected_amount'),
                  ),
                ),
                DropdownButtonFormField<RecurringEconomicType>(
                  isExpanded: true,
                  initialValue: type,
                  decoration: InputDecoration(labelText: w.text('nature')),
                  items: RecurringEconomicType.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(_kind(w, v)),
                        ),
                      )
                      .toList(),
                  onChanged: current == null
                      ? (v) => setState(() => type = v!)
                      : null,
                ),
                DropdownButtonFormField<RecurringFrequency>(
                  isExpanded: true,
                  initialValue: frequency,
                  decoration: InputDecoration(labelText: w.text('frequency')),
                  items: RecurringFrequency.values
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(_frequency(w, v)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => frequency = v!),
                ),
                if (type == RecurringEconomicType.accountTransfer) ...[
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: sourceAccountId,
                    decoration: InputDecoration(
                      labelText: w.text('source_account'),
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
                    decoration: InputDecoration(
                      labelText: w.text('destination_account'),
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
                    decoration: InputDecoration(
                      labelText: w.text('optional_account'),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(w.text('unspecified_m')),
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
                    decoration: InputDecoration(
                      labelText: w.text('optional_envelope'),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(w.text('unspecified_f')),
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
                  decoration: InputDecoration(
                    labelText: w.text('optional_member'),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(w.text('unspecified_m')),
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
                  title: Text(w.text('certain_amount')),
                  subtitle: Text(
                    certainty == RecurringCertainty.certain
                        ? w.text('confirmed')
                        : w.text('uncertain'),
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
                  title: Text(w.text('first_occurrence')),
                  subtitle: Text(DateFormat.yMMMd(locale).format(starts)),
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
                Text(
                  w.text('no_movement'),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(w.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(current == null ? w.text('plan') : w.text('save')),
          ),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) return;
  final parsed = double.tryParse(amount.text.replaceAll(',', '.'));
  if (label.text.trim().isEmpty || parsed == null || parsed <= 0) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(w.text('invalid_form'))));
    return;
  }
  if (type == RecurringEconomicType.accountTransfer &&
      (sourceAccountId == null ||
          destinationAccountId == null ||
          sourceAccountId == destinationAccountId)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(w.text('distinct_accounts'))));
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

String _kind(RecurringFinanceWords w, RecurringEconomicType v) =>
    w.text('kind.${v.name}');
String _frequency(RecurringFinanceWords w, RecurringFrequency v) =>
    w.text('frequency.${v.name}');
String _status(RecurringFinanceWords w, RecurringStatus v) =>
    w.text('status.${v.name}');
String _occurrenceLabel(
  RecurringFinanceWords w,
  ExpectedFinancialOccurrence o,
) => switch (o.status) {
  ExpectedOccurrenceStatus.expected => w.text('occurrence.expected'),
  ExpectedOccurrenceStatus.partiallyRealized => w.format(
    'occurrence.partiallyRealized',
    {'amount': '${o.remaining.dirhams.toStringAsFixed(2)} MAD'},
  ),
  ExpectedOccurrenceStatus.realized => w.text('occurrence.realized'),
  ExpectedOccurrenceStatus.ignored => w.text('occurrence.ignored'),
  ExpectedOccurrenceStatus.overdue => w.text('occurrence.overdue'),
};
IconData _icon(ExpectedOccurrenceStatus s) => switch (s) {
  ExpectedOccurrenceStatus.realized => Icons.check_circle,
  ExpectedOccurrenceStatus.partiallyRealized => Icons.timelapse,
  ExpectedOccurrenceStatus.overdue => Icons.warning_amber,
  ExpectedOccurrenceStatus.ignored => Icons.block,
  ExpectedOccurrenceStatus.expected => Icons.schedule,
};
