import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/envelope_imported_data.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';

void main() {
  test('lit les vraies lignes Enveloppes et Journal du snapshot confirmé', () {
    const analysis = WorkbookImportAnalysis(
      fileName: 'foyer.xlsx',
      sourceFingerprint: 'fingerprint',
      sheetPreviews: [],
      unhandledSheetNames: [],
      sourceSheets: [
        SourceSheetSnapshot(
          sourceSheetName: 'Enveloppes',
          cells: [
            SourceCellSnapshot(coordinate: 'B17', value: 'Nourriture'),
            SourceCellSnapshot(coordinate: 'B18', value: 'Wifi'),
          ],
        ),
        SourceSheetSnapshot(
          sourceSheetName: 'Journal',
          cells: [
            SourceCellSnapshot(coordinate: 'A2', value: 'Date'),
            SourceCellSnapshot(coordinate: 'B2', value: 'Enveloppe'),
            SourceCellSnapshot(
              coordinate: 'C2',
              value: 'Montant (negatif : depense ; positif : alimentation)',
            ),
            SourceCellSnapshot(coordinate: 'A3', value: '2026-07-01'),
            SourceCellSnapshot(coordinate: 'B3', value: 'Nourriture'),
            SourceCellSnapshot(coordinate: 'C3', value: '1 000'),
            SourceCellSnapshot(coordinate: 'A4', value: '2026-07-03'),
            SourceCellSnapshot(coordinate: 'B4', value: 'Nourriture'),
            SourceCellSnapshot(coordinate: 'C4', value: '-125,50'),
            SourceCellSnapshot(coordinate: 'B5', value: 'Wifi'),
            SourceCellSnapshot(coordinate: 'C5', value: '350'),
          ],
        ),
      ],
    );

    final data = const EnvelopeImportedDataReader().read(analysis)!;

    expect(data.importedMovements, 3);
    expect(data.balances[0].balance, Money.fromDirhams(874.5));
    expect(data.balances[1].balance, Money.fromDirhams(350));
    expect(data.totalFunds, Money.fromDirhams(1224.5));
  });
}
