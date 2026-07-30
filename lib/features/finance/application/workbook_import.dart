import 'dart:typed_data';

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

class ImportIssue {
  const ImportIssue({required this.severity, required this.message});

  final ImportIssueSeverity severity;
  final String message;
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
    if (sheet.rows.length < headerRow) {
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

    final headers = _rowValues(sheet.rows[headerRow - 1]);
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

    for (var rowIndex = headerRow; rowIndex < sheet.rows.length; rowIndex++) {
      final row = sheet.rows[rowIndex];
      final values = _rowValues(row);
      if (values.every((value) => value.trim().isEmpty)) {
        continue;
      }
      records++;
      final rowNumber = rowIndex + 1;
      if (_cell(values, dateIndex).isEmpty) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Date',
            'Cette depense ou alimentation n a pas de date.',
            'Saisissez une date dans la colonne Date.',
          ),
        );
      }
      final envelope = _cell(values, envelopeIndex);
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
      if (_parseAmount(_cell(values, amountIndex)) == null) {
        problems.add(
          _missingProblem(
            rowNumber,
            'Montant',
            'Le montant doit etre un nombre positif ou negatif.',
            'Saisissez par exemple 250 ou -250, sans texte.',
          ),
        );
      }
      if (_cell(values, detailIndex).isEmpty) {
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
      unhandledSheetNames.isEmpty &&
      sheetPreviews.every((preview) => preview.canBeConfirmed);

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
      unhandledSheetNames.isEmpty &&
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
    final workbook = Excel.decodeBytes(bytes);
    final previews = <SheetImportPreview>[];
    final handledNames = <String>{};
    final sourceSheets = <SourceSheetSnapshot>[];

    for (var index = 0; index < _importers.length; index++) {
      final importer = _importers[index];
      final sheet = workbook.tables[importer.sourceSheetName];
      if (sheet == null) {
        previews.add(
          SheetImportPreview(
            importerId: importer.id,
            sourceSheetName: importer.sourceSheetName,
            detectedRecords: 0,
            issues: const [
              ImportIssue(
                severity: ImportIssueSeverity.blocking,
                message: 'Onglet source introuvable.',
              ),
            ],
          ),
        );
        onProgress?.call(index + 1, _importers.length);
        continue;
      }
      handledNames.add(importer.sourceSheetName);
      previews.add(await importer.analyze(sheet));
      sourceSheets.add(_snapshotSheet(importer.sourceSheetName, sheet));
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
}

class WorkbookImportState {
  const WorkbookImportState({
    this.isPicking = false,
    this.isLoadingGoogleSheet = false,
    this.loadingMessage,
    this.loadingProgress,
    this.error,
    this.analysis,
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
      await _analyzeWorkbook(file.name, file.bytes!);
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
      await _analyzeWorkbook(workbook.fileName, workbook.bytes);
    } on FormatException catch (error) {
      state = WorkbookImportState(error: error.message);
    } catch (_) {
      state = const WorkbookImportState(
        error:
            'Impossible de lire ce Google Sheet. Verifiez le lien et son partage, puis reessayez.',
      );
    }
  }

  Future<void> _analyzeWorkbook(String fileName, Uint8List bytes) async {
    final expectedEnvelopes = await SourceEnvelopeImport.loadEnvelopeNames();
    final analysis =
        await WorkbookImportEngine(
          DefaultWorkbookImportRegistry.create(expectedEnvelopes),
        ).analyze(
          fileName: fileName,
          bytes: bytes,
          onProgress: (completed, total) {
            state = state.copyWith(
              loadingMessage: 'Analyse des onglets : $completed / $total',
              loadingProgress: completed / total,
            );
          },
        );
    state = WorkbookImportState(analysis: analysis);
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
