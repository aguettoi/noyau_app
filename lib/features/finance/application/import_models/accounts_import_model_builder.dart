import '../accounts_csv_business_validator.dart';
import '../csv_import_validation_pipeline.dart';
import 'import_account.dart';

class AccountsImportModelBuilder {
  List<ImportAccount> build(CsvImportValidationResult validationResult) {
    if (!validationResult.isValid ||
        validationResult.stage != CsvImportValidationStage.valid) {
      throw StateError(
        'Le résultat de validation doit être valide avant de construire les comptes à importer.',
      );
    }

    final businessResult = validationResult.accountsBusinessResult;
    final parsedRows = validationResult.parsedRows;
    if (businessResult == null || parsedRows == null || parsedRows.isEmpty) {
      throw StateError('Les données validées des comptes sont indisponibles.');
    }

    final indexes = <String, int>{
      for (var index = 0; index < parsedRows.first.length; index++)
        parsedRows.first[index].trim().toLowerCase(): index,
    };
    final accounts = businessResult.rows.map((rowResult) {
      final sourceIndex = rowResult.lineNumber - 1;
      if (sourceIndex < 0 || sourceIndex >= parsedRows.length) {
        throw StateError(
          'La ligne source ${rowResult.lineNumber} est indisponible.',
        );
      }
      final row = parsedRows[sourceIndex];
      final name = _value(row, indexes, 'nom');
      final type = AccountsCsvBusinessValidator.accountTypeFromCsv(
        _value(row, indexes, 'type'),
      );
      if (type == null) {
        throw StateError('Le type de compte validé est indisponible.');
      }
      return ImportAccount(
        name: name,
        type: type,
        openingBalanceCents: rowResult.initialBalanceCents,
      );
    });
    return List.unmodifiable(accounts);
  }

  static String _value(
    List<String> row,
    Map<String, int> indexes,
    String column,
  ) {
    final index = indexes[column];
    if (index == null || index >= row.length) {
      throw StateError("La colonne '$column' est indisponible.");
    }
    return row[index].trim();
  }
}
