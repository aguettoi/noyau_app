import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/accounts_csv_business_validator.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';

void main() {
  final validator = AccountsCsvBusinessValidator();
  final template = byType(ImportTemplateType.accounts);
  final header = List<String>.from(template.columns);

  List<String> account({
    String name = 'Compte courant',
    String type = 'bank',
    String balance = '',
  }) => ['', name, type, '', 'actif', balance, ''];

  AccountsCsvBusinessValidationResult validate(List<List<String>> data) =>
      validator.validate(rows: [header, ...data], template: template);

  test('fichier Comptes métier valide', () {
    expect(validate([account(balance: '125')]).isValid, isTrue);
  });

  test('solde initial est optionnel dans le template Comptes', () {
    expect(template.optionalColumns, contains('solde_initial_centimes'));
  });

  test('nom vide refusé', () {
    expect(
      validate([account(name: '')]).errors,
      contains('La ligne 2 : le nom du compte est obligatoire.'),
    );
  });

  test('type de compte invalide refusé', () {
    expect(
      validate([account(type: 'XYZ')]).errors,
      contains("La ligne 2 : le type de compte 'XYZ' est invalide."),
    );
  });

  test('type accepté avec casse différente et espaces', () {
    expect(validate([account(type: '  BANK  ')]).isValid, isTrue);
  });

  test('solde entier valide et converti en centimes', () {
    expect(
      validate([account(balance: '125')]).rows.single.initialBalanceCents,
      12500,
    );
  });

  test('solde avec point valide et converti en centimes', () {
    expect(
      validate([account(balance: '125.50')]).rows.single.initialBalanceCents,
      12550,
    );
  });

  test('solde avec virgule valide et converti en centimes', () {
    expect(
      validate([account(balance: '125,50')]).rows.single.initialBalanceCents,
      12550,
    );
  });

  test('solde négatif valide et converti en centimes', () {
    expect(
      validate([account(balance: '-25.75')]).rows.single.initialBalanceCents,
      -2575,
    );
  });

  test('solde zéro valide', () {
    expect(
      validate([account(balance: '0')]).rows.single.initialBalanceCents,
      0,
    );
  });

  test('texte comme solde refusé', () {
    expect(validate([account(balance: 'abc')]).isValid, isFalse);
  });

  test('plusieurs séparateurs décimaux refusés', () {
    expect(validate([account(balance: '1.2.3')]).isValid, isFalse);
  });

  test('plus de deux décimales refusées', () {
    expect(validate([account(balance: '1.234')]).isValid, isFalse);
  });

  test('solde vide facultatif reste absent', () {
    final row = validate([account()]).rows.single;
    expect(row.isValid, isTrue);
    expect(row.initialBalanceCents, isNull);
  });

  test('initialBalanceCents vaut null lorsque le solde est invalide', () {
    expect(
      validate([account(balance: 'abc')]).rows.single.initialBalanceCents,
      isNull,
    );
  });

  test('deux noms identiques refusés', () {
    expect(validate([account(), account()]).isValid, isFalse);
  });

  test('doublon détecté malgré casse et espaces différents', () {
    expect(
      validate([account(), account(name: '  COMPTE COURANT  ')]).isValid,
      isFalse,
    );
  });

  test('les deux lignes dupliquées sont invalides', () {
    final result = validate([account(), account()]);
    expect(result.rows.every((row) => !row.isValid), isTrue);
  });

  test('ligne entièrement vide ignorée', () {
    final result = validate([
      account(),
      ['', '', '', '', '', '', ''],
    ]);
    expect(result.rows, hasLength(1));
  });

  test('plusieurs erreurs sur une même ligne sont toutes retournées', () {
    final result = validate([account(name: '', type: 'XYZ', balance: 'abc')]);
    expect(result.rows.single.errors, hasLength(3));
  });

  test('plusieurs lignes invalides agrègent toutes les erreurs', () {
    final result = validate([account(name: ''), account(type: 'XYZ')]);
    expect(result.errors, hasLength(2));
  });

  test('numéros de ligne CSV corrects', () {
    final result = validate([
      ['', '', '', '', '', '', ''],
      account(name: ''),
    ]);
    expect(result.rows.single.lineNumber, 3);
  });

  test(
    'validation globale valide uniquement lorsque toutes les lignes sont valides',
    () {
      expect(validate([account(), account(type: 'XYZ')]).isValid, isFalse);
    },
  );

  test('aucune exception si une ligne inattendue est fournie', () {
    expect(
      () => validate([
        ['Compte courant'],
      ]),
      returnsNormally,
    );
  });
}
