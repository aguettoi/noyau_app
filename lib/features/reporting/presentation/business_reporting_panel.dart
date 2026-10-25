import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../application/reporting_provider.dart';
import '../domain/business_reporting.dart';

class BusinessReportingPanel extends ConsumerWidget {
  const BusinessReportingPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedReportingMonthProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Mois précédent',
                onPressed: () =>
                    ref.read(selectedReportingMonthProvider.notifier).state =
                        DateTime(month.year, month.month - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  _monthLabel(month),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Mois suivant',
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
                    child: Text('Rapport indisponible : $error'),
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
                        'Timeline significative',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Une sélection explicable, distincte de l’historique exhaustif.',
                      ),
                      const SizedBox(height: 8),
                      if (data.timeline.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Aucun fait significatif visible sur cette période.',
                            ),
                          ),
                        )
                      else
                        for (final fact in data.timeline)
                          _TimelineTile(fact: fact),
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
          Text('Rapport métier', style: Theme.of(context).textTheme.titleLarge),
          Text(
            report.isPartial
                ? 'Données disponibles — période sans snapshot figé'
                : 'Clôture : ${report.closeStatus.name}',
          ),
          const Divider(),
          if (report.categories.isEmpty)
            const Text('Aucun fait financier visible sur cette période.')
          else
            for (final category in report.categories)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(category.label),
                subtitle: Text(
                  '${category.count} fait(s) • ${_statusLabel(category.status)}',
                ),
                trailing: Text(_money(category.total)),
              ),
          const Divider(),
          for (final explanation in report.explanations)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $explanation'),
            ),
        ],
      ),
    ),
  );
}

class _TimelineTile extends ConsumerWidget {
  const _TimelineTile({required this.fact});
  final TimelineFact fact;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: Text(fact.title),
      subtitle: Text(
        '${_date(fact.date)} • ${_statusLabel(fact.status)} • ${_sourceLabel(fact.source)}\n${fact.reason}',
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
                  ? 'Retirer des faits significatifs'
                  : 'Marquer comme significatif',
              onPressed: () async {
                try {
                  await ref
                      .read(timelineMarkActionProvider)
                      .setMarked(fact, !fact.manuallyMarked);
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Action impossible : $error')),
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

String _statusLabel(ReportFactStatus status) => switch (status) {
  ReportFactStatus.observed => 'Réalisé',
  ReportFactStatus.expected => 'Attendu',
  ReportFactStatus.projected => 'Projeté',
  ReportFactStatus.imported => 'Historique importé',
};

String _sourceLabel(ReportFactSource source) => switch (source) {
  ReportFactSource.financialEvent => 'Événement financier',
  ReportFactSource.monthlyClose => 'Clôture',
  ReportFactSource.obligation => 'Obligation',
  ReportFactSource.financing => 'Financement',
  ReportFactSource.importedHistory => 'Historique importé',
};

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _money(Money value) => '${value.dirhams.toStringAsFixed(2)} MAD';

String _monthLabel(DateTime value) {
  const months = [
    'Janvier',
    'Février',
    'Mars',
    'Avril',
    'Mai',
    'Juin',
    'Juillet',
    'Août',
    'Septembre',
    'Octobre',
    'Novembre',
    'Décembre',
  ];
  return '${months[value.month - 1]} ${value.year}';
}
