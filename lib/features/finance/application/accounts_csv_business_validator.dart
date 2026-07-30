import '../domain/financial_account.dart';
import 'csv_import_templates.dart';

class AccountsCsvBusinessValidationResult {
  const AccountsCsvBusinessValidationResult({
    required this.rows,
    required this.errors,
  });

  final List<AccountsCsvRowValidationResult> rows;
  final List<String> errors;

  bool get isValid => errors.isEmpty;
}

class AccountsCsvRowValidationResult {
  const AccountsCsvRowValidationResult({
    required this.lineNumber,
    required this.errors,
    this.initialBalanceCents,
  });

  final int lineNumber;
  final List<String> errors;
  final int? initialBalanceCents;

  bool get isValid => errors.isEmpty;
}

class AccountsCsvBusinessValidator {
  AccountsCsvBusinessValidationResult validate({
    required List<List<String>> rows,
    required CsvImportTemplateDefinition template,
  }) {
    if (rows.isEmpty) {
      return const AccountsCsvBusinessValidationResult(rows: [], errors: []);
    }

    final indexes = <String, int>{
      for (var index = 0; index < rows.first.length; index++)
        _normalize(rows.first[index]): index,
    };
    final drafts = <_RowDraft>[];
    final names = <String, List<_RowDraft>>{};

    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      if (_isBlankRow(row)) {
        continue;
      }

      final draft = _RowDraft(lineNumber: rowIndex + 1);
      final name = _value(row, indexes, 'nom');
      final type = _value(row, indexes, 'type');
      final initialBalance = _value(row, indexes, 'solde_initial_centimes');

      if (name.isEmpty) {
        draft.errors.add(
          'La ligne ${draft.lineNumber} : le nom du compte est obligatoire.',
        );
      } else {
        names.putIfAbsent(_normalize(name), () => []).add(draft);
      }

      if (type.isEmpty) {
        draft.errors.add(
          'La ligne ${draft.lineNumber} : le type de compte est obligatoire.',
        );
      } else if (!_allowedAccountTypes.contains(_normalize(type))) {
        draft.errors.add(
          "La ligne ${draft.lineNumber} : le type de compte '$type' est invalide.",
        );
      }

      final amount = _parseAmountInCents(initialBalance);
      if (initialBalance.isNotEmpty && amount == null) {
        draft.errors.add(
          "La ligne ${draft.lineNumber} : le solde initial '$initialBalance' est invalide.",
        );
      }
      draft.initialBalanceCents = amount;
      drafts.add(draft);
    }

    for (final sameNameRows in names.values) {
      if (sameNameRows.length < 2) {
        continue;
      }
      for (final draft in sameNameRows) {
        final name = _value(rows[draft.lineNumber - 1], indexes, 'nom');
        draft.errors.add(
          "La ligne ${draft.lineNumber} : le compte '$name' est dupliqué dans le fichier.",
        );
      }
    }

    final results = drafts
        .map(
          (draft) => AccountsCsvRowValidationResult(
            lineNumber: draft.lineNumber,
            errors: List.unmodifiable(draft.errors),
            initialBalanceCents: draft.initialBalanceCents,
          ),
        )
        .toList(growable: false);
    final errors = results
        .expand((result) => result.errors)
        .toList(growable: false);
    return AccountsCsvBusinessValidationResult(rows: results, errors: errors);
  }

  static final Set<String> _allowedAccountTypes = FinancialAccountType.values
      .map((type) => type.name.toLowerCase())
      .toSet();

  static String _value(
    List<String> row,
    Map<String, int> indexes,
    String column,
  ) {
    final index = indexes[_normalize(column)];
    if (index == null || index >= row.length) {
      return '';
    }
    return row[index].trim();
  }

  static String _normalize(String value) => value.trim().toLowerCase();

  static bool _isBlankRow(List<String> row) =>
      row.isEmpty || row.every((value) => value.trim().isEmpty);

  static int? _parseAmountInCents(String value) {
    if (value.isEmpty || !RegExp(r'^-?\d+(?:[.,]\d{1,2})?$').hasMatch(value)) {
      return null;
    }
    final normalized = value.replaceAll(',', '.');
    final negative = normalized.startsWith('-');
    final unsigned = negative ? normalized.substring(1) : normalized;
    final parts = unsigned.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null) {
      return null;
    }
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts.last.padRight(2, '0'));
    final cents = (whole * 100) + fraction;
    return negative ? -cents : cents;
  }
}

class _RowDraft {
  _RowDraft({required this.lineNumber});

  final int lineNumber;
  final List<String> errors = [];
  int? initialBalanceCents;
}
