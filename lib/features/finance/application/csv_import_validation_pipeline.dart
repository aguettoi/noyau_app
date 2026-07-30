import 'accounts_csv_business_validator.dart';
import 'csv_import_templates.dart';
import 'csv_structure_validator.dart';
import 'csv_text_parser.dart';

typedef CsvTextParse = List<List<String>> Function(String csvText);
typedef CsvStructureValidation =
    CsvStructureValidationResult Function({
      required List<List<String>> rows,
      required CsvImportTemplateDefinition template,
    });
typedef AccountsCsvBusinessValidation =
    AccountsCsvBusinessValidationResult Function({
      required List<List<String>> rows,
      required CsvImportTemplateDefinition template,
    });

enum CsvImportValidationStage {
  parsingFailed,
  structureInvalid,
  businessInvalid,
  valid,
  unsupportedTemplate,
}

class CsvImportValidationResult {
  const CsvImportValidationResult({
    required this.stage,
    required this.isValid,
    required this.errors,
    this.parsedRows,
    this.structureResult,
    this.accountsBusinessResult,
  });

  final CsvImportValidationStage stage;
  final bool isValid;
  final List<List<String>>? parsedRows;
  final CsvStructureValidationResult? structureResult;
  final AccountsCsvBusinessValidationResult? accountsBusinessResult;
  final List<String> errors;
}

class CsvImportValidationPipeline {
  CsvImportValidationPipeline({
    CsvTextParse? parseCsvText,
    CsvStructureValidation? validateStructure,
    AccountsCsvBusinessValidation? validateAccountsBusiness,
  }) : _parseCsvText = parseCsvText ?? CsvTextParser().parse,
       _validateStructure =
           validateStructure ?? CsvStructureValidator().validate,
       _validateAccountsBusiness =
           validateAccountsBusiness ?? AccountsCsvBusinessValidator().validate;

  final CsvTextParse _parseCsvText;
  final CsvStructureValidation _validateStructure;
  final AccountsCsvBusinessValidation _validateAccountsBusiness;

  CsvImportValidationResult validate({
    required String csvText,
    required CsvImportTemplateDefinition template,
  }) {
    late final List<List<String>> parsedRows;
    try {
      parsedRows = _parseCsvText(csvText);
    } catch (error) {
      return _failure(
        CsvImportValidationStage.parsingFailed,
        'Erreur de parsing : $error',
      );
    }

    late final CsvStructureValidationResult structureResult;
    try {
      structureResult = _validateStructure(
        rows: parsedRows,
        template: template,
      );
    } catch (error) {
      return _failure(
        CsvImportValidationStage.structureInvalid,
        'Erreur de validation de la structure : $error',
        parsedRows: parsedRows,
      );
    }
    if (!structureResult.isValid) {
      return CsvImportValidationResult(
        stage: CsvImportValidationStage.structureInvalid,
        isValid: false,
        parsedRows: parsedRows,
        structureResult: structureResult,
        errors: structureResult.errors,
      );
    }

    if (template.type != ImportTemplateType.accounts) {
      return CsvImportValidationResult(
        stage: CsvImportValidationStage.unsupportedTemplate,
        isValid: false,
        parsedRows: parsedRows,
        structureResult: structureResult,
        errors: const [
          'La validation métier de ce template n’est pas encore disponible.',
        ],
      );
    }

    late final AccountsCsvBusinessValidationResult businessResult;
    try {
      businessResult = _validateAccountsBusiness(
        rows: parsedRows,
        template: template,
      );
    } catch (error) {
      return _failure(
        CsvImportValidationStage.businessInvalid,
        'Erreur de validation métier : $error',
        parsedRows: parsedRows,
        structureResult: structureResult,
      );
    }
    if (!businessResult.isValid) {
      return CsvImportValidationResult(
        stage: CsvImportValidationStage.businessInvalid,
        isValid: false,
        parsedRows: parsedRows,
        structureResult: structureResult,
        accountsBusinessResult: businessResult,
        errors: businessResult.errors,
      );
    }

    return CsvImportValidationResult(
      stage: CsvImportValidationStage.valid,
      isValid: true,
      parsedRows: parsedRows,
      structureResult: structureResult,
      accountsBusinessResult: businessResult,
      errors: const [],
    );
  }

  CsvImportValidationResult _failure(
    CsvImportValidationStage stage,
    String error, {
    List<List<String>>? parsedRows,
    CsvStructureValidationResult? structureResult,
  }) => CsvImportValidationResult(
    stage: stage,
    isValid: false,
    parsedRows: parsedRows,
    structureResult: structureResult,
    errors: [error],
  );
}
