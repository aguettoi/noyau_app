import 'package:flutter/material.dart';

import '../application/historical_analytics.dart';
import '../application/workbook_import.dart';

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

  @override
  Widget build(BuildContext context) {
    final expense = preview.count(HistoricalAnalyticClassification.expense);
    final ambiguous = preview.count(
      HistoricalAnalyticClassification.ambiguousPositive,
    );
    return Card(
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
                Text('$expense dépenses analytiques'),
                Text('$ambiguous positifs à valider'),
                Text('${preview.duplicateCandidates} candidats doublons'),
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
  }

  Future<void> _openReview() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Propositions analytiques'),
      content: SizedBox(
        width: 900,
        height: 560,
        child: ListView.builder(
          itemCount: preview.lines.length,
          itemBuilder: (context, index) {
            final line = preview.lines[index];
            final selected =
                localDecisions[line.sourceRowNumber] ?? line.classification;
            return ListTile(
              key: ValueKey('historical-line-${line.sourceRowNumber}'),
              title: Text(
                '${line.occurredOn.day.toString().padLeft(2, '0')}/'
                '${line.occurredOn.month.toString().padLeft(2, '0')}/'
                '${line.occurredOn.year} — ${line.mappedEnvelopeLabel}',
              ),
              subtitle: Text(
                '${line.sourceAmount.toStringAsFixed(2)} MAD · ${line.detail}'
                '${line.duplicateCandidateKey == null ? '' : ' · doublon potentiel'}',
              ),
              trailing: DropdownButton<HistoricalAnalyticClassification>(
                value: selected,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => localDecisions[line.sourceRowNumber] = value);
                  Navigator.of(context).pop();
                  _openReview();
                },
                items: HistoricalAnalyticClassification.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(growable: false),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    ),
  );
}
