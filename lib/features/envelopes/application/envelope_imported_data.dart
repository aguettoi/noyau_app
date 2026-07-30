import '../../../core/money/money.dart';
import '../../finance/application/workbook_import.dart';
import '../domain/envelope_reporting.dart';

class ImportedEnvelopeBalance {
  const ImportedEnvelopeBalance({required this.name, required this.balance});

  final String name;
  final Money balance;
}

class ImportedEnvelopeData {
  const ImportedEnvelopeData({
    required this.balances,
    required this.totalFunds,
    required this.importedMovements,
  });

  final List<ImportedEnvelopeBalance> balances;
  final Money totalFunds;
  final int importedMovements;
}

/// Reads the real Enveloppes and Journal values kept in a confirmed source
/// snapshot. Formulas are deliberately not trusted: the same signed Journal
/// lines are recalculated in Dart, exactly as in the source sheet.
class EnvelopeImportedDataReader {
  const EnvelopeImportedDataReader({
    this.calculator = const EnvelopeReportCalculator(),
  });

  final EnvelopeReportCalculator calculator;

  ImportedEnvelopeData? read(WorkbookImportAnalysis analysis) {
    final envelopeSheet = _findSheet(analysis, 'Enveloppes');
    final journalSheet = _findSheet(analysis, 'Journal');
    if (envelopeSheet == null || journalSheet == null) return null;

    final envelopeNames = _readEnvelopeNames(envelopeSheet);
    if (envelopeNames.isEmpty) return null;
    final movements = _readJournalMovements(journalSheet, envelopeNames);
    final balances = calculator.balancesByEnvelope(movements);
    return ImportedEnvelopeData(
      balances: envelopeNames
          .map(
            (name) => ImportedEnvelopeBalance(
              name: name,
              balance:
                  balances[_normalize(name)] ?? const Money.fromMinorUnits(0),
            ),
          )
          .toList(growable: false),
      totalFunds: calculator.totalEnvelopeFunds(movements),
      importedMovements: movements.length,
    );
  }

  SourceSheetSnapshot? _findSheet(
    WorkbookImportAnalysis analysis,
    String sourceSheetName,
  ) {
    for (final sheet in analysis.sourceSheets) {
      if (_normalize(sheet.sourceSheetName) == _normalize(sourceSheetName)) {
        return sheet;
      }
    }
    return null;
  }

  List<String> _readEnvelopeNames(SourceSheetSnapshot sheet) {
    final cells = _cellsByCoordinate(sheet);
    final names = <String>[];
    // The source table begins in B17 and contains exactly the 25 household
    // envelopes. Keeping this explicit prevents unrelated labels elsewhere in
    // the dashboard from accidentally becoming envelopes.
    for (var row = 17; row <= 41; row++) {
      final name = cells['B$row']?.trim() ?? '';
      if (name.isNotEmpty) names.add(name);
    }
    return names;
  }

  List<EnvelopeMovement> _readJournalMovements(
    SourceSheetSnapshot sheet,
    List<String> envelopeNames,
  ) {
    final rows = _rows(sheet);
    final knownNames = {
      _forComparison(envelopeNames.first): envelopeNames.first,
    };
    for (final name in envelopeNames.skip(1)) {
      knownNames[_forComparison(name)] = name;
    }

    final headerRow = rows.entries
        .where(
          (entry) => entry.value.values.any(
            (value) => _normalize(value) == 'enveloppe',
          ),
        )
        .map((entry) => entry.key)
        .cast<int?>()
        .firstWhere((row) => row != null, orElse: () => null);
    if (headerRow == null) return const [];

    final headers = rows[headerRow]!;
    final envelopeColumn = _columnFor(headers, 'enveloppe');
    final amountColumn = _columnFor(
      headers,
      'montant (negatif : depense ; positif : alimentation)',
    );
    final dateColumn = _columnFor(headers, 'date');
    if (envelopeColumn == null || amountColumn == null) return const [];

    final movements = <EnvelopeMovement>[];
    for (final entry in rows.entries) {
      if (entry.key <= headerRow) continue;
      final rawEnvelope = entry.value[envelopeColumn];
      final amount = _parseAmount(entry.value[amountColumn]);
      final canonicalName = rawEnvelope == null
          ? null
          : knownNames[_forComparison(rawEnvelope)];
      if (canonicalName == null || amount == null) continue;
      movements.add(
        EnvelopeMovement(
          envelopeId: _normalize(canonicalName),
          occurredAt: _parseDate(entry.value[dateColumn]) ?? DateTime(1970),
          amount: amount,
        ),
      );
    }
    return movements;
  }

  Map<String, String> _cellsByCoordinate(SourceSheetSnapshot sheet) => {
    for (final cell in sheet.cells) cell.coordinate.toUpperCase(): cell.value,
  };

  Map<int, Map<String, String>> _rows(SourceSheetSnapshot sheet) {
    final rows = <int, Map<String, String>>{};
    for (final cell in sheet.cells) {
      final match = RegExp(
        r'^([A-Z]+)([0-9]+)$',
      ).firstMatch(cell.coordinate.toUpperCase());
      if (match == null) continue;
      rows.putIfAbsent(int.parse(match.group(2)!), () => {})[match.group(1)!] =
          cell.value;
    }
    return rows;
  }

  String? _columnFor(Map<String, String> headers, String wanted) {
    for (final entry in headers.entries) {
      if (_normalize(entry.value) == wanted) return entry.key;
    }
    return null;
  }

  Money? _parseAmount(String? raw) {
    if (raw == null) return null;
    final normalized = raw
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll(',', '.');
    final value = num.tryParse(normalized);
    return value == null ? null : Money.fromDirhams(value);
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw);
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

String _forComparison(String value) => _normalize(value);
