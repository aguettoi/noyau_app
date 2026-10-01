import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';
import 'package:noyau_app/features/finance/presentation/historical_analytics_preview_card.dart';

void main() {
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
          SourceCellSnapshot(coordinate: 'B4', value: '2026-05-04'),
          SourceCellSnapshot(coordinate: 'C4', value: 'Navette'),
          SourceCellSnapshot(coordinate: 'D4', value: '-5'),
          SourceCellSnapshot(coordinate: 'E4', value: 'Grand taxi'),
          SourceCellSnapshot(coordinate: 'B5', value: '2026-05-04'),
          SourceCellSnapshot(coordinate: 'C5', value: 'Navette'),
          SourceCellSnapshot(coordinate: 'D5', value: '-5'),
          SourceCellSnapshot(coordinate: 'E5', value: 'Grand taxi'),
          SourceCellSnapshot(coordinate: 'B6', value: '2026-05-06'),
          SourceCellSnapshot(coordinate: 'C6', value: 'Divers'),
          SourceCellSnapshot(coordinate: 'D6', value: '40'),
          SourceCellSnapshot(coordinate: 'E6', value: 'Positif à qualifier'),
          SourceCellSnapshot(coordinate: 'B7', value: '2026-05-07'),
          SourceCellSnapshot(coordinate: 'C7', value: 'Compte A'),
          SourceCellSnapshot(coordinate: 'D7', value: '-20'),
          SourceCellSnapshot(coordinate: 'E7', value: 'Transfert interne'),
          SourceCellSnapshot(coordinate: 'B8', value: '2026-05-07'),
          SourceCellSnapshot(coordinate: 'C8', value: 'Compte B'),
          SourceCellSnapshot(coordinate: 'D8', value: '20'),
          SourceCellSnapshot(coordinate: 'E8', value: 'Transfert interne'),
          SourceCellSnapshot(coordinate: 'B9', value: '2026-09-29'),
          SourceCellSnapshot(coordinate: 'C9', value: 'Traite maison'),
          SourceCellSnapshot(coordinate: 'D9', value: '59630'),
          SourceCellSnapshot(coordinate: 'E9', value: 'Syndic et notaire'),
        ],
      ),
    ],
  );

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1100, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HistoricalAnalyticsPreviewCard(analysis: analysis),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('historical-analytics-review')));
    await tester.pumpAndSettle();
  }

  testWidgets('filters, searches, sorts and groups duplicate occurrences', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Propositions analytiques'), findsOneWidget);
    expect(find.text('Total lignes : 7'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-filter-adjustments')));
    await tester.pumpAndSettle();
    expect(find.textContaining('59630.00 MAD'), findsOneWidget);
    expect(find.textContaining('Syndic et notaire'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-filter-duplicates')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('duplicate-group-0')), findsOneWidget);
    expect(find.text('Groupe 1 — 2 occurrences à comparer'), findsOneWidget);
    expect(find.text('Ligne 4'), findsOneWidget);
    expect(find.text('Ligne 5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-filter-positives')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Positif à qualifier'), findsOneWidget);
    expect(find.textContaining('Grand taxi'), findsNothing);

    await tester.enterText(find.byKey(const Key('history-search')), '40.00');
    await tester.pump();
    expect(find.textContaining('Positif à qualifier'), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-sort-direction')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps local decisions across filters and creates no write action',
    (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('history-filter-positives')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history-decision-6')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revenu validé').last);
      await tester.pumpAndSettle();
      expect(find.text('Décisions humaines effectuées : 1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('history-filter-expenses')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history-filter-validated')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historical-line-6')), findsOneWidget);
      expect(find.text('Revenu validé'), findsOneWidget);
      expect(find.textContaining('Importer'), findsNothing);
      expect(find.textContaining('Matérialiser'), findsNothing);
    },
  );

  testWidgets(
    'duplicate decision survives navigation and mobile has no overflow',
    (tester) async {
      await open(tester, size: const Size(390, 720));
      await tester.tap(find.byKey(const Key('history-filter-mobile')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Doublons potentiels').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('duplicate-decision-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conserver').last);
      await tester.pumpAndSettle();
      expect(find.text('Doublons potentiels non décidés : 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('history-filter-mobile')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Toutes (').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('history-filter-mobile')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Doublons potentiels').last);
      await tester.pumpAndSettle();
      expect(find.text('Conserver'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
