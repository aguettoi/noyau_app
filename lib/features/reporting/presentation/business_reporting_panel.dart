import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/kpi_reporting_locale.dart';
import '../../../core/money/money.dart';
import '../../monthly_close/domain/monthly_close.dart';
import '../application/reporting_provider.dart';
import '../domain/business_reporting.dart';

class BusinessReportingPanel extends ConsumerWidget {
  const BusinessReportingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = KpiReportingWords.of(context);
    final month = ref.watch(selectedReportingMonthProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                tooltip: words.text('report.previous_month'),
                onPressed: () =>
                    ref.read(selectedReportingMonthProvider.notifier).state =
                        DateTime(month.year, month.month - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _monthLabel(words, month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: words.text('report.next_month'),
                onPressed: () =>
                    ref.read(selectedReportingMonthProvider.notifier).state =
                        DateTime(month.year, month.month + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: ref
              .watch(reportingDataProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(words.text('report.unavailable')),
                  ),
                ),
                data: (data) => RefreshIndicator(
                  onRefresh: () => ref.refresh(reportingDataProvider.future),
                  child: ListView(
                    key: const Key('business-reporting-list'),
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    children: [
                      _ReportCard(report: data.report),
                      const SizedBox(height: 12),
                      Text(
                        words.text('report.timeline_title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(words.text('report.timeline_description')),
                      const SizedBox(height: 8),
                      if (data.timeline.isEmpty)
                        Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(words.text('report.timeline_empty')),
                          ),
                        )
                      else
                        for (final fact in data.timeline)
                          _TimelineTile(fact: fact, words: words),
                    ],
                  ),
                ),
              ),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});
  final BusinessPeriodReport report;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            KpiReportingWords.of(context).text('report.title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(
            report.isPartial
                ? KpiReportingWords.of(context).text('report.partial')
                : KpiReportingWords.of(context).format('report.close_status', {
                    'status': _closeStatusLabel(
                      KpiReportingWords.of(context),
                      report.closeStatus,
                    ),
                  }),
          ),
          const Divider(),
          if (report.categories.isEmpty)
            Text(KpiReportingWords.of(context).text('report.empty'))
          else
            for (final category in report.categories)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(category.label),
                subtitle: Text(
                  KpiReportingWords.of(
                    context,
                  ).format('report.category_summary', {
                    'count': category.count,
                    'status': _statusLabel(
                      KpiReportingWords.of(context),
                      category.status,
                    ),
                  }),
                ),
                trailing: Text(_money(category.total)),
              ),
          const Divider(),
          for (final explanation in report.explanations)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                KpiReportingWords.of(
                  context,
                ).format('report.explanation', {'explanation': explanation}),
              ),
            ),
        ],
      ),
    ),
  );
}

class _TimelineTile extends ConsumerWidget {
  const _TimelineTile({required this.fact, required this.words});
  final TimelineFact fact;
  final KpiReportingWords words;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: Text(fact.title),
      subtitle: Text(
        words.format('report.fact_detail', {
          'date': _date(fact.date),
          'status': _statusLabel(words, fact.status),
          'source': _sourceLabel(words, fact.source),
          'reason': fact.reason,
        }),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (fact.amount case final Money amount) Text(_money(amount)),
          if (fact.canToggleMark)
            IconButton(
              key: ValueKey('timeline-mark-${fact.identity}'),
              tooltip: fact.manuallyMarked
                  ? words.text('report.unmark')
                  : words.text('report.mark'),
              onPressed: () async {
                try {
                  await ref
                      .read(timelineMarkActionProvider)
                      .setMarked(fact, !fact.manuallyMarked);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(words.text('report.action_failed')),
                      ),
                    );
                  }
                }
              },
              icon: Icon(fact.manuallyMarked ? Icons.star : Icons.star_border),
            ),
        ],
      ),
    ),
  );
}

String _statusLabel(KpiReportingWords words, ReportFactStatus status) =>
    switch (status) {
      ReportFactStatus.observed => words.text('report.status.observed'),
      ReportFactStatus.expected => words.text('report.status.expected'),
      ReportFactStatus.projected => words.text('report.status.projected'),
      ReportFactStatus.imported => words.text('report.status.imported'),
    };

String _closeStatusLabel(KpiReportingWords words, MonthlyCloseStatus status) =>
    words.text('report.close.${status.name}');

String _sourceLabel(KpiReportingWords words, ReportFactSource source) =>
    switch (source) {
      ReportFactSource.financialEvent => words.text(
        'report.source.financial_event',
      ),
      ReportFactSource.monthlyClose => words.text(
        'report.source.monthly_close',
      ),
      ReportFactSource.obligation => words.text('report.source.obligation'),
      ReportFactSource.financing => words.text('report.source.financing'),
      ReportFactSource.importedHistory => words.text(
        'report.source.imported_history',
      ),
    };

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _money(Money value) => '${value.dirhams.toStringAsFixed(2)} MAD';

String _monthLabel(KpiReportingWords words, DateTime value) =>
    '${words.text('month.${value.month}')} ${value.year}';
