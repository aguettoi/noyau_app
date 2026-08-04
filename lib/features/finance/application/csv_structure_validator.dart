import 'csv_import_templates.dart';

class CsvStructureValidationResult {
  const CsvStructureValidationResult(this.errors);

  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

class CsvStructureValidator {
  CsvStructureValidationResult validate({
    required List<List<String>> rows,
    required CsvImportTemplateDefinition template,
  }) {
    if (rows.isEmpty) {
      return const CsvStructureValidationResult(['Le fichier est vide.']);
    }

    final header = rows.first;
    if (_isBlankRow(header)) {
      return const CsvStructureValidationResult([
        "La ligne d'en-tête est absente.",
      ]);
    }

    final normalizedHeader = header.map(_normalizeColumnName).toList();
    final errors = <String>[];
    final seenColumns = <String>{};

    for (var index = 0; index < normalizedHeader.length; index++) {
      final column = normalizedHeader[index];
      if (!seenColumns.add(column)) {
        errors.add(
          "La colonne '${_displayColumnName(header[index])}' apparaît plusieurs fois.",
        );
      }
    }

    for (final expectedColumn in template.columns) {
      if (template.optionalColumns
          .map(_normalizeColumnName)
          .contains(_normalizeColumnName(expectedColumn))) {
        continue;
      }
      if (!seenColumns.contains(_normalizeColumnName(expectedColumn))) {
        errors.add(
          "La colonne '${_displayColumnName(expectedColumn)}' est manquante.",
        );
      }
    }

    for (var index = 1; index < rows.length; index++) {
      final row = rows[index];
      if (_isBlankRow(row)) {
        continue;
      }
      if (row.length != header.length) {
        errors.add(
          'La ligne ${index + 1} contient ${row.length} colonnes au lieu de ${header.length}.',
        );
      }
    }

    return CsvStructureValidationResult(List.unmodifiable(errors));
  }

  static bool _isBlankRow(List<String> row) =>
      row.isEmpty || row.every((cell) => cell.trim().isEmpty);

  static String _normalizeColumnName(String value) =>
      value.trim().toLowerCase();

  static String _displayColumnName(String value) {
    final words = value.trim().split('_');
    return words
        .map(
          (word) => word.isEmpty
              ? word
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }
}
