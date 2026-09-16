import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:noyau_app/features/finance/application/cutover_opening_import.dart';
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

  test('lit les positions d ouverture d un XLSX compatible Excel mais non pris '
      'en charge nativement par excel', () async {
    final bytes = _buildStylesCompatibilityFixture();
    final analysis = await WorkbookImportEngine(
      DefaultWorkbookImportRegistry.create(const []),
    ).analyze(fileName: 'CUTOVER-B1-E2E.xlsx', bytes: bytes);

    expect(analysis.sourceFingerprint, sha256.convert(bytes).toString());
    expect(
      analysis.sourceSheets.map((sheet) => sheet.sourceSheetName),
      contains('Positions ouverture'),
    );

    final plan = CutoverOpeningPlanBuilder().build(
      analysis: analysis,
      householdId: 'household',
      effectiveDate: DateTime(2026, 9, 14),
    );
    expect(plan.canConfirm, isTrue, reason: plan.blockingErrors.join(' | '));
    expect(
      plan.accounts.map((account) => (account.name, account.openingAmount)),
      containsAll([('Banque A', 1000.0), ('Caisse', 200.0)]),
    );
    expect(
      plan.envelopes.map((envelope) => (envelope.name, envelope.openingAmount)),
      containsAll([
        ('Nourriture', 500.0),
        ('Épargne', 250.0),
        ('À répartir', 50.0),
      ]),
    );
  });

  test('refuse toujours un XLSX réellement corrompu', () async {
    await expectLater(
      WorkbookImportEngine(const []).analyze(
        fileName: 'corrompu.xlsx',
        bytes: Uint8List.fromList(utf8.encode('ceci n’est pas un fichier zip')),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('endommagé'),
        ),
      ),
    );
  });

  test(
    'analyse le Journal uniquement à partir de ses quatre colonnes métier',
    () async {
      final workbook = Excel.createExcel();
      final sheet = workbook['Journal'];
      _setText(sheet, 0, 1, 'Date');
      _setText(sheet, 1, 1, 'Enveloppe');
      _setText(
        sheet,
        2,
        1,
        'Montant (negatif : depense ; positif : alimentation)',
      );
      _setText(sheet, 3, 1, 'Detail');
      _setText(sheet, 4, 1, 'Formule hors périmètre');
      _setText(sheet, 0, 2, '2026-09-15');
      _setText(sheet, 1, 2, 'Nourriture');
      _setText(sheet, 2, 2, '-100');
      _setText(sheet, 3, 2, 'Courses');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 2))
          .value = const FormulaCellValue(
        '=SUM(1,2)',
      );
      // This row has an expensive/unrelated formula but no Journal movement.
      // It must not become an artificial invalid record.
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 3))
          .value = const FormulaCellValue(
        '=SUM(999999,999999)',
      );

      final preview = await JournalSheetImporter(const [
        'Nourriture',
      ]).analyze(sheet);

      expect(preview.detectedRecords, 1);
      expect(preview.problems, isEmpty);
    },
  );

  test(
    'l analyse en isolate conserve le résultat B1 et le fingerprint brut',
    () async {
      final bytes = _buildStylesCompatibilityFixture();

      final analysis = await WorkbookImportEngine.analyzeInBackground(
        fileName: 'CUTOVER-B1-E2E.xlsx',
        bytes: bytes,
        expectedEnvelopeNames: const [],
      );

      expect(analysis.sourceFingerprint, sha256.convert(bytes).toString());
      expect(
        analysis.sourceSheets.map((sheet) => sheet.sourceSheetName),
        contains('Positions ouverture'),
      );
    },
  );

  test('les erreurs de décodage dans l isolate remontent proprement', () async {
    await expectLater(
      WorkbookImportEngine.analyzeInBackground(
        fileName: 'corrompu.xlsx',
        bytes: Uint8List.fromList(utf8.encode('ceci n’est pas un fichier zip')),
        expectedEnvelopeNames: const [],
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('endommagé'),
        ),
      ),
    );
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

  test('le fingerprint d’une source inchangée autorise l’exécution', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final fingerprint = sha256.convert(bytes).toString();

    final check = WorkbookImportController.fingerprintCheck(bytes, fingerprint);

    expect(check.isMatch, isTrue);
    expect(check.error, isNull);
  });

  test('une source modifiée depuis la preview est bloquée avant RPC', () {
    final previewBytes = Uint8List.fromList([1, 2, 3]);
    final changedBytes = Uint8List.fromList([1, 2, 4]);

    final check = WorkbookImportController.fingerprintCheck(
      changedBytes,
      sha256.convert(previewBytes).toString(),
    );

    expect(check.isMatch, isFalse);
    expect(check.error, contains('SOURCE MODIFIÉE'));
  });

  test(
    'une source Google est relue avant le contrôle de fingerprint',
    () async {
      var reads = 0;
      final source = WorkbookSource.forTesting(
        kind: WorkbookSourceKind.googleSheet,
        fileName: 'source.xlsx',
        rereader: () async => Uint8List.fromList([++reads]),
      );

      final preview = await source.reread();
      final check = await WorkbookImportController.checkSource(
        source,
        sha256.convert(preview).toString(),
      );

      expect(reads, 2);
      expect(check.isMatch, isFalse);
      expect(check.error, contains('SOURCE MODIFIÉE'));
    },
  );

  test('une source devenue inaccessible est bloquée', () async {
    const source = WorkbookSource.local(fileName: 'source.xlsx', path: null);

    final check = await WorkbookImportController.checkSource(source, 'abc');

    expect(check.isMatch, isFalse);
    expect(check.error, contains('SOURCE INACCESSIBLE'));
  });
}

Uint8List _buildStylesCompatibilityFixture() {
  final workbook = Excel.createExcel();
  final sheet = workbook['Positions ouverture'];
  final rows = [
    ['Type', 'Nom', 'Kind', 'Montant'],
    ['Compte', 'Banque A', 'bank', 1000],
    ['Compte', 'Caisse', 'cash', 200],
    ['Enveloppe', 'Nourriture', '', 500],
    ['Enveloppe', 'Épargne', '', 250],
    ['Enveloppe', 'À répartir', '', 50],
  ];
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    for (
      var columnIndex = 0;
      columnIndex < rows[rowIndex].length;
      columnIndex++
    ) {
      final value = rows[rowIndex][columnIndex];
      sheet
          .cell(
            CellIndex.indexByColumnRow(
              columnIndex: columnIndex,
              rowIndex: rowIndex,
            ),
          )
          .value = value is int
          ? IntCellValue(value)
          : TextCellValue(value as String);
    }
  }

  final encoded = workbook.encode()!;
  final original = ZipDecoder().decodeBytes(encoded, verify: true);
  final mutated = Archive();
  for (final file in original.files) {
    if (!file.isFile) {
      continue;
    }
    file.decompress();
    var content = utf8.decode(file.content as List<int>);
    if (file.name == 'xl/_rels/workbook.xml.rels') {
      content = content
          .replaceAll('Target="styles.xml"', 'Target="/xl/styles.xml"')
          .replaceAll('Target="worksheets/', 'Target="/xl/worksheets/')
          .replaceAll(
            'Target="sharedStrings.xml"',
            'Target="/xl/sharedStrings.xml"',
          );
    } else if (file.name.startsWith('xl/') &&
        file.name.endsWith('.xml') &&
        content.contains(
          'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"',
        )) {
      if (file.name.startsWith('xl/worksheets/')) {
        content = content.replaceAllMapped(
          RegExp(r'<c([^>]*)\s+t="inlineStr"([^>]*)><is><t>(.*?)</t></is></c>'),
          (match) =>
              '<c${match.group(1)} t="str"${match.group(2)}>'
              '<v>${match.group(3)}</v></c>',
        );
      }
      content = content
          .replaceAll(
            'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"',
            'xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main"',
          )
          .replaceAllMapped(
            RegExp(r'<(/?)([A-Za-z][A-Za-z0-9]*)(?=[\s>/])'),
            (match) => '<${match.group(1)}x:${match.group(2)}',
          );
    }
    final bytes = utf8.encode(content);
    mutated.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(mutated)!);
}

void _setText(Sheet sheet, int columnIndex, int rowIndex, String value) {
  sheet
      .cell(
        CellIndex.indexByColumnRow(
          columnIndex: columnIndex,
          rowIndex: rowIndex,
        ),
      )
      .value = TextCellValue(
    value,
  );
}
