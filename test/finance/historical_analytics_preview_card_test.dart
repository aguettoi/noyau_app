import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';
import 'package:noyau_app/features/finance/presentation/historical_analytics_preview_card.dart';

void main() {
  testWidgets('preview is local and permits an explicit review decision', (
    tester,
  ) async {
    const analysis = WorkbookImportAnalysis(
      fileName: 'source.xlsx',
      sourceFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      sheetPreviews: [],
      unhandledSheetNames: [],
      sourceSheets: [
        SourceSheetSnapshot(
          sourceSheetName: 'Journal',
          cells: [
            SourceCellSnapshot(coordinate: 'B3', value: '2026-05-01'),
            SourceCellSnapshot(coordinate: 'C3', value: 'Courses'),
            SourceCellSnapshot(coordinate: 'D3', value: '-100'),
            SourceCellSnapshot(coordinate: 'E3', value: 'Marché'),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HistoricalAnalyticsPreviewCard(analysis: analysis),
        ),
      ),
    );
    expect(find.text('Historique analytique — aperçu local'), findsOneWidget);
    expect(find.textContaining('Aucune écriture financière'), findsOneWidget);
    await tester.tap(find.byKey(const Key('historical-analytics-review')));
    await tester.pumpAndSettle();
    expect(find.text('Propositions analytiques'), findsOneWidget);
    expect(find.textContaining('100.00 MAD'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Propositions analytiques'), findsNothing);
  });
}
