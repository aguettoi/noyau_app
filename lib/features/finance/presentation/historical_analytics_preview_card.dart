import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/historical_analytics_locale.dart';

import '../application/cutover_opening_import.dart';
import '../application/historical_analytic_materialization.dart';
import '../application/historical_analytics.dart';
import '../application/providers/historical_analytics_provider.dart';
import '../application/workbook_import.dart';

enum _ReviewFilter {
  all,
  expenses,
  positives,
  duplicates,
  transfers,
  adjustments,
  ignored,
  validated,
}

enum _ReviewSort { date, amount, envelope, classification }

enum _DuplicateDecision { keep, ignore, review }

class HistoricalAnalyticsPreviewCard extends ConsumerStatefulWidget {
  const HistoricalAnalyticsPreviewCard({super.key, required this.analysis});
  final WorkbookImportAnalysis analysis;

  @override
  ConsumerState<HistoricalAnalyticsPreviewCard> createState() =>
      _HistoricalAnalyticsPreviewCardState();
}

class _HistoricalAnalyticsPreviewCardState
    extends ConsumerState<HistoricalAnalyticsPreviewCard> {
  static const _expectedBackupSha =
      'a98806810967481921508df92138ab58e6e1b02cde5e40f390c08ec5b0519663';
  static const _expectedSourceSha =
      'f3cbc99e335586d5628791017e5fd8119430a03d32674ba1d11f284157c8f8bc';
  static const _realHouseholdId = '51cfd7c6-8edc-4c42-94db-1be78289fe81';
  late final HistoricalAnalyticsPreview preview =
      const HistoricalAnalyticsPreviewBuilder().build(widget.analysis);
  final Map<int, HistoricalAnalyticClassification> localDecisions = {};
  final Map<int, _DuplicateDecision> duplicateDecisions = {};
  HistoricalAnalyticMaterializationPlan? _materializationPlan;
  String? _materializationError;
  String? _materializationResult;
  String? _selectedHouseholdId;
  bool _materializing = false;

  @override
  Widget build(BuildContext context) {
    final w = HistoricalAnalyticsWords.of(context);
    final households = ref.watch(cutoverEligibleHouseholdsProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              w.text('title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              w.format('intro', {
                'start': _date(context, preview.periodStart),
                'end': _date(context, preview.periodEnd),
              }),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Text(w.format('retained', {'count': preview.lines.length})),
                Text(
                  w.format('expenses', {
                    'count': preview.count(
                      HistoricalAnalyticClassification.expense,
                    ),
                  }),
                ),
                Text(
                  w.format('positives', {
                    'count': preview.lines
                        .where(
                          (line) =>
                              (localDecisions[line.sourceRowNumber] ??
                                  line.classification) ==
                              HistoricalAnalyticClassification
                                  .ambiguousPositive,
                        )
                        .length,
                  }),
                ),
                Text(
                  w.format('duplicates', {
                    'count': preview.duplicateCandidates,
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('historical-analytics-review'),
              onPressed: preview.lines.isEmpty ? null : _openReview,
              icon: const Icon(Icons.manage_search),
              label: Text(w.text('review')),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              w.text('materialization'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(w.text('materialization_intro')),
            const SizedBox(height: 10),
            households.when(
              data: (items) => DropdownButtonFormField<String>(
                key: const Key('historical-materialization-household'),
                initialValue: _selectedHouseholdId,
                decoration: InputDecoration(
                  labelText: w.text('target_household'),
                  border: const OutlineInputBorder(),
                ),
                items: items
                    .where((item) => item.isOperational)
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          // i18n-dynamic-only
                          '${item.name} — ${w.text('operational')}',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() {
                  _selectedHouseholdId = value;
                  _materializationPlan = null;
                  _materializationResult = null;
                }),
              ),
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => Text(w.text('households_unavailable')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('load-historical-decisions'),
              onPressed: _selectedHouseholdId == null ? null : _loadBackup,
              icon: const Icon(Icons.restore_page_outlined),
              label: Text(w.text('load_decisions')),
            ),
            if (_materializationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _materializationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_materializationPlan case final plan?) ...[
              const SizedBox(height: 12),
              Text(w.format('source', {'source': widget.analysis.fileName})),
              SelectableText(w.format('sha', {'sha': plan.sourceFingerprint})),
              Text(
                w.format('period', {
                  'start': _date(context, preview.periodStart),
                  'end': _date(context, preview.periodEnd),
                }),
              ),
              Text(
                w.format('plan_counts', {
                  'lines': plan.lines.length,
                  'decisions': plan.decisions.length,
                }),
              ),
              Text(
                w.format('breakdown', {
                  'expenses': plan.count(
                    HistoricalAnalyticClassification.expense,
                  ),
                  'income': plan.count(
                    HistoricalAnalyticClassification.validatedIncome,
                  ),
                  'transfers': plan.count(
                    HistoricalAnalyticClassification.internalTransfer,
                  ),
                  'adjustments': plan.count(
                    HistoricalAnalyticClassification.technicalAdjustment,
                  ),
                  'funding': plan.count(
                    HistoricalAnalyticClassification.budgetFunding,
                  ),
                }),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const Key('materialize-historical-analytics'),
                onPressed: _materializing
                    ? null
                    : () => _confirmMaterialization(plan),
                icon: const Icon(Icons.publish_outlined),
                label: Text(w.text('materialize')),
              ),
            ],
            if (_materializationResult != null) ...[
              const SizedBox(height: 8),
              Text(_materializationResult!),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadBackup() async {
    try {
      final bytes = await ref.read(historicalDecisionFilePickerProvider)();
      if (bytes == null || !mounted) return;
      _restoreBackup(bytes);
    } catch (_) {
      if (mounted) {
        setState(
          () => _materializationError = HistoricalAnalyticsWords.of(
            context,
          ).text('backup_error'),
        );
      }
    }
  }

  void _restoreBackup(Uint8List bytes) {
    final target = _selectedHouseholdId;
    if (target == null || target != _realHouseholdId) {
      throw FormatException(
        HistoricalAnalyticsWords.of(
          context,
        ).text('certified_household_required'),
      );
    }
    if (widget.analysis.sourceFingerprint != _expectedSourceSha) {
      throw FormatException(
        HistoricalAnalyticsWords.of(context).text('source_mismatch'),
      );
    }
    final backup = HistoricalAnalyticDecisionBackup.decodeStrict(
      bytes,
      expectedSha256: _expectedBackupSha,
      expectedSourceFingerprint: _expectedSourceSha,
      expectedHouseholdId: _realHouseholdId,
    );
    final plan = HistoricalAnalyticMaterializationPlan.restore(
      preview: preview,
      backup: backup,
      sourceFingerprint: widget.analysis.sourceFingerprint,
      householdId: target,
    );
    setState(() {
      _materializationPlan = plan;
      duplicateDecisions.clear();
      localDecisions
        ..clear()
        ..addEntries(
          backup.decisions.map(
            (decision) => MapEntry(
              decision.sourceRowNumber,
              decision.finalClassification,
            ),
          ),
        );
      _materializationError = null;
      _materializationResult = null;
    });
  }

  Future<void> _confirmMaterialization(
    HistoricalAnalyticMaterializationPlan plan,
  ) async {
    final w = HistoricalAnalyticsWords.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(w.text('confirm_title')),
        content: Text(w.text('confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(w.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(w.text('confirm')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _materializing = true);
    try {
      final result = await ref
          .read(historicalAnalyticsGatewayProvider)
          .materialize(plan);
      if (mounted) {
        setState(() {
          _materializationResult = result['replayed'] == true
              ? w.text('replayed')
              : w.format('inserted', {
                  'lines': result['inserted_lines']!,
                  'decisions': result['inserted_decisions']!,
                });
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _materializationError = w.text('materialization_error'));
      }
    } finally {
      if (mounted) setState(() => _materializing = false);
    }
  }

  Future<void> _openReview() => showDialog<void>(
    context: context,
    builder: (_) => _ReviewDialog(
      preview: preview,
      decisions: localDecisions,
      duplicateDecisions: duplicateDecisions,
      onDecision: () => setState(() {
        _materializationPlan = null;
        _materializationResult = null;
      }),
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
        _searchDate(line.occurredOn).contains(q);
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
  Widget build(BuildContext context) {
    final w = HistoricalAnalyticsWords.of(context);
    return Dialog(
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
                        w.text('proposals'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: w.text('close'),
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
                          decoration: InputDecoration(
                            labelText: w.text('filter'),
                            border: const OutlineInputBorder(),
                          ),
                          items: _ReviewFilter.values
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    w.format('filter_count', {
                                      'label': _filterLabel(w, value),
                                      'count': count(value),
                                    }),
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
                                  label: Text(
                                    w.format('filter_count', {
                                      'label': _filterLabel(w, value),
                                      'count': count(value),
                                    }),
                                  ),
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
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: w.text('search'),
                        border: const OutlineInputBorder(),
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
                                      child: Text(
                                        w.format('sort', {
                                          'label': _sortLabel(w, v),
                                        }),
                                      ),
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
                                    child: Text(
                                      w.format('sort', {
                                        'label': _sortLabel(w, v),
                                      }),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => sort = v);
                            },
                          ),
                        IconButton(
                          key: const Key('history-sort-direction'),
                          onPressed: () =>
                              setState(() => ascending = !ascending),
                          icon: Icon(
                            ascending
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
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
                Expanded(child: results(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget results(BuildContext context) {
    final w = HistoricalAnalyticsWords.of(context);
    final lines = visible;
    if (lines.isEmpty) {
      return Center(child: Text(w.text('empty')));
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
    final w = HistoricalAnalyticsWords.of(context);
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
      return w.format(count == 1 ? 'groups_one' : 'groups_many', {
        'count': count,
      });
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
            Text(w.format('total_lines', {'count': preview.lines.length})),
            const SizedBox(width: 14),
            Text(w.format('proposed_expenses', {'count': expenses.length})),
            const SizedBox(width: 14),
            Text(
              w.format('expense_amount', {'amount': _money(context, amount)}),
            ),
            const SizedBox(width: 14),
            Text(
              w.format('undecided_positives', {
                'count': n(HistoricalAnalyticClassification.ambiguousPositive),
              }),
            ),
            const SizedBox(width: 14),
            Text(
              w.format('strict_repetitions', {
                'groups': groups(HistoricalAnalyticRepetition.strictSource),
                'lines': preview.repetitionLineCount(
                  HistoricalAnalyticRepetition.strictSource,
                ),
              }),
            ),
            const SizedBox(width: 14),
            Text(
              w.format('business_similarities', {
                'groups': groups(
                  HistoricalAnalyticRepetition.businessSimilarity,
                ),
                'lines': preview.repetitionLineCount(
                  HistoricalAnalyticRepetition.businessSimilarity,
                ),
              }),
            ),
            const SizedBox(width: 14),
            Text(
              w.format('internal_transfers', {
                'count': n(HistoricalAnalyticClassification.internalTransfer),
              }),
            ),
            const SizedBox(width: 14),
            Text(
              w.format('technical_adjustments', {
                'count': n(
                  HistoricalAnalyticClassification.technicalAdjustment,
                ),
              }),
            ),
            const SizedBox(width: 14),
            Text(w.format('ignored', {'count': ignoredCount})),
            const SizedBox(width: 14),
            Text(w.format('human_decisions', {'count': decisionsCount})),
            const SizedBox(width: 14),
            Text(w.format('remaining', {'count': remainingCount})),
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
    final w = HistoricalAnalyticsWords.of(context);
    final selector = DropdownButton<HistoricalAnalyticClassification>(
      key: ValueKey('history-decision-${line.sourceRowNumber}'),
      value: classification,
      isExpanded: true,
      items: HistoricalAnalyticClassification.values
          .map(
            (v) => DropdownMenuItem(
              value: v,
              child: Text(
                _classificationLabel(w, v),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
    final detail = w.format('detail', {
      'date': _date(context, line.occurredOn),
      'envelope': line.mappedEnvelopeLabel,
      'amount': _money(context, line.sourceAmount),
      'detail': line.detail,
      'line': line.sourceRowNumber,
    });
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
          SizedBox(width: 90, child: Text(_date(context, line.occurredOn))),
          Expanded(flex: 2, child: Text(line.mappedEnvelopeLabel)),
          SizedBox(width: 105, child: Text(_money(context, line.sourceAmount))),
          Expanded(
            flex: 3,
            child: Text(line.detail, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 80,
            child: Text(w.format('line', {'number': line.sourceRowNumber})),
          ),
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
  Widget build(BuildContext context) {
    final w = HistoricalAnalyticsWords.of(context);
    return Card(
      key: ValueKey('duplicate-group-$index'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              w.format('duplicate_group', {
                'repetition': _repetitionLabel(w, lines.first.repetition),
                'group': index + 1,
                'count': lines.length,
              }),
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
                    Text(_date(context, line.occurredOn)),
                    Text(line.mappedEnvelopeLabel),
                    Text(_money(context, line.sourceAmount)),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(line.detail),
                    ),
                    Text(w.format('line', {'number': line.sourceRowNumber})),
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
                        items: [
                          DropdownMenuItem(
                            value: _DuplicateDecision.keep,
                            child: Text(w.text('keep')),
                          ),
                          DropdownMenuItem(
                            value: _DuplicateDecision.ignore,
                            child: Text(w.text('ignore_duplicate')),
                          ),
                          DropdownMenuItem(
                            value: _DuplicateDecision.review,
                            child: Text(w.text('to_review')),
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
}

String _date(BuildContext context, DateTime value) => DateFormat.yMd(
  Localizations.localeOf(context).toLanguageTag(),
).format(value);

String _searchDate(DateTime value) => value.toIso8601String().substring(0, 10);

String _money(BuildContext context, num value) => NumberFormat.currency(
  locale: Localizations.localeOf(context).toLanguageTag(),
  symbol: 'MAD',
  decimalDigits: 2,
).format(value);

String _repetitionLabel(
  HistoricalAnalyticsWords w,
  HistoricalAnalyticRepetition? value,
) => switch (value) {
  HistoricalAnalyticRepetition.strictSource => w.text('repetition_strict'),
  HistoricalAnalyticRepetition.businessSimilarity => w.text(
    'repetition_business',
  ),
  null => w.text('repetition_review'),
};

String _filterLabel(HistoricalAnalyticsWords w, _ReviewFilter value) =>
    w.text('filter_${value.name}');

String _sortLabel(HistoricalAnalyticsWords w, _ReviewSort value) =>
    w.text('sort_${value.name}');

String _classificationLabel(
  HistoricalAnalyticsWords w,
  HistoricalAnalyticClassification value,
) => switch (value) {
  HistoricalAnalyticClassification.expense => w.text('class_expense'),
  HistoricalAnalyticClassification.budgetFunding => w.text(
    'class_budget_funding',
  ),
  HistoricalAnalyticClassification.internalTransfer => w.text(
    'class_internal_transfer',
  ),
  HistoricalAnalyticClassification.ambiguousPositive => w.text(
    'class_ambiguous_positive',
  ),
  HistoricalAnalyticClassification.technicalAdjustment => w.text(
    'class_technical_adjustment',
  ),
  HistoricalAnalyticClassification.ignored => w.text('class_ignored'),
  HistoricalAnalyticClassification.validatedIncome => w.text(
    'class_validated_income',
  ),
};
