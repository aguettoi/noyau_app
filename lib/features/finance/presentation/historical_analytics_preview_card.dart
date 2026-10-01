import 'package:flutter/material.dart';

import '../application/historical_analytics.dart';
import '../application/workbook_import.dart';

enum _ReviewFilter {
  all('Toutes'),
  expenses('Dépenses'),
  positives('Positifs à valider'),
  duplicates('Répétitions à contrôler'),
  transfers('Transferts internes'),
  adjustments('Ajustements techniques'),
  ignored('Ignorés'),
  validated('Validés');

  const _ReviewFilter(this.label);
  final String label;
}

enum _ReviewSort {
  date('Date'),
  amount('Montant'),
  envelope('Enveloppe'),
  classification('Classification');

  const _ReviewSort(this.label);
  final String label;
}

enum _DuplicateDecision { keep, ignore, review }

class HistoricalAnalyticsPreviewCard extends StatefulWidget {
  const HistoricalAnalyticsPreviewCard({super.key, required this.analysis});
  final WorkbookImportAnalysis analysis;

  @override
  State<HistoricalAnalyticsPreviewCard> createState() =>
      _HistoricalAnalyticsPreviewCardState();
}

class _HistoricalAnalyticsPreviewCardState
    extends State<HistoricalAnalyticsPreviewCard> {
  late final HistoricalAnalyticsPreview preview =
      const HistoricalAnalyticsPreviewBuilder().build(widget.analysis);
  final Map<int, HistoricalAnalyticClassification> localDecisions = {};
  final Map<int, _DuplicateDecision> duplicateDecisions = {};

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Historique analytique — aperçu local',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Période retenue : 01/05/2026 au 29/09/2026. '
            'Aucune écriture financière et aucune donnée Supabase ne sont créées par cet aperçu.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              Text('${preview.lines.length} lignes retenues'),
              Text(
                '${preview.count(HistoricalAnalyticClassification.expense)} dépenses analytiques',
              ),
              Text(
                '${preview.count(HistoricalAnalyticClassification.ambiguousPositive)} positifs à valider',
              ),
              Text(
                '${preview.duplicateCandidates} lignes avec répétition à contrôler',
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const Key('historical-analytics-review'),
            onPressed: preview.lines.isEmpty ? null : _openReview,
            icon: const Icon(Icons.manage_search),
            label: const Text('Examiner les propositions'),
          ),
        ],
      ),
    ),
  );

  Future<void> _openReview() => showDialog<void>(
    context: context,
    builder: (_) => _ReviewDialog(
      preview: preview,
      decisions: localDecisions,
      duplicateDecisions: duplicateDecisions,
      onDecision: () => setState(() {}),
    ),
  );
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.preview,
    required this.decisions,
    required this.duplicateDecisions,
    required this.onDecision,
  });
  final HistoricalAnalyticsPreview preview;
  final Map<int, HistoricalAnalyticClassification> decisions;
  final Map<int, _DuplicateDecision> duplicateDecisions;
  final VoidCallback onDecision;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  _ReviewFilter filter = _ReviewFilter.all;
  _ReviewSort sort = _ReviewSort.date;
  bool ascending = true;
  String query = '';

  HistoricalAnalyticClassification current(HistoricalAnalyticLine line) =>
      widget.decisions[line.sourceRowNumber] ?? line.classification;
  bool ignored(HistoricalAnalyticLine line) =>
      current(line) == HistoricalAnalyticClassification.ignored ||
      widget.duplicateDecisions[line.sourceRowNumber] ==
          _DuplicateDecision.ignore;
  bool validated(HistoricalAnalyticLine line) =>
      (widget.decisions.containsKey(line.sourceRowNumber) ||
          widget.duplicateDecisions[line.sourceRowNumber] ==
              _DuplicateDecision.keep) &&
      !ignored(line);

  bool matches(HistoricalAnalyticLine line, _ReviewFilter value) =>
      switch (value) {
        _ReviewFilter.all => true,
        _ReviewFilter.expenses =>
          current(line) == HistoricalAnalyticClassification.expense,
        _ReviewFilter.positives =>
          current(line) == HistoricalAnalyticClassification.ambiguousPositive,
        _ReviewFilter.duplicates => line.duplicateCandidateKey != null,
        _ReviewFilter.transfers =>
          current(line) == HistoricalAnalyticClassification.internalTransfer,
        _ReviewFilter.adjustments =>
          current(line) == HistoricalAnalyticClassification.technicalAdjustment,
        _ReviewFilter.ignored => ignored(line),
        _ReviewFilter.validated => validated(line),
      };

  bool searched(HistoricalAnalyticLine line) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return line.detail.toLowerCase().contains(q) ||
        line.sourceEnvelopeLabel.toLowerCase().contains(q) ||
        line.mappedEnvelopeLabel.toLowerCase().contains(q) ||
        line.sourceAmount.toStringAsFixed(2).contains(q) ||
        _date(line.occurredOn).contains(q);
  }

  List<HistoricalAnalyticLine> get visible {
    final result = widget.preview.lines
        .where((l) => matches(l, filter) && searched(l))
        .toList();
    int compare(HistoricalAnalyticLine a, HistoricalAnalyticLine b) {
      final value = switch (sort) {
        _ReviewSort.date => a.occurredOn.compareTo(b.occurredOn),
        _ReviewSort.amount => a.sourceAmount.compareTo(b.sourceAmount),
        _ReviewSort.envelope => a.mappedEnvelopeLabel.toLowerCase().compareTo(
          b.mappedEnvelopeLabel.toLowerCase(),
        ),
        _ReviewSort.classification => current(
          a,
        ).name.compareTo(current(b).name),
      };
      if (value != 0) return ascending ? value : -value;
      return a.sourceRowNumber.compareTo(b.sourceRowNumber);
    }

    result.sort(compare);
    return result;
  }

  int count(_ReviewFilter value) =>
      widget.preview.lines.where((l) => matches(l, value)).length;
  Set<int> get decided => {
    ...widget.decisions.keys,
    ...widget.duplicateDecisions.entries
        .where((e) => e.value != _DuplicateDecision.review)
        .map((e) => e.key),
  };
  Set<int> get reviewable => widget.preview.lines
      .where(
        (l) =>
            l.classification ==
            HistoricalAnalyticClassification.ambiguousPositive,
      )
      .map((l) => l.sourceRowNumber)
      .toSet();

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(12),
    child: SafeArea(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Propositions analytiques',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              _Summary(
                preview: widget.preview,
                classification: current,
                ignoredCount: count(_ReviewFilter.ignored),
                decisionsCount: decided.length,
                remainingCount: reviewable.difference(decided).length,
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (_, constraints) => constraints.maxWidth < 700
                    ? DropdownButtonFormField<_ReviewFilter>(
                        key: const Key('history-filter-mobile'),
                        initialValue: filter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Filtrer les propositions',
                          border: OutlineInputBorder(),
                        ),
                        items: _ReviewFilter.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(
                                  '${value.label} (${count(value)})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) setState(() => filter = value);
                        },
                      )
                    : Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: _ReviewFilter.values
                            .map(
                              (value) => FilterChip(
                                key: ValueKey('history-filter-${value.name}'),
                                selected: filter == value,
                                label: Text('${value.label} (${count(value)})'),
                                onSelected: (_) =>
                                    setState(() => filter = value),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (_, c) {
                  final search = TextField(
                    key: const Key('history-search'),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText:
                          'Rechercher : libellé, enveloppe, montant ou date',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  );
                  Widget sorting({required bool expanded}) => Row(
                    mainAxisSize: expanded
                        ? MainAxisSize.max
                        : MainAxisSize.min,
                    children: [
                      if (expanded)
                        Expanded(
                          child: DropdownButton<_ReviewSort>(
                            key: const Key('history-sort'),
                            value: sort,
                            isExpanded: true,
                            items: _ReviewSort.values
                                .map(
                                  (v) => DropdownMenuItem(
                                    value: v,
                                    child: Text('Tri : ${v.label}'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => sort = v);
                            },
                          ),
                        )
                      else
                        DropdownButton<_ReviewSort>(
                          key: const Key('history-sort'),
                          value: sort,
                          items: _ReviewSort.values
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text('Tri : ${v.label}'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => sort = v);
                          },
                        ),
                      IconButton(
                        key: const Key('history-sort-direction'),
                        onPressed: () => setState(() => ascending = !ascending),
                        icon: Icon(
                          ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        ),
                      ),
                    ],
                  );
                  return c.maxWidth < 700
                      ? Column(
                          children: [
                            search,
                            const SizedBox(height: 6),
                            sorting(expanded: true),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: search),
                            const SizedBox(width: 14),
                            sorting(expanded: false),
                          ],
                        );
                },
              ),
              const SizedBox(height: 10),
              Expanded(child: results()),
            ],
          ),
        ),
      ),
    ),
  );

  Widget results() {
    final lines = visible;
    if (lines.isEmpty) {
      return const Center(child: Text('Aucune ligne pour ces critères.'));
    }
    if (filter == _ReviewFilter.duplicates) {
      final groups = <String, List<HistoricalAnalyticLine>>{};
      for (final line in lines) {
        groups.putIfAbsent(line.duplicateCandidateKey!, () => []).add(line);
      }
      final entries = groups.entries.toList()
        ..sort(
          (a, b) => a.value.first.sourceRowNumber.compareTo(
            b.value.first.sourceRowNumber,
          ),
        );
      return ListView.builder(
        key: const Key('history-results-duplicates'),
        itemCount: entries.length,
        itemBuilder: (_, i) => _DuplicateGroup(
          index: i,
          lines: entries[i].value,
          decisions: widget.duplicateDecisions,
          onChanged: (row, value) {
            setState(() => widget.duplicateDecisions[row] = value);
            widget.onDecision();
          },
        ),
      );
    }
    return LayoutBuilder(
      builder: (_, c) => ListView.builder(
        key: const Key('history-results-lines'),
        itemCount: lines.length,
        itemBuilder: (_, i) => _LineRow(
          line: lines[i],
          compact: c.maxWidth < 700,
          classification: current(lines[i]),
          onChanged: (value) {
            setState(() => widget.decisions[lines[i].sourceRowNumber] = value);
            widget.onDecision();
          },
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.preview,
    required this.classification,
    required this.ignoredCount,
    required this.decisionsCount,
    required this.remainingCount,
  });
  final HistoricalAnalyticsPreview preview;
  final HistoricalAnalyticClassification Function(HistoricalAnalyticLine)
  classification;
  final int ignoredCount, decisionsCount, remainingCount;

  @override
  Widget build(BuildContext context) {
    final expenses = preview.lines
        .where(
          (l) => classification(l) == HistoricalAnalyticClassification.expense,
        )
        .toList();
    final amount = expenses.fold<double>(
      0,
      (sum, l) => sum + l.analyticalAmount,
    );
    int n(HistoricalAnalyticClassification c) =>
        preview.lines.where((l) => classification(l) == c).length;
    String groups(HistoricalAnalyticRepetition repetition) {
      final count = preview.repetitionGroupCount(repetition);
      return '$count groupe${count > 1 ? 's' : ''}';
    }

    return Container(
      key: const Key('history-dynamic-summary'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Text('Total lignes : ${preview.lines.length}'),
            const SizedBox(width: 14),
            Text('Dépenses proposées : ${expenses.length}'),
            const SizedBox(width: 14),
            Text('Montant dépenses : ${amount.toStringAsFixed(2)} MAD'),
            const SizedBox(width: 14),
            Text(
              'Positifs non décidés : ${n(HistoricalAnalyticClassification.ambiguousPositive)}',
            ),
            const SizedBox(width: 14),
            Text(
              'Répétitions source strictes : '
              '${groups(HistoricalAnalyticRepetition.strictSource)} / '
              '${preview.repetitionLineCount(HistoricalAnalyticRepetition.strictSource)} lignes',
            ),
            const SizedBox(width: 14),
            Text(
              'Ressemblances métier : '
              '${groups(HistoricalAnalyticRepetition.businessSimilarity)} / '
              '${preview.repetitionLineCount(HistoricalAnalyticRepetition.businessSimilarity)} lignes',
            ),
            const SizedBox(width: 14),
            Text(
              'Transferts internes : ${n(HistoricalAnalyticClassification.internalTransfer)}',
            ),
            const SizedBox(width: 14),
            Text(
              'Ajustements techniques : ${n(HistoricalAnalyticClassification.technicalAdjustment)}',
            ),
            const SizedBox(width: 14),
            Text('Ignorés : $ignoredCount'),
            const SizedBox(width: 14),
            Text('Décisions humaines effectuées : $decisionsCount'),
            const SizedBox(width: 14),
            Text('Restant à examiner : $remainingCount'),
          ],
        ),
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.compact,
    required this.classification,
    required this.onChanged,
  });
  final HistoricalAnalyticLine line;
  final bool compact;
  final HistoricalAnalyticClassification classification;
  final ValueChanged<HistoricalAnalyticClassification> onChanged;

  @override
  Widget build(BuildContext context) {
    final selector = DropdownButton<HistoricalAnalyticClassification>(
      key: ValueKey('history-decision-${line.sourceRowNumber}'),
      value: classification,
      isExpanded: true,
      items: HistoricalAnalyticClassification.values
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(v.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
    final detail =
        '${_date(line.occurredOn)} · ${line.mappedEnvelopeLabel} · '
        '${line.sourceAmount.toStringAsFixed(2)} MAD · ${line.detail} · Ligne ${line.sourceRowNumber}';
    if (compact) {
      return Card(
        key: ValueKey('historical-line-${line.sourceRowNumber}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(detail), const SizedBox(height: 6), selector],
          ),
        ),
      );
    }
    return Container(
      key: ValueKey('historical-line-${line.sourceRowNumber}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x1F000000))),
      ),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(_date(line.occurredOn))),
          Expanded(flex: 2, child: Text(line.mappedEnvelopeLabel)),
          SizedBox(
            width: 105,
            child: Text('${line.sourceAmount.toStringAsFixed(2)} MAD'),
          ),
          Expanded(
            flex: 3,
            child: Text(line.detail, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(width: 80, child: Text('Ligne ${line.sourceRowNumber}')),
          SizedBox(width: 240, child: selector),
        ],
      ),
    );
  }
}

class _DuplicateGroup extends StatelessWidget {
  const _DuplicateGroup({
    required this.index,
    required this.lines,
    required this.decisions,
    required this.onChanged,
  });
  final int index;
  final List<HistoricalAnalyticLine> lines;
  final Map<int, _DuplicateDecision> decisions;
  final void Function(int, _DuplicateDecision) onChanged;

  @override
  Widget build(BuildContext context) => Card(
    key: ValueKey('duplicate-group-$index'),
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_repetitionLabel(lines.first.repetition)} — '
            'groupe ${index + 1} — ${lines.length} occurrences conservées',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 4,
                children: [
                  Text(_date(line.occurredOn)),
                  Text(line.mappedEnvelopeLabel),
                  Text('${line.sourceAmount.toStringAsFixed(2)} MAD'),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(line.detail),
                  ),
                  Text('Ligne ${line.sourceRowNumber}'),
                  SizedBox(
                    width: 220,
                    child: DropdownButton<_DuplicateDecision>(
                      key: ValueKey(
                        'duplicate-decision-${line.sourceRowNumber}',
                      ),
                      value:
                          decisions[line.sourceRowNumber] ??
                          _DuplicateDecision.keep,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(
                          value: _DuplicateDecision.keep,
                          child: Text('Conserver'),
                        ),
                        DropdownMenuItem(
                          value: _DuplicateDecision.ignore,
                          child: Text('Ignorer comme saisie dupliquée'),
                        ),
                        DropdownMenuItem(
                          value: _DuplicateDecision.review,
                          child: Text('À revoir'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) onChanged(line.sourceRowNumber, v);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/'
    '${value.month.toString().padLeft(2, '0')}/${value.year}';

String _repetitionLabel(HistoricalAnalyticRepetition? value) => switch (value) {
  HistoricalAnalyticRepetition.strictSource => 'Répétition source stricte',
  HistoricalAnalyticRepetition.businessSimilarity => 'Ressemblance métier',
  null => 'Répétition à contrôler',
};
