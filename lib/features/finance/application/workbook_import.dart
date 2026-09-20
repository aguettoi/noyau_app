import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'source_envelope_import.dart';
import 'google_sheets_workbook_loader.dart';

final workbookImportProvider =
    NotifierProvider<WorkbookImportController, WorkbookImportState>(
      WorkbookImportController.new,
    );

enum ImportIssueSeverity { information, warning, blocking }

enum WorkbookSourceKind { localFile, googleSheet }

/// Keeps only the rereadable source descriptor. The bytes used for preview are
/// never treated as proof at execution time.
class WorkbookSource {
  const WorkbookSource.local({required this.fileName, required this.path})
    : kind = WorkbookSourceKind.localFile,
      googleUrl = null,
      rereader = null;

  const WorkbookSource.google({required this.fileName, required this.googleUrl})
    : kind = WorkbookSourceKind.googleSheet,
      path = null,
      rereader = null;

  /// Test seam only: production sources always use their native reread path.
  const WorkbookSource.forTesting({
    required this.kind,
    required this.fileName,
    required Future<Uint8List> Function() this.rereader,
  }) : path = null,
       googleUrl = null;

  final WorkbookSourceKind kind;
  final String fileName;
  final String? path;
  final String? googleUrl;
  final Future<Uint8List> Function()? rereader;

  Future<Uint8List> reread() async {
    final override = rereader;
    if (override != null) return override();
    return switch (kind) {
      WorkbookSourceKind.localFile => _rereadLocal(),
      WorkbookSourceKind.googleSheet => _rereadGoogle(),
    };
  }

  Future<Uint8List> _rereadLocal() async {
    final localPath = path;
    if (localPath == null || localPath.isEmpty) {
      throw const FormatException('La source locale ne peut plus être relue.');
    }
    return File(localPath).readAsBytes();
  }

  Future<Uint8List> _rereadGoogle() async {
    final url = googleUrl;
    if (url == null || url.isEmpty) {
      throw const FormatException(
        'La source Google Sheets ne peut plus être relue.',
      );
    }
    return (await GoogleSheetsWorkbookLoader().download(url)).bytes;
  }
}

class SourceFingerprintCheck {
  const SourceFingerprintCheck._(this.isMatch, this.error);
  const SourceFingerprintCheck.match() : this._(true, null);
  const SourceFingerprintCheck.blocked(String error) : this._(false, error);
  final bool isMatch;
  final String? error;
}

class ImportIssue {
  const ImportIssue({required this.severity, required this.message});

  final ImportIssueSeverity severity;
  final String message;

  Map<String, Object?> _toBackgroundPayload() => {
    'severity': severity.name,
    'message': message,
  };

  static ImportIssue _fromBackgroundPayload(Map<Object?, Object?> payload) =>
      ImportIssue(
        severity: ImportIssueSeverity.values.byName(
          payload['severity']! as String,
        ),
        message: payload['message']! as String,
      );
}

class ImportProblem {
  const ImportProblem({
    required this.rowNumber,
    required this.field,
    required this.explanation,
    required this.correctionHint,
  });

  final int rowNumber;
  final String field;
  final String explanation;
  final String correctionHint;

  Map<String, Object?> _toBackgroundPayload() => {
    'row_number': rowNumber,
    'field': field,
    'explanation': explanation,
    'correction_hint': correctionHint,
  };

  static ImportProblem _fromBackgroundPayload(Map<Object?, Object?> payload) =>
      ImportProblem(
        rowNumber: payload['row_number']! as int,
        field: payload['field']! as String,
        explanation: payload['explanation']! as String,
        correctionHint: payload['correction_hint']! as String,
      );
}

class SheetImportPreview {
  const SheetImportPreview({
    required this.importerId,
    required this.sourceSheetName,
    required this.detectedRecords,
    required this.issues,
    this.problems = const [],
    this.isTransactionReady = false,
  });

  final String importerId;
  final String sourceSheetName;
  final int detectedRecords;
  final List<ImportIssue> issues;
  final List<ImportProblem> problems;
  final bool isTransactionReady;

  Map<String, Object?> _toBackgroundPayload() => {
    'importer_id': importerId,
    'source_sheet_name': sourceSheetName,
    'detected_records': detectedRecords,
    'issues': issues
        .map((issue) => issue._toBackgroundPayload())
        .toList(growable: false),
    'problems': problems
        .map((problem) => problem._toBackgroundPayload())
        .toList(growable: false),
    'is_transaction_ready': isTransactionReady,
  };

  static SheetImportPreview _fromBackgroundPayload(
    Map<Object?, Object?> payload,
  ) => SheetImportPreview(
    importerId: payload['importer_id']! as String,
    sourceSheetName: payload['source_sheet_name']! as String,
    detectedRecords: payload['detected_records']! as int,
    issues: _backgroundList(payload['issues'])
        .map(
          (issue) => ImportIssue._fromBackgroundPayload(_backgroundMap(issue)),
        )
        .toList(growable: false),
    problems: _backgroundList(payload['problems'])
        .map(
          (problem) =>
              ImportProblem._fromBackgroundPayload(_backgroundMap(problem)),
        )
        .toList(growable: false),
    isTransactionReady: payload['is_transaction_ready']! as bool,
  );

  bool get canBeConfirmed =>
      issues.every((issue) => issue.severity != ImportIssueSeverity.blocking);
}

class SourceCellSnapshot {
  const SourceCellSnapshot({
    required this.coordinate,
    required this.value,
    this.formula,
  });

  final String coordinate;
  final String value;
  final String? formula;

  Map<String, Object?> toJson() => {
    'coordinate': coordinate,
    'value': value,
    if (formula != null) 'formula': formula,
  };

  Map<String, Object?> _toBackgroundPayload() => toJson();

  static SourceCellSnapshot _fromBackgroundPayload(
    Map<Object?, Object?> payload,
  ) => SourceCellSnapshot(
    coordinate: payload['coordinate']! as String,
    value: payload['value']! as String,
    formula: payload['formula'] as String?,
  );
}

class SourceSheetSnapshot {
  const SourceSheetSnapshot({
    required this.sourceSheetName,
    required this.cells,
  });

  final String sourceSheetName;
  final List<SourceCellSnapshot> cells;

  Map<String, Object?> toJson() => {
    'source_sheet_name': sourceSheetName,
    'cells': cells.map((cell) => cell.toJson()).toList(growable: false),
  };

  Map<String, Object?> _toBackgroundPayload() => {
    'source_sheet_name': sourceSheetName,
    'cells': cells
        .map((cell) => cell._toBackgroundPayload())
        .toList(growable: false),
  };

  static SourceSheetSnapshot _fromBackgroundPayload(
    Map<Object?, Object?> payload,
  ) => SourceSheetSnapshot(
    sourceSheetName: payload['source_sheet_name']! as String,
    cells: _backgroundList(payload['cells'])
        .map(
          (cell) =>
              SourceCellSnapshot._fromBackgroundPayload(_backgroundMap(cell)),
        )
        .toList(growable: false),
  );
}

/// Contract implemented by exactly one module per workbook sheet.
///
/// A module owns parsing, differences, validation, its transaction payload and
/// its compensating operation. The engine never needs changing when a sheet is
/// added: it only orchestrates registered modules.
abstract interface class WorkbookSheetImporter {
  String get id;
  String get sourceSheetName;

  Future<SheetImportPreview> analyze(Sheet sheet);
}

/// Implemented by the data layer when an importer is ready to write its target
/// tables. A sheet importer supplies reversible commands; the shared gateway
/// commits all commands in one database transaction and can replay their undo
/// commands as one cancellation operation.
abstract interface class WorkbookImportCommitter {
  Future<ImportCommitResult> commit(ConfirmedWorkbookImport import);

  Future<void> undo(String importSessionId, {required String reason});
}

class ConfirmedWorkbookImport {
  const ConfirmedWorkbookImport({
    required this.analysis,
    required this.selectedImporterIds,
  });

  final WorkbookImportAnalysis analysis;
  final Set<String> selectedImporterIds;
}

class ImportCommitResult {
  const ImportCommitResult({required this.importSessionId});

  final String importSessionId;
}

class EnvelopeSheetImporter implements WorkbookSheetImporter {
  EnvelopeSheetImporter(this._expectedNames);

  final List<String> _expectedNames;

  @override
  String get id => 'envelopes';

  @override
  String get sourceSheetName => 'Enveloppes';

  @override
  Future<SheetImportPreview> analyze(Sheet sheet) async {
    final normalizedCells = {
      for (final cell in sheet.rows.expand((row) => row))
        if (cell?.value != null) _normalize(cell!.value.toString()): true,
    };
    final missing = _expectedNames
        .where((name) => !normalizedCells.containsKey(_normalize(name)))
        .toList(growable: false);

    return SheetImportPreview(
      importerId: id,
      sourceSheetName: sourceSheetName,
      detectedRecords: _expectedNames.length - missing.length,
      issues: [
        if (missing.isEmpty)
          const ImportIssue(
            severity: ImportIssueSeverity.information,
            message: 'Les 25 enveloppes de reference sont presentes.',
          )
        else
          ImportIssue(
            severity: ImportIssueSeverity.blocking,
            message: 'Enveloppes non trouvees : ${missing.join(', ')}',
          ),
      ],
      isTransactionReady: true,
    );
  }
}

class JournalSheetImporter implements WorkbookSheetImporter {
  JournalSheetImporter(this._knownEnvelopeNames);

  final List<String> _knownEnvelopeNames;

  @override
  String get id => 'journal';

  @override
  String get sourceSheetName => 'Journal';

  @override
  Future<SheetImportPreview> analyze(Sheet sheet) async {
    const headerRow = 2;
    // `excel` rebuilds the complete two-dimensional matrix for every `rows`
    // access. Keep one materialized view for the large Journal sheet.
    final rows = sheet.rows;
    if (rows.length < headerRow) {
      return const SheetImportPreview(
        importerId: 'journal',
        sourceSheetName: 'Journal',
        detectedRecords: 0,
        issues: [
          ImportIssue(
            severity: ImportIssueSeverity.blocking,
            message: 'Entete du journal introuvable.',
          ),
        ],
      );
    }

    final headers = _rowValues(rows[headerRow - 1]);
    final indexes = {
      for (var index = 0; index < headers.length; index++)
        _normalize(headers[index]): index,
    };
    final required = [
      'date',
      'enveloppe',
      'montant (negatif : depense ; positif : alimentation)',
      'detail',
    ];
    final missingHeaders = required
        .where((header) => !indexes.containsKey(header))
        .toList();
    if (missingHeaders.isNotEmpty) {
      return SheetImportPreview(
        importerId: id,
        sourceSheetName: sourceSheetName,
        detectedRecords: 0,
        issues: [
          ImportIssue(
            severity: ImportIssueSeverity.blocking,
            message:
                'Colonnes obligatoires absentes : ${missingHeaders.join(', ')}',
          ),
        ],
      );
    }

    final envelopeIndex = indexes['enveloppe']!;
    final dateIndex = indexes['date']!;
    final amountIndex =
        indexes['montant (negatif : depense ; positif : alimentation)']!;
    final detailIndex = indexes['detail']!;
    final knownEnvelopes = _knownEnvelopeNames.map(_normalize).toSet();
    var records = 0;
    final problems = <ImportProblem>[];

    for (var rowIndex = headerRow; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      // The Journal can contain tens of thousands of formula cells in columns
      // unrelated to a financial movement. Only these four business fields
      // determine whether a Journal row exists and whether it is valid.
      final date = _journalCellValue(row, dateIndex);
      final envelope = _journalCellValue(row, envelopeIndex);
      final amount = _journalCellValue(row, amountIndex);
      final detail = _journalCellValue(row, detailIndex);
      if ([date, envelope, amount, detail].every((value) => value.isEmpty)) {
        continue;
      }
      records++;
      final rowNumber = rowIndex + 1;
      if (date.isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Date',
            'Cette depense ou alimentation n a pas de date.',
            'Saisissez une date dans la colonne Date.',
          ),
        );
      }
      if (envelope.isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Enveloppe',
            'La ligne ne peut pas etre rattachee a un budget.',
            'Choisissez une des enveloppes du foyer.',
          ),
        );
      } else if (!knownEnvelopes.contains(_normalize(envelope))) {
        problems.add(
          ImportProblem(
            rowNumber: rowNumber,
            field: 'Enveloppe',
            explanation:
                '"$envelope" ne correspond a aucune enveloppe reconnue.',
            correctionHint:
                'Corrigez le libelle ou ajoutez cette enveloppe apres validation.',
          ),
        );
      }
      if (_parseAmount(amount) == null) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Montant',
            'Le montant doit etre un nombre positif ou negatif.',
            'Saisissez par exemple 250 ou -250, sans texte.',
          ),
        );
      }
      if (detail.isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Detail',
            'Cette ligne ne permet pas de comprendre le mouvement.',
            'Ajoutez une courte explication, par exemple "Alimentation budget".',
          ),
        );
      }
    }

    final invalidRows = problems
        .map((problem) => problem.rowNumber)
        .toSet()
        .length;
    final unknownEnvelopes = problems
        .where(
          (problem) =>
              problem.field == 'Enveloppe' &&
              problem.explanation.contains('ne correspond'),
        )
        .map((problem) => problem.rowNumber)
        .toSet()
        .length;

    return SheetImportPreview(
      importerId: id,
      sourceSheetName: sourceSheetName,
      detectedRecords: records,
      issues: [
        if (invalidRows > 0)
          ImportIssue(
            severity: ImportIssueSeverity.blocking,
            message:
                '$invalidRows ligne(s) incomplete(s) ou avec un montant invalide.',
          ),
        if (unknownEnvelopes > 0)
          ImportIssue(
            severity: ImportIssueSeverity.blocking,
            message:
                '$unknownEnvelopes ligne(s) referencent une enveloppe inconnue.',
          ),
        if (invalidRows == 0 && unknownEnvelopes == 0)
          const ImportIssue(
            severity: ImportIssueSeverity.information,
            message: 'Dates, enveloppes, montants signes et details reconnus.',
          ),
        const ImportIssue(
          severity: ImportIssueSeverity.information,
          message:
              'Le journal sera archive avec le classeur; son mapping Grand Livre attend les comptes confirmes.',
        ),
      ],
      problems: problems,
    );
  }
}

class ScenarioSheetImporter implements WorkbookSheetImporter {
  ScenarioSheetImporter(this._knownEnvelopeNames);

  final List<String> _knownEnvelopeNames;

  @override
  String get id => 'scenarios';

  @override
  String get sourceSheetName => 'SCENARIOS';

  @override
  Future<SheetImportPreview> analyze(Sheet sheet) async {
    final indexes = _headerIndexes(sheet, 1);
    const required = [
      'scenario',
      'enveloppes',
      'montant prevu',
      'salaire',
      'cash',
      'duree en mois',
    ];
    final missingHeaders = required
        .where((header) => !indexes.containsKey(header))
        .toList();
    if (missingHeaders.isNotEmpty) {
      return _missingHeadersPreview(id, sourceSheetName, missingHeaders);
    }

    var records = 0;
    final sourceEnvelopeLabels = <String>{};
    final problems = <ImportProblem>[];
    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final values = _rowValues(sheet.rows[rowIndex]);
      final scenario = _cell(values, indexes['scenario']!);
      final envelope = _cell(values, indexes['enveloppes']!);
      if (scenario.isEmpty && envelope.isEmpty) {
        continue;
      }
      records++;
      sourceEnvelopeLabels.add(envelope);
      final rowNumber = rowIndex + 1;
      if (scenario.isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Scenario',
            'La ligne ne precise pas a quel scenario elle appartient.',
            'Saisissez un nom de scenario, par exemple DEPART.',
          ),
        );
      }
      if (envelope.isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Enveloppes',
            'La ligne ne precise pas quelle enveloppe est concernee.',
            'Saisissez le nom de l enveloppe.',
          ),
        );
      }
      if (_cell(values, indexes['salaire']!).isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Salaire',
            'Le membre payeur n est pas indique.',
            'Saisissez le membre concerne.',
          ),
        );
      }
      if (_cell(values, indexes['cash']!).isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Cash',
            'Le compte source n est pas indique.',
            'Saisissez le nom du compte ou de l espece.',
          ),
        );
      }
      if (!_isAmountOrFormula(_cell(values, indexes['montant prevu']!))) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Montant prevu',
            'Le montant est vide ou ne peut pas etre lu.',
            'Saisissez un montant ou conservez une formule Excel valide.',
          ),
        );
      }
      if (!_isAmountOrFormula(_cell(values, indexes['duree en mois']!))) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Duree en mois',
            'La duree est vide ou ne peut pas etre lue.',
            'Saisissez un nombre de mois ou conservez une formule Excel valide.',
          ),
        );
      }
    }
    final known = _knownEnvelopeNames.map(_normalize).toSet();
    final unmatched = sourceEnvelopeLabels
        .where(
          (label) => label.isNotEmpty && !known.contains(_normalize(label)),
        )
        .toList(growable: false);
    final invalidRows = problems
        .map((problem) => problem.rowNumber)
        .toSet()
        .length;
    return SheetImportPreview(
      importerId: id,
      sourceSheetName: sourceSheetName,
      detectedRecords: records,
      issues: [
        if (invalidRows > 0)
          ImportIssue(
            severity: ImportIssueSeverity.blocking,
            message:
                '$invalidRows ligne(s) de scenario incomplete(s) ou invalide(s).',
          ),
        if (unmatched.isNotEmpty)
          ImportIssue(
            severity: ImportIssueSeverity.warning,
            message:
                'Libelles a confirmer avec les enveloppes : ${unmatched.join(', ')}',
          ),
        if (invalidRows == 0)
          const ImportIssue(
            severity: ImportIssueSeverity.information,
            message: 'Scenarios, salaires, comptes source et durees reconnus.',
          ),
        const ImportIssue(
          severity: ImportIssueSeverity.information,
          message:
              'Les correspondances seront confirmees avant la creation des regles de repartition.',
        ),
      ],
      problems: problems,
    );
  }
}

class ShoppingListSheetImporter implements WorkbookSheetImporter {
  @override
  String get id => 'shopping-list';

  @override
  String get sourceSheetName => 'Shopping list';

  @override
  Future<SheetImportPreview> analyze(Sheet sheet) async {
    final indexes = _headerIndexes(sheet, 3);
    const required = [
      'element',
      'estimation',
      'priorite nora',
      'priorite ibrahim',
      'fait ?',
    ];
    final missingHeaders = required
        .where((header) => !indexes.containsKey(header))
        .toList();
    if (missingHeaders.isNotEmpty) {
      return _missingHeadersPreview(id, sourceSheetName, missingHeaders);
    }

    var records = 0;
    final problems = <ImportProblem>[];
    for (var rowIndex = 3; rowIndex < sheet.rows.length; rowIndex++) {
      final values = _rowValues(sheet.rows[rowIndex]);
      final element = _cell(values, indexes['element']!);
      if (element.isEmpty) {
        continue;
      }
      records++;
      final rowNumber = rowIndex + 1;
      final estimate = _parseAmount(_cell(values, indexes['estimation']!));
      final noraPriority = _parseAmount(
        _cell(values, indexes['priorite nora']!),
      );
      final ibrahimPriority = _parseAmount(
        _cell(values, indexes['priorite ibrahim']!),
      );
      if (estimate == null || estimate < 0) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Estimation',
            'Le prix estime est absent ou invalide.',
            'Saisissez un montant positif, par exemple 600.',
          ),
        );
      }
      if (noraPriority == null) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Priorite Nora',
            'La priorite de Nora est absente.',
            'Saisissez un niveau de priorite, par exemple 0, 1, 2 ou 3.',
          ),
        );
      }
      if (ibrahimPriority == null) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Priorite Ibrahim',
            'La priorite d Ibrahim est absente.',
            'Saisissez un niveau de priorite, par exemple 0, 1, 2 ou 3.',
          ),
        );
      }
    }
    final invalidRows = problems
        .map((problem) => problem.rowNumber)
        .toSet()
        .length;
    return SheetImportPreview(
      importerId: id,
      sourceSheetName: sourceSheetName,
      detectedRecords: records,
      issues: [
        if (invalidRows > 0)
          ImportIssue(
            severity: ImportIssueSeverity.blocking,
            message:
                '$invalidRows achat(s) ont une estimation ou une priorite invalide.',
          ),
        if (invalidRows == 0)
          const ImportIssue(
            severity: ImportIssueSeverity.information,
            message:
                'Achats, estimations, priorites et statut de realisation reconnus.',
          ),
        const ImportIssue(
          severity: ImportIssueSeverity.information,
          message:
              'Les achats seront archives et attendront le module objectifs pour leur materialisation.',
        ),
      ],
      problems: problems,
    );
  }
}

class PrioritiesSheetImporter implements WorkbookSheetImporter {
  @override
  String get id => 'priorities';

  @override
  String get sourceSheetName => 'PRIOS';

  @override
  Future<SheetImportPreview> analyze(Sheet sheet) async {
    final indexes = _headerIndexes(sheet, 1);
    const required = ['prio', 'element', 'montant'];
    final missingHeaders = required
        .where((header) => !indexes.containsKey(header))
        .toList();
    if (missingHeaders.isNotEmpty) {
      return _missingHeadersPreview(id, sourceSheetName, missingHeaders);
    }

    var records = 0;
    final problems = <ImportProblem>[];
    for (var rowIndex = 1; rowIndex < sheet.rows.length; rowIndex++) {
      final values = _rowValues(sheet.rows[rowIndex]);
      final priority = _cell(values, indexes['prio']!);
      final item = _cell(values, indexes['element']!);
      if (priority.isEmpty && item.isEmpty) {
        continue;
      }
      records++;
      final rowNumber = rowIndex + 1;
      if (priority.isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'PRIO',
            'Le rang de priorite est absent.',
            'Saisissez par exemple PRIO 1.',
          ),
        );
      }
      if (item.isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'ELEMENT',
            'L element prioritaire est absent.',
            'Saisissez le nom de l achat ou du projet.',
          ),
        );
      }
      if ((_parseAmount(_cell(values, indexes['montant']!)) ?? -1) < 0) {
        problems.add(
          _missingProblem(
            rowNumber,
            'MONTANT',
            'Le cout est absent ou invalide.',
            'Saisissez un montant positif.',
          ),
        );
      }
    }
    final invalidRows = problems
        .map((problem) => problem.rowNumber)
        .toSet()
        .length;
    return SheetImportPreview(
      importerId: id,
      sourceSheetName: sourceSheetName,
      detectedRecords: records,
      issues: [
        if (invalidRows > 0)
          ImportIssue(
            severity: ImportIssueSeverity.blocking,
            message:
                '$invalidRows priorite(s) incomplete(s) ou avec un montant invalide.',
          ),
        if (invalidRows == 0)
          const ImportIssue(
            severity: ImportIssueSeverity.information,
            message: 'Rang, element et montant de priorite reconnus.',
          ),
        const ImportIssue(
          severity: ImportIssueSeverity.information,
          message:
              'Les priorites seront archivees et attendront le module objectifs pour leur materialisation.',
        ),
      ],
      problems: problems,
    );
  }
}

/// Reusable base for an importer that owns a tabular source sheet. A concrete
/// registration carries its own headers and identifier, so adding a new sheet
/// never changes [WorkbookImportEngine].
class HeaderSheetImporter implements WorkbookSheetImporter {
  const HeaderSheetImporter({
    required this.id,
    required this.sourceSheetName,
    required this.headerRow,
    required this.requiredHeaders,
    this.isTransactionReady = true,
  });

  @override
  final String id;
  @override
  final String sourceSheetName;
  final int headerRow;
  final List<String> requiredHeaders;
  final bool isTransactionReady;

  @override
  Future<SheetImportPreview> analyze(Sheet sheet) async {
    final headerCells = sheet.rows.length >= headerRow
        ? sheet.rows[headerRow - 1]
              .map((cell) => cell?.value?.toString() ?? '')
              .toList(growable: false)
        : const <String>[];
    final normalizedHeaders = headerCells.map(_normalize).toSet();
    final missing = requiredHeaders
        .where((header) => !normalizedHeaders.contains(_normalize(header)))
        .toList(growable: false);
    final records = sheet.rows
        .skip(headerRow)
        .where(
          (row) => row.any(
            (cell) => (cell?.value?.toString() ?? '').trim().isNotEmpty,
          ),
        )
        .length;
    return SheetImportPreview(
      importerId: id,
      sourceSheetName: sourceSheetName,
      detectedRecords: records,
      isTransactionReady: isTransactionReady,
      issues: [
        if (missing.isNotEmpty)
          ImportIssue(
            severity: ImportIssueSeverity.blocking,
            message: 'Colonnes obligatoires absentes : ${missing.join(', ')}',
          )
        else
          const ImportIssue(
            severity: ImportIssueSeverity.information,
            message: 'Structure de la table reconnue.',
          ),
      ],
    );
  }
}

/// Owns a calculation, dashboard or simulation sheet. It is still registered
/// independently and audited. Its formula cells are archived verbatim rather
/// than flattened into values, then mapped by its dedicated future module.
class FormulaSheetImporter implements WorkbookSheetImporter {
  const FormulaSheetImporter({required this.id, required this.sourceSheetName});

  @override
  final String id;
  @override
  final String sourceSheetName;

  @override
  Future<SheetImportPreview> analyze(Sheet sheet) async {
    final nonEmptyRows = sheet.rows
        .where(
          (row) => row.any(
            (cell) => (cell?.value?.toString() ?? '').trim().isNotEmpty,
          ),
        )
        .length;
    return SheetImportPreview(
      importerId: id,
      sourceSheetName: sourceSheetName,
      detectedRecords: nonEmptyRows,
      issues: const [
        ImportIssue(
          severity: ImportIssueSeverity.information,
          message:
              'Onglet de calcul archive avec ses formules; mapping metier distinct.',
        ),
      ],
    );
  }
}

/// B1 owns this deliberately small, opt-in opening-position sheet.  A source
/// workbook can still contain any number of unrelated/archive sheets.
class OpeningPositionsSheetImporter implements WorkbookSheetImporter {
  const OpeningPositionsSheetImporter();

  @override
  String get id => 'cutover-opening-positions';

  @override
  String get sourceSheetName => 'Positions ouverture';

  @override
  Future<SheetImportPreview> analyze(Sheet sheet) async {
    final records = sheet.rows
        .skip(1)
        .where(
          (row) => row.any(
            (cell) => (cell?.value?.toString() ?? '').trim().isNotEmpty,
          ),
        )
        .length;
    return SheetImportPreview(
      importerId: id,
      sourceSheetName: sourceSheetName,
      detectedRecords: records,
      issues: const [
        ImportIssue(
          severity: ImportIssueSeverity.information,
          message:
              'Positions B1 détectées : elles seront contrôlées avant confirmation.',
        ),
      ],
      isTransactionReady: true,
    );
  }
}

class DefaultWorkbookImportRegistry {
  const DefaultWorkbookImportRegistry._();

  static List<WorkbookSheetImporter> create(List<String> expectedEnvelopes) => [
    EnvelopeSheetImporter(expectedEnvelopes),
    JournalSheetImporter(expectedEnvelopes),
    ScenarioSheetImporter(expectedEnvelopes),
    ShoppingListSheetImporter(),
    PrioritiesSheetImporter(),
    const HeaderSheetImporter(
      id: 'household-tasks',
      sourceSheetName: 'Orga m\u00e9nage',
      headerRow: 2,
      requiredHeaders: ['Piece', 'Tache', 'Jour', 'Frequence'],
    ),
    const FormulaSheetImporter(id: 'mapping', sourceSheetName: 'MAPPING'),
    const FormulaSheetImporter(
      id: 'income-current',
      sourceSheetName: 'Test Nv salaires',
    ),
    const FormulaSheetImporter(
      id: 'income-after-car',
      sourceSheetName: 'Test Nv salaires apr\u00e8s acquisit',
    ),
    const FormulaSheetImporter(
      id: 'income-after-repayment',
      sourceSheetName: 'Test Nv salaires apr\u00e8s rembours',
    ),
    const FormulaSheetImporter(
      id: 'income-after-august-27',
      sourceSheetName: 'Test Nv salaires apr\u00e8s Ao\u00fbt 27',
    ),
    const FormulaSheetImporter(
      id: 'income-sheet-21',
      sourceSheetName: 'Feuille 21',
    ),
    const FormulaSheetImporter(
      id: 'income-after-priorities',
      sourceSheetName: 'Test Nv salaires apr\u00e8s FIN PRIO',
    ),
    const FormulaSheetImporter(
      id: 'income-sheet-22',
      sourceSheetName: 'Feuille 22',
    ),
    const OpeningPositionsSheetImporter(),
    const FormulaSheetImporter(id: 'dashboard', sourceSheetName: 'TDB'),
    const FormulaSheetImporter(
      id: 'household-sheet-16',
      sourceSheetName: 'Feuille 16',
    ),
    const FormulaSheetImporter(
      id: 'loan-180',
      sourceSheetName: 'SIMULATION EMPRUNT 180 Mois',
    ),
    const FormulaSheetImporter(
      id: 'loan-240',
      sourceSheetName: 'SIMULATION EMPRUNT 240 mois',
    ),
    const FormulaSheetImporter(
      id: 'loan-karam',
      sourceSheetName: 'SIMULATION EMPRUNT KARAM 180 Mo',
    ),
    const FormulaSheetImporter(
      id: 'loan-umnya',
      sourceSheetName: 'SIMULATION EMPRUNT UMNYA 180 Mo',
    ),
    const FormulaSheetImporter(
      id: 'loan-yousr',
      sourceSheetName: 'SIMULATION EMPRUNT YOUSR 180 Mo',
    ),
    const FormulaSheetImporter(
      id: 'loan-akhdar',
      sourceSheetName: 'SIMULATION EMPRUNT AKHDAR 180 M',
    ),
    const FormulaSheetImporter(
      id: 'loan-dar-amane',
      sourceSheetName: 'SIMULATION EMPRUNT DAR AMANE 18',
    ),
    const FormulaSheetImporter(
      id: 'loan-arreda',
      sourceSheetName: 'SIMULATION EMPRUNT ARREDA 180 M',
    ),
    const FormulaSheetImporter(
      id: 'notary-simulation',
      sourceSheetName: 'SIMULATION NOTAIRE',
    ),
    const FormulaSheetImporter(
      id: 'property-sale-simulation',
      sourceSheetName: 'SIMULATION VENTE APPARTEMENT',
    ),
    const FormulaSheetImporter(
      id: 'comparison',
      sourceSheetName: 'COMPARAISON',
    ),
    const FormulaSheetImporter(
      id: 'legacy-programme',
      sourceSheetName: 'ANCIEN PROGRAMME',
    ),
    const FormulaSheetImporter(
      id: 'car-purchase',
      sourceSheetName: 'Acquisit voiture',
    ),
  ];
}

class WorkbookImportAnalysis {
  const WorkbookImportAnalysis({
    required this.fileName,
    required this.sourceFingerprint,
    required this.sheetPreviews,
    required this.unhandledSheetNames,
    required this.sourceSheets,
  });

  final String fileName;
  final String sourceFingerprint;
  final List<SheetImportPreview> sheetPreviews;
  final List<String> unhandledSheetNames;
  final List<SourceSheetSnapshot> sourceSheets;

  bool get canBeConfirmed =>
      sheetPreviews.every((preview) => preview.canBeConfirmed);

  Map<String, Object?> _toBackgroundPayload() => {
    'file_name': fileName,
    'source_fingerprint': sourceFingerprint,
    'sheet_previews': sheetPreviews
        .map((preview) => preview._toBackgroundPayload())
        .toList(growable: false),
    'unhandled_sheet_names': unhandledSheetNames,
    'source_sheets': sourceSheets
        .map((sheet) => sheet._toBackgroundPayload())
        .toList(growable: false),
  };

  static WorkbookImportAnalysis _fromBackgroundPayload(
    Map<Object?, Object?> payload,
  ) => WorkbookImportAnalysis(
    fileName: payload['file_name']! as String,
    sourceFingerprint: payload['source_fingerprint']! as String,
    sheetPreviews: _backgroundList(payload['sheet_previews'])
        .map(
          (preview) => SheetImportPreview._fromBackgroundPayload(
            _backgroundMap(preview),
          ),
        )
        .toList(growable: false),
    unhandledSheetNames: _backgroundList(
      payload['unhandled_sheet_names'],
    ).cast<String>(),
    sourceSheets: _backgroundList(payload['source_sheets'])
        .map(
          (sheet) =>
              SourceSheetSnapshot._fromBackgroundPayload(_backgroundMap(sheet)),
        )
        .toList(growable: false),
  );

  List<Map<String, Object?>> toArchivePayload({Set<String>? importerIds}) {
    final previewsBySheet = {
      for (final preview in sheetPreviews) preview.sourceSheetName: preview,
    };
    return sourceSheets
        .where(
          (snapshot) =>
              importerIds == null ||
              importerIds.contains(
                previewsBySheet[snapshot.sourceSheetName]!.importerId,
              ),
        )
        .map((snapshot) {
          final preview = previewsBySheet[snapshot.sourceSheetName]!;
          return {
            'importer_id': preview.importerId,
            'source_sheet_name': snapshot.sourceSheetName,
            'detected_records': preview.detectedRecords,
            'preview': {
              'issues': preview.issues
                  .map(
                    (issue) => {
                      'severity': issue.severity.name,
                      'message': issue.message,
                    },
                  )
                  .toList(growable: false),
            },
            'snapshot': snapshot.toJson(),
          };
        })
        .toList(growable: false);
  }

  List<SheetImportPreview> previewsFor(Set<String> importerIds) => sheetPreviews
      .where((preview) => importerIds.contains(preview.importerId))
      .toList(growable: false);

  bool canConfirmSelection(Set<String> importerIds) =>
      importerIds.isNotEmpty &&
      previewsFor(importerIds).every((preview) => preview.canBeConfirmed);
}

class WorkbookImportEngine {
  const WorkbookImportEngine(this._importers);

  final List<WorkbookSheetImporter> _importers;

  Future<WorkbookImportAnalysis> analyze({
    required String fileName,
    required Uint8List bytes,
    void Function(int completed, int total)? onProgress,
  }) async {
    final workbook = _WorkbookDecoder.decode(bytes);
    final previews = <SheetImportPreview>[];
    final handledNames = <String>{};
    final sourceSheets = <SourceSheetSnapshot>[];

    for (var index = 0; index < _importers.length; index++) {
      final importer = _importers[index];
      final resolvedSheetName = _resolveSheetName(
        importer.sourceSheetName,
        workbook.tables.keys,
      );
      if (resolvedSheetName == null) {
        // Missing sheets are not selected and must not block unrelated B1
        // work; only an explicitly selected sheet participates in validation.
        onProgress?.call(index + 1, _importers.length);
        continue;
      }
      final sheet = workbook.tables[resolvedSheetName];
      if (sheet == null) {
        continue;
      }
      handledNames.add(resolvedSheetName);
      final preview = await importer.analyze(sheet);
      previews.add(
        SheetImportPreview(
          importerId: preview.importerId,
          sourceSheetName: resolvedSheetName,
          detectedRecords: preview.detectedRecords,
          issues: preview.issues,
          problems: preview.problems,
          isTransactionReady: preview.isTransactionReady,
        ),
      );
      sourceSheets.add(_snapshotSheet(resolvedSheetName, sheet));
      onProgress?.call(index + 1, _importers.length);
    }

    final unhandled = workbook.tables.keys
        .where((name) => !handledNames.contains(name))
        .toList(growable: false);
    return WorkbookImportAnalysis(
      fileName: fileName,
      sourceFingerprint: sha256.convert(bytes).toString(),
      sheetPreviews: List.unmodifiable(previews),
      unhandledSheetNames: List.unmodifiable(unhandled),
      sourceSheets: List.unmodifiable(sourceSheets),
    );
  }

  /// Runs the existing decoder and import engine away from Flutter's UI
  /// isolate. The request and response contain only transferable bytes and
  /// primitive collection payloads; accounting and import rules stay in this
  /// engine and are not duplicated in the presentation layer.
  static Future<WorkbookImportAnalysis> analyzeInBackground({
    required String fileName,
    required Uint8List bytes,
    required List<String> expectedEnvelopeNames,
  }) async {
    final request = _WorkbookImportBackgroundRequest(
      fileName: fileName,
      sourceBytes: TransferableTypedData.fromList([bytes]),
      expectedEnvelopeNames: expectedEnvelopeNames,
    );
    final payload = await Isolate.run(
      () => _analyzeWorkbookInBackground(request),
    );
    return WorkbookImportAnalysis._fromBackgroundPayload(payload);
  }

  static String? _resolveSheetName(String expected, Iterable<String> names) {
    if (names.contains(expected)) return expected;
    const aliases = {'Feuille 21': 'Feuille 25', 'Feuille 22': 'Feuille 26'};
    final alias = aliases[expected];
    return alias != null && names.contains(alias) ? alias : null;
  }
}

class _WorkbookImportBackgroundRequest {
  const _WorkbookImportBackgroundRequest({
    required this.fileName,
    required this.sourceBytes,
    required this.expectedEnvelopeNames,
  });

  final String fileName;
  final TransferableTypedData sourceBytes;
  final List<String> expectedEnvelopeNames;
}

Future<Map<String, Object?>> _analyzeWorkbookInBackground(
  _WorkbookImportBackgroundRequest request,
) async {
  final bytes = request.sourceBytes.materialize().asUint8List();
  final analysis = await WorkbookImportEngine(
    DefaultWorkbookImportRegistry.create(request.expectedEnvelopeNames),
  ).analyze(fileName: request.fileName, bytes: bytes);
  return analysis._toBackgroundPayload();
}

/// Compatibility adapter for valid OOXML workbooks that use absolute package
/// targets or an explicit SpreadsheetML prefix. `excel` 4.0.6 expects relative
/// targets and unprefixed SpreadsheetML elements. The source bytes remain the
/// import source of record: this adapter is only an in-memory representation
/// passed to the existing decoder, so the SHA-256 fingerprint is unaffected.
class _WorkbookDecoder {
  static Excel decode(Uint8List sourceBytes) {
    try {
      return Excel.decodeBytes(sourceBytes);
    } catch (_) {
      final normalization = _OoxmlCompatibilityNormalizer.normalize(
        sourceBytes,
      );
      if (!normalization.isOoxml) {
        throw const FormatException(
          'Le fichier Excel est endommagé ou n’est pas un fichier .xlsx valide.',
        );
      }
      final normalizedBytes = normalization.bytes;
      if (normalizedBytes == null) {
        throw const FormatException(
          'Le fichier Excel contient une structure non prise en charge. '
          'Ouvrez-le dans Excel puis enregistrez-le à nouveau au format .xlsx.',
        );
      }
      try {
        return Excel.decodeBytes(normalizedBytes);
      } catch (_) {
        throw const FormatException(
          'Le fichier Excel est lisible, mais certaines de ses structures ne '
          'sont pas encore prises en charge. Ouvrez-le dans Excel puis '
          'enregistrez-le à nouveau au format .xlsx.',
        );
      }
    }
  }
}

class _OoxmlNormalizationResult {
  const _OoxmlNormalizationResult({required this.isOoxml, required this.bytes});

  final bool isOoxml;
  final Uint8List? bytes;
}

class _OoxmlCompatibilityNormalizer {
  static const _spreadsheetMlNamespace =
      'http://schemas.openxmlformats.org/spreadsheetml/2006/main';

  static _OoxmlNormalizationResult normalize(Uint8List sourceBytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(sourceBytes, verify: true);
    } catch (_) {
      return const _OoxmlNormalizationResult(isOoxml: false, bytes: null);
    }

    final hasWorkbook = archive.findFile('xl/workbook.xml') != null;
    final hasContentTypes = archive.findFile('[Content_Types].xml') != null;
    if (!hasWorkbook || !hasContentTypes) {
      return const _OoxmlNormalizationResult(isOoxml: false, bytes: null);
    }

    var changed = false;
    final normalizedArchive = Archive();
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      file.decompress();
      var content = Uint8List.fromList(file.content as List<int>);
      if (file.name == 'xl/_rels/workbook.xml.rels') {
        final normalized = _normalizeWorkbookRelationships(
          utf8.decode(content),
        );
        if (normalized != null) {
          content = Uint8List.fromList(utf8.encode(normalized));
          changed = true;
        }
      } else if (file.name.startsWith('xl/') && file.name.endsWith('.xml')) {
        final normalized = _normalizeSpreadsheetMarkup(
          file.name,
          utf8.decode(content),
        );
        if (normalized != null) {
          content = Uint8List.fromList(utf8.encode(normalized));
          changed = true;
        }
      }
      normalizedArchive.addFile(
        ArchiveFile(file.name, content.length, content),
      );
    }

    if (!changed) {
      return const _OoxmlNormalizationResult(isOoxml: true, bytes: null);
    }
    final bytes = ZipEncoder().encode(normalizedArchive);
    return _OoxmlNormalizationResult(
      isOoxml: true,
      bytes: bytes == null ? null : Uint8List.fromList(bytes),
    );
  }

  static String? _normalizeWorkbookRelationships(String xml) {
    final normalized = xml
        .replaceAll('Target="/xl/', 'Target="')
        .replaceAll("Target='/xl/", "Target='");
    return normalized == xml ? null : normalized;
  }

  static String? _normalizeSpreadsheetMarkup(String path, String xml) {
    var normalized = xml;
    if (normalized.contains('xmlns:x="$_spreadsheetMlNamespace"')) {
      normalized = normalized
          .replaceAll(
            'xmlns:x="$_spreadsheetMlNamespace"',
            'xmlns="$_spreadsheetMlNamespace"',
          )
          .replaceAll('<x:', '<')
          .replaceAll('</x:', '</');
    }
    if (path.startsWith('xl/worksheets/')) {
      normalized = normalized
          .replaceAllMapped(
            RegExp(r'<c(\s+[^>]*?)\s+t="str"([^>]*)><v>(.*?)</v></c>'),
            (match) =>
                '<c${match.group(1)} t="inlineStr"${match.group(2)}>'
                '<is><t>${match.group(3)}</t></is></c>',
          )
          .replaceAllMapped(
            RegExp(r'<c(\s+[^>]*?)\s+t="str"([^>]*)\s*/>'),
            (match) =>
                '<c${match.group(1)} t="inlineStr"${match.group(2)}>'
                '<is><t></t></is></c>',
          );
    }
    return normalized == xml ? null : normalized;
  }
}

class WorkbookImportState {
  const WorkbookImportState({
    this.isPicking = false,
    this.isLoadingGoogleSheet = false,
    this.loadingMessage,
    this.loadingProgress,
    this.error,
    this.analysis,
    this.source,
    this.selectedImporterIds = const {},
    this.isConfirmed = false,
    this.lastImportSessionId,
  });

  final bool isPicking;
  final bool isLoadingGoogleSheet;
  final String? loadingMessage;
  final double? loadingProgress;
  final String? error;
  final WorkbookImportAnalysis? analysis;
  final WorkbookSource? source;
  final Set<String> selectedImporterIds;
  final bool isConfirmed;
  final String? lastImportSessionId;

  WorkbookImportState copyWith({
    bool? isPicking,
    bool? isLoadingGoogleSheet,
    String? loadingMessage,
    double? loadingProgress,
    String? error,
    WorkbookImportAnalysis? analysis,
    WorkbookSource? source,
    Set<String>? selectedImporterIds,
    bool? isConfirmed,
    String? lastImportSessionId,
  }) => WorkbookImportState(
    isPicking: isPicking ?? this.isPicking,
    isLoadingGoogleSheet: isLoadingGoogleSheet ?? this.isLoadingGoogleSheet,
    loadingMessage: loadingMessage,
    loadingProgress: loadingProgress,
    error: error,
    analysis: analysis ?? this.analysis,
    source: source ?? this.source,
    selectedImporterIds: selectedImporterIds ?? this.selectedImporterIds,
    isConfirmed: isConfirmed ?? this.isConfirmed,
    lastImportSessionId: lastImportSessionId ?? this.lastImportSessionId,
  );
}

class WorkbookImportController extends Notifier<WorkbookImportState> {
  @override
  WorkbookImportState build() => const WorkbookImportState();

  Future<void> chooseWorkbook() async {
    state = const WorkbookImportState(isPicking: true);
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (selection == null) {
        state = const WorkbookImportState();
        return;
      }
      final file = selection.files.single;
      if (file.bytes == null) {
        throw const FormatException(
          'Le fichier selectionne ne peut pas etre lu.',
        );
      }
      await _analyzeWorkbook(
        file.name,
        file.bytes!,
        source: WorkbookSource.local(fileName: file.name, path: file.path),
      );
    } on FormatException catch (error) {
      state = WorkbookImportState(error: error.message);
    } catch (_) {
      state = const WorkbookImportState(
        error:
            'Lecture du fichier impossible. Selectionnez un fichier Excel .xlsx valide.',
      );
    }
  }

  Future<void> loadGoogleSheet(String source) async {
    state = state.copyWith(
      isLoadingGoogleSheet: true,
      loadingMessage: 'Connexion a Google Sheets...',
      loadingProgress: null,
      isConfirmed: false,
    );
    try {
      final workbook = await GoogleSheetsWorkbookLoader().download(
        source,
        onProgress: (received, total) {
          state = state.copyWith(
            isLoadingGoogleSheet: true,
            loadingMessage: total == null
                ? 'Telechargement du Google Sheet en cours...'
                : 'Telechargement : ${(received / total * 100).round()} %',
            loadingProgress: total == null ? null : received / total,
          );
        },
      );
      state = state.copyWith(
        isLoadingGoogleSheet: true,
        loadingMessage: 'Fichier recu. Analyse des onglets en cours...',
        loadingProgress: null,
      );
      await _analyzeWorkbook(
        workbook.fileName,
        workbook.bytes,
        source: WorkbookSource.google(
          fileName: workbook.fileName,
          googleUrl: source,
        ),
      );
    } on FormatException catch (error) {
      state = WorkbookImportState(error: error.message);
    } catch (_) {
      state = const WorkbookImportState(
        error:
            'Impossible de lire ce Google Sheet. Verifiez le lien et son partage, puis reessayez.',
      );
    }
  }

  Future<void> _analyzeWorkbook(
    String fileName,
    Uint8List bytes, {
    required WorkbookSource source,
  }) async {
    final expectedEnvelopes = await SourceEnvelopeImport.loadEnvelopeNames();
    state = state.copyWith(
      loadingMessage: 'Analyse du classeur en cours...',
      loadingProgress: null,
    );
    final analysis = await WorkbookImportEngine.analyzeInBackground(
      fileName: fileName,
      bytes: bytes,
      expectedEnvelopeNames: expectedEnvelopes,
    );
    state = WorkbookImportState(analysis: analysis, source: source);
  }

  /// Re-reads the exact source immediately before execution. Google Sheets is
  /// downloaded again; a source which cannot be reread is intentionally
  /// blocked rather than guessed from preview bytes.
  Future<SourceFingerprintCheck> verifyConfirmedSource(String fingerprint) =>
      checkSource(state.source, fingerprint);

  static Future<SourceFingerprintCheck> checkSource(
    WorkbookSource? source,
    String fingerprint,
  ) async {
    if (source == null) {
      return const SourceFingerprintCheck.blocked(
        'SOURCE INACCESSIBLE — nouvelle analyse nécessaire.',
      );
    }
    try {
      final bytes = await source.reread();
      return fingerprintCheck(bytes, fingerprint);
    } on Object {
      return const SourceFingerprintCheck.blocked(
        'SOURCE INACCESSIBLE — nouvelle analyse nécessaire.',
      );
    }
  }

  static SourceFingerprintCheck fingerprintCheck(
    Uint8List bytes,
    String confirmedFingerprint,
  ) {
    final current = sha256.convert(bytes).toString();
    if (current != confirmedFingerprint) {
      return const SourceFingerprintCheck.blocked(
        'SOURCE MODIFIÉE DEPUIS LA CONFIRMATION — nouvelle analyse nécessaire.',
      );
    }
    return const SourceFingerprintCheck.match();
  }

  void confirmAnalysis() {
    final analysis = state.analysis;
    if (analysis == null ||
        !analysis.canConfirmSelection(state.selectedImporterIds)) {
      return;
    }
    state = state.copyWith(isConfirmed: true);
  }

  void toggleSheet(String importerId, bool selected) {
    final selection = {...state.selectedImporterIds};
    if (selected) {
      selection.add(importerId);
    } else {
      selection.remove(importerId);
    }
    state = state.copyWith(
      selectedImporterIds: Set.unmodifiable(selection),
      isConfirmed: false,
    );
  }

  void selectOnlyValidSheets() {
    final analysis = state.analysis;
    if (analysis == null) {
      return;
    }
    state = state.copyWith(
      selectedImporterIds: Set.unmodifiable(
        analysis.sheetPreviews
            .where((preview) => preview.canBeConfirmed)
            .map((preview) => preview.importerId),
      ),
      isConfirmed: false,
    );
  }

  void selectAllSheets() {
    final analysis = state.analysis;
    if (analysis == null) {
      return;
    }
    state = state.copyWith(
      selectedImporterIds: Set.unmodifiable(
        analysis.sheetPreviews.map((preview) => preview.importerId),
      ),
      isConfirmed: false,
    );
  }

  void registerCompletedImport(String importSessionId) {
    state = state.copyWith(lastImportSessionId: importSessionId);
  }

  void clearLastImport() {
    state = WorkbookImportState(
      analysis: state.analysis,
      selectedImporterIds: state.selectedImporterIds,
    );
  }

  /// Discards only local preview/selection state. It never affects an import
  /// already materialised in Supabase.
  void abandonPreparation() {
    state = const WorkbookImportState();
  }
}

String _normalize(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll('é', 'e')
    .replaceAll('è', 'e')
    .replaceAll('ê', 'e')
    .replaceAll('à', 'a')
    .replaceAll('â', 'a')
    .replaceAll('î', 'i')
    .replaceAll('ô', 'o')
    .replaceAll('ù', 'u')
    .replaceAll(RegExp(r'\s+'), ' ');

List<String> _rowValues(List<Data?> row) =>
    row.map((cell) => cell?.value?.toString() ?? '').toList(growable: false);

String _journalCellValue(List<Data?> row, int index) {
  if (index >= row.length) return '';
  final value = row[index]?.value;
  if (value == null) return '';
  // Never stringify an unused Journal formula. Formulas in one of the four
  // documented Journal fields retain their source expression, as before.
  return (value is FormulaCellValue ? value.formula : value.toString()).trim();
}

Map<Object?, Object?> _backgroundMap(Object? value) =>
    Map<Object?, Object?>.from(value! as Map);

List<Object?> _backgroundList(Object? value) =>
    List<Object?>.from(value! as List);

String _cell(List<String> values, int index) =>
    index < values.length ? values[index].trim() : '';

num? _parseAmount(String raw) =>
    num.tryParse(raw.replaceAll(' ', '').replaceAll(',', '.'));

bool _isAmountOrFormula(String raw) =>
    _parseAmount(raw) != null ||
    raw.contains('!') ||
    raw.contains('(') ||
    raw.startsWith('=');

ImportProblem _missingProblem(
  int rowNumber,
  String field,
  String explanation,
  String correctionHint,
) => ImportProblem(
  rowNumber: rowNumber,
  field: field,
  explanation: explanation,
  correctionHint: correctionHint,
);

Map<String, int> _headerIndexes(Sheet sheet, int headerRow) {
  if (sheet.rows.length < headerRow) return const {};
  final headers = _rowValues(sheet.rows[headerRow - 1]);
  return {
    for (var index = 0; index < headers.length; index++)
      _normalize(headers[index]): index,
  };
}

SheetImportPreview _missingHeadersPreview(
  String importerId,
  String sourceSheetName,
  List<String> missingHeaders,
) => SheetImportPreview(
  importerId: importerId,
  sourceSheetName: sourceSheetName,
  detectedRecords: 0,
  issues: [
    ImportIssue(
      severity: ImportIssueSeverity.blocking,
      message: 'Colonnes obligatoires absentes : ${missingHeaders.join(', ')}',
    ),
  ],
);

SourceSheetSnapshot _snapshotSheet(String sourceSheetName, Sheet sheet) {
  final cells = <SourceCellSnapshot>[];
  for (final row in sheet.rows) {
    for (final cell in row) {
      final value = cell?.value;
      if (value == null) {
        continue;
      }
      cells.add(
        SourceCellSnapshot(
          coordinate: cell!.cellIndex.cellId,
          value: value.toString(),
          formula: value is FormulaCellValue ? value.formula : null,
        ),
      );
    }
  }
  return SourceSheetSnapshot(sourceSheetName: sourceSheetName, cells: cells);
}
