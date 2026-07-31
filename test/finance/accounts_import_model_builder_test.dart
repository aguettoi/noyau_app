import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/accounts_csv_business_validator.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';
import 'package:noyau_app/features/finance/application/csv_import_validation_pipeline.dart';
import 'package:noyau_app/features/finance/application/import_models/accounts_import_model_builder.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';

void main() {
  final builder = AccountsImportModelBuilder();
  final template = byType(ImportTemplateType.accounts);

  CsvImportValidationResult validResult({
    required List<List<String>> dataRows,
    required List<int?> balances,
  }) {
    final parsedRows = [template.columns, ...dataRows];
    return CsvImportValidationResult(
      stage: CsvImportValidationStage.valid,
      isValid: true,
      parsedRows: parsedRows,
      accountsBusinessResult: AccountsCsvBusinessValidationResult(
        rows: List.generate(
          balances.length,
          (index) => AccountsCsvRowValidationResult(
            lineNumber: index + 2,
            errors: const [],
            initialBalanceCents: balances[index],
          ),
        ),
        errors: const [],
      ),
      errors: const [],
    );
  }

  List<String> account(String name, String type) => [
    '',
    name,
    type,
    '',
    'actif',
    '',
    '',
  ];

  test('construction d’un compte valide', () {
    final accounts = builder.build(
      validResult(dataRows: [account('Compte courant', 'bank')], balances: [0]),
    );

    expect(accounts, hasLength(1));
    expect(accounts.single.name, 'Compte courant');
  });

  test('construction de plusieurs comptes', () {
    final accounts = builder.build(
      validResult(
        dataRows: [
          account('Compte courant', 'bank'),
          account('Épargne', 'savings'),
        ],
        balances: [0, 250000],
      ),
    );

    expect(accounts, hasLength(2));
  });

  test('openingBalanceCents null est conservé', () {
    final accounts = builder.build(
      validResult(dataRows: [account('Compte', 'bank')], balances: [null]),
    );
    expect(accounts.single.openingBalanceCents, isNull);
  });

  test('openingBalanceCents positif est conservé', () {
    final accounts = builder.build(
      validResult(dataRows: [account('Compte', 'bank')], balances: [12550]),
    );
    expect(accounts.single.openingBalanceCents, 12550);
  });

  test('openingBalanceCents négatif est conservé', () {
    final accounts = builder.build(
      validResult(dataRows: [account('Compte', 'bank')], balances: [-2575]),
    );
    expect(accounts.single.openingBalanceCents, -2575);
  });

  test('FinancialAccountType est conservé', () {
    final accounts = builder.build(
      validResult(dataRows: [account('Espèces', 'cash')], balances: [0]),
    );
    expect(accounts.single.type, FinancialAccountType.cash);
  });

  test('nom est conservé', () {
    final accounts = builder.build(
      validResult(
        dataRows: [account('Épargne foyer', 'savings')],
        balances: [0],
      ),
    );
    expect(accounts.single.name, 'Épargne foyer');
  });

  test('ordre des comptes est conservé', () {
    final accounts = builder.build(
      validResult(
        dataRows: [account('Premier', 'bank'), account('Second', 'cash')],
        balances: [0, 0],
      ),
    );
    expect(accounts.map((account) => account.name), ['Premier', 'Second']);
  });

  test('validation invalide lance StateError', () {
    final invalid = CsvImportValidationResult(
      stage: CsvImportValidationStage.businessInvalid,
      isValid: false,
      errors: const ['Erreur'],
    );
    expect(() => builder.build(invalid), throwsStateError);
  });

  test('stage différent de valid lance StateError', () {
    final invalidStage = CsvImportValidationResult(
      stage: CsvImportValidationStage.structureInvalid,
      isValid: true,
      errors: const [],
    );
    expect(() => builder.build(invalidStage), throwsStateError);
  });

  test('liste vide retourne liste vide', () {
    final accounts = builder.build(
      validResult(dataRows: const [], balances: const []),
    );
    expect(accounts, isEmpty);
  });

  test('aucune modification des objets source', () {
    final dataRows = [account('Compte courant', 'bank')];
    final validationResult = validResult(dataRows: dataRows, balances: [0]);
    final originalRows = validationResult.parsedRows!
        .map(List<String>.from)
        .toList(growable: false);

    builder.build(validationResult);

    expect(validationResult.parsedRows, originalRows);
  });
}
