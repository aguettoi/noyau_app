import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/accounts_csv_business_validator.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';
import 'package:noyau_app/features/finance/application/csv_import_validation_pipeline.dart';
import 'package:noyau_app/features/finance/application/csv_structure_validator.dart';

void main() {
  final accounts = byType(ImportTemplateType.accounts);
  final envelopes = byType(ImportTemplateType.envelopes);
  const parsedRows = <List<String>>[
    ['nom', 'type'],
    ['Compte courant', 'bank'],
  ];
  const validStructure = CsvStructureValidationResult([]);
  const invalidStructure = CsvStructureValidationResult([
    'Structure invalide.',
  ]);
  const validBusiness = AccountsCsvBusinessValidationResult(
    rows: [],
    errors: [],
  );
  const invalidBusiness = AccountsCsvBusinessValidationResult(
    rows: [],
    errors: ['Donnée invalide.'],
  );

  CsvImportValidationPipeline pipeline({
    CsvTextParse? parser,
    CsvStructureValidation? structure,
    AccountsCsvBusinessValidation? business,
  }) => CsvImportValidationPipeline(
    parseCsvText: parser ?? (_) => parsedRows,
    validateStructure:
        structure ?? ({required rows, required template}) => validStructure,
    validateAccountsBusiness:
        business ?? ({required rows, required template}) => validBusiness,
  );

  test('le parseur reçoit exactement le texte fourni', () {
    String? received;
    pipeline(
      parser: (text) {
        received = text;
        return parsedRows;
      },
    ).validate(csvText: 'texte exact', template: accounts);
    expect(received, 'texte exact');
  });

  test('une erreur de parsing arrête le pipeline', () {
    var structureCalls = 0;
    var businessCalls = 0;
    final result = pipeline(
      parser: (_) => throw const FormatException('invalide'),
      structure: ({required rows, required template}) {
        structureCalls++;
        return validStructure;
      },
      business: ({required rows, required template}) {
        businessCalls++;
        return validBusiness;
      },
    ).validate(csvText: 'x', template: accounts);

    expect(result.stage, CsvImportValidationStage.parsingFailed);
    expect(result.parsedRows, isNull);
    expect(result.errors.single, startsWith('Erreur de parsing :'));
    expect(structureCalls, 0);
    expect(businessCalls, 0);
  });

  test('le validateur structurel reçoit les lignes et le template exacts', () {
    List<List<String>>? receivedRows;
    CsvImportTemplateDefinition? receivedTemplate;
    pipeline(
      structure: ({required rows, required template}) {
        receivedRows = rows;
        receivedTemplate = template;
        return validStructure;
      },
    ).validate(csvText: 'x', template: accounts);
    expect(receivedRows, same(parsedRows));
    expect(receivedTemplate, same(accounts));
  });

  test('une structure invalide arrête le pipeline et conserve les erreurs', () {
    var businessCalls = 0;
    final result = pipeline(
      structure: ({required rows, required template}) => invalidStructure,
      business: ({required rows, required template}) {
        businessCalls++;
        return validBusiness;
      },
    ).validate(csvText: 'x', template: accounts);

    expect(result.stage, CsvImportValidationStage.structureInvalid);
    expect(result.parsedRows, same(parsedRows));
    expect(result.structureResult, same(invalidStructure));
    expect(result.errors, invalidStructure.errors);
    expect(businessCalls, 0);
  });

  test(
    'le validateur métier Comptes reçoit les lignes et le template exacts',
    () {
      List<List<String>>? receivedRows;
      CsvImportTemplateDefinition? receivedTemplate;
      pipeline(
        business: ({required rows, required template}) {
          receivedRows = rows;
          receivedTemplate = template;
          return validBusiness;
        },
      ).validate(csvText: 'x', template: accounts);
      expect(receivedRows, same(parsedRows));
      expect(receivedTemplate, same(accounts));
    },
  );

  test(
    'des données métier invalides retournent businessInvalid et leurs erreurs',
    () {
      final result = pipeline(
        business: ({required rows, required template}) => invalidBusiness,
      ).validate(csvText: 'x', template: accounts);

      expect(result.stage, CsvImportValidationStage.businessInvalid);
      expect(result.accountsBusinessResult, same(invalidBusiness));
      expect(result.errors, invalidBusiness.errors);
    },
  );

  test('un CSV Comptes valide retourne tous ses résultats', () {
    final result = pipeline().validate(csvText: 'x', template: accounts);

    expect(result.stage, CsvImportValidationStage.valid);
    expect(result.isValid, isTrue);
    expect(result.parsedRows, same(parsedRows));
    expect(result.structureResult, same(validStructure));
    expect(result.accountsBusinessResult, same(validBusiness));
    expect(result.errors, isEmpty);
  });

  test('un template non pris en charge ne lance pas le validateur Comptes', () {
    var businessCalls = 0;
    final result = pipeline(
      business: ({required rows, required template}) {
        businessCalls++;
        return validBusiness;
      },
    ).validate(csvText: 'x', template: envelopes);

    expect(result.stage, CsvImportValidationStage.unsupportedTemplate);
    expect(result.isValid, isFalse);
    expect(result.parsedRows, same(parsedRows));
    expect(result.structureResult, same(validStructure));
    expect(result.accountsBusinessResult, isNull);
    expect(result.errors, const [
      'La validation métier de ce template n’est pas encore disponible.',
    ]);
    expect(businessCalls, 0);
  });

  test('une exception structurelle inattendue ne se propage pas', () {
    final result = pipeline(
      structure: ({required rows, required template}) =>
          throw StateError('erreur'),
    ).validate(csvText: 'x', template: accounts);

    expect(result.stage, CsvImportValidationStage.structureInvalid);
    expect(
      result.errors.single,
      startsWith('Erreur de validation de la structure :'),
    );
  });

  test('une exception métier inattendue ne se propage pas', () {
    final result = pipeline(
      business: ({required rows, required template}) =>
          throw StateError('erreur'),
    ).validate(csvText: 'x', template: accounts);

    expect(result.stage, CsvImportValidationStage.businessInvalid);
    expect(result.errors.single, startsWith('Erreur de validation métier :'));
  });

  test('l’ordre parsing puis structure puis métier est respecté', () {
    final calls = <String>[];
    pipeline(
      parser: (_) {
        calls.add('parsing');
        return parsedRows;
      },
      structure: ({required rows, required template}) {
        calls.add('structure');
        return validStructure;
      },
      business: ({required rows, required template}) {
        calls.add('métier');
        return validBusiness;
      },
    ).validate(csvText: 'x', template: accounts);
    expect(calls, ['parsing', 'structure', 'métier']);
  });
}
