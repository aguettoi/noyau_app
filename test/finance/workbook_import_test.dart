import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/workbook_import.dart';

void main() {
  test(
    'archive les onglets hors périmètre sans bloquer une sélection ciblée',
    () {
      const analysis = WorkbookImportAnalysis(
        fileName: 'source.xlsx',
        sourceFingerprint:
            '0123456789012345678901234567890123456789012345678901234567890123',
        sheetPreviews: [
          SheetImportPreview(
            importerId: 'envelopes',
            sourceSheetName: 'Enveloppes',
            detectedRecords: 25,
            issues: [],
            isTransactionReady: true,
          ),
        ],
        unhandledSheetNames: ['Journal'],
        sourceSheets: [],
      );

      expect(analysis.canConfirmSelection({'envelopes'}), isTrue);
    },
  );

  test('un apercu sans ecart peut etre confirme', () {
    const preview = SheetImportPreview(
      importerId: 'envelopes',
      sourceSheetName: 'Enveloppes',
      detectedRecords: 25,
      issues: [],
      isTransactionReady: true,
    );

    expect(preview.canBeConfirmed, isTrue);
  });

  test('une selection exclut les onglets bloques sans modifier les autres', () {
    const analysis = WorkbookImportAnalysis(
      fileName: 'source.xlsx',
      sourceFingerprint:
          '0123456789012345678901234567890123456789012345678901234567890123',
      sheetPreviews: [
        SheetImportPreview(
          importerId: 'envelopes',
          sourceSheetName: 'Enveloppes',
          detectedRecords: 25,
          issues: [],
        ),
        SheetImportPreview(
          importerId: 'journal',
          sourceSheetName: 'Journal',
          detectedRecords: 0,
          issues: [
            ImportIssue(
              severity: ImportIssueSeverity.blocking,
              message: 'Montant invalide',
            ),
          ],
        ),
      ],
      unhandledSheetNames: [],
      sourceSheets: [],
    );

    expect(analysis.canConfirmSelection({'envelopes'}), isTrue);
    expect(analysis.canConfirmSelection({'envelopes', 'journal'}), isFalse);
  });

  test('le registre couvre les onglets connus et le plan B1 optionnel', () {
    final importers = DefaultWorkbookImportRegistry.create(const []);

    expect(importers, hasLength(30));
    expect(
      importers.map((importer) => importer.sourceSheetName),
      containsAll([
        'Journal',
        'SCENARIOS',
        'Shopping list',
        'PRIOS',
        'Orga m\u00e9nage',
        'SIMULATION EMPRUNT 180 Mois',
        'Positions ouverture',
      ]),
    );
  });

  test(
    'le plan d archive conserve les cellules et les metadonnees par onglet',
    () {
      const analysis = WorkbookImportAnalysis(
        fileName: 'source.xlsx',
        sourceFingerprint:
            '0123456789012345678901234567890123456789012345678901234567890123',
        sheetPreviews: [
          SheetImportPreview(
            importerId: 'envelopes',
            sourceSheetName: 'Enveloppes',
            detectedRecords: 1,
            issues: [],
          ),
        ],
        unhandledSheetNames: [],
        sourceSheets: [
          SourceSheetSnapshot(
            sourceSheetName: 'Enveloppes',
            cells: [SourceCellSnapshot(coordinate: 'A1', value: 'Nourriture')],
          ),
        ],
      );

      final payload = analysis.toArchivePayload();

      expect(payload.single['importer_id'], 'envelopes');
      expect(
        (payload.single['snapshot']
            as Map<String, Object?>)['source_sheet_name'],
        'Enveloppes',
      );
    },
  );
}
