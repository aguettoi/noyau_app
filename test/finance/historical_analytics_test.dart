import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/historical_analytics.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';

void main() {
  WorkbookImportAnalysis analysis(List<List<String>> rows) {
    final cells = <SourceCellSnapshot>[];
    const columns = ['B', 'C', 'D', 'E'];
    for (var index = 0; index < rows.length; index++) {
      for (var column = 0; column < columns.length; column++) {
        cells.add(
          SourceCellSnapshot(
            coordinate: '${columns[column]}${index + 2}',
            value: rows[index][column],
          ),
        );
      }
    }
    return WorkbookImportAnalysis(
      fileName: 'source.xlsx',
      sourceFingerprint: 'a' * 64,
      sheetPreviews: const [],
      unhandledSheetNames: const [],
      sourceSheets: [
        SourceSheetSnapshot(sourceSheetName: 'Journal', cells: cells),
      ],
    );
  }

  test('classifies retained history without creating historical income', () {
    final preview = const HistoricalAnalyticsPreviewBuilder().build(
      analysis([
        ['2026-05-01', 'Courses', '-120,50', 'Marché'],
        ['2026-05-02', 'Wifi Home', '500', 'Alimentation budget'],
        ['2026-05-03', 'Compte A', '-100', 'Transfert épargne'],
        ['2026-05-03', 'Compte B', '100', 'Transfert épargne'],
        ['2026-05-04', 'Traite maison', '59630', 'Syndic et notaire'],
        ['2026-05-05', 'Besoin personnel', '40', 'Remboursement ?'],
        ['2026-04-30', 'Courses', '-10', 'Hors période'],
        ['2026-09-30', 'Courses', '-10', 'Jour du cutover exclu'],
      ]),
    );

    expect(preview.lines, hasLength(6));
    expect(preview.count(HistoricalAnalyticClassification.expense), 1);
    expect(preview.count(HistoricalAnalyticClassification.budgetFunding), 1);
    expect(preview.count(HistoricalAnalyticClassification.internalTransfer), 2);
    expect(
      preview.count(HistoricalAnalyticClassification.technicalAdjustment),
      1,
    );
    expect(
      preview.count(HistoricalAnalyticClassification.ambiguousPositive),
      1,
    );
    expect(preview.count(HistoricalAnalyticClassification.validatedIncome), 0);
    expect(preview.lines[1].mappedEnvelopeLabel, 'Wifi');
    expect(preview.lines.last.mappedEnvelopeLabel, 'Besoin perso');
  });

  test(
    'keeps strict repetitions and business similarities as separate expenses',
    () {
      final preview = const HistoricalAnalyticsPreviewBuilder().build(
        analysis([
          ['2026-06-01', 'Courses', '-50', 'Épicerie'],
          ['2026-06-01', 'Courses', '-50', 'Épicerie'],
          ['2026-06-02', 'Navette', '-5', 'grand taxi'],
          ['2026-06-02', 'Navette', '-5', 'Grand taxi'],
        ]),
      );
      expect(preview.lines, hasLength(4));
      expect(preview.duplicateCandidates, 4);
      expect(
        preview.repetitionGroupCount(HistoricalAnalyticRepetition.strictSource),
        1,
      );
      expect(
        preview.repetitionLineCount(HistoricalAnalyticRepetition.strictSource),
        2,
      );
      expect(
        preview.repetitionGroupCount(
          HistoricalAnalyticRepetition.businessSimilarity,
        ),
        1,
      );
      expect(
        preview.repetitionLineCount(
          HistoricalAnalyticRepetition.businessSimilarity,
        ),
        2,
      );
      expect(
        preview.lines.every(
          (line) =>
              line.classification == HistoricalAnalyticClassification.expense,
        ),
        isTrue,
      );
      expect(preview.amount(HistoricalAnalyticClassification.expense), 110);
      expect(
        preview.lines.first.duplicateCandidateKey,
        preview.lines[1].duplicateCandidateKey,
      );
      expect(
        preview.lines.first.sourceContentHash,
        isNot(preview.lines[1].sourceContentHash),
      );
    },
  );

  test('commit payload is analytical and contains no financial operation', () {
    final line = const HistoricalAnalyticsPreviewBuilder()
        .build(
          analysis([
            ['2026-05-01', 'Courses', '-120', 'Marché'],
          ]),
        )
        .lines
        .single;
    final payload = line.toCommitJson();
    expect(payload['classification'], 'expense');
    expect(payload['analytical_amount'], 120);
    expect(payload, isNot(contains('financial_event_id')));
    expect(payload, isNot(contains('transaction_id')));
  });
}
