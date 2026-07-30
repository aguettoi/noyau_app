import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';
import 'package:noyau_app/features/finance/application/csv_structure_validator.dart';

void main() {
  final validator = CsvStructureValidator();
  final accountsTemplate = byType(ImportTemplateType.accounts);
  final header = List<String>.from(accountsTemplate.columns);

  CsvStructureValidationResult validate(List<List<String>> rows) =>
      validator.validate(rows: rows, template: accountsTemplate);

  test('structure valide', () {
    final result = validate([
      header,
      ['id-1', 'Compte courant', 'banque', '', 'actif', '0', '2026-01-01'],
    ]);

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
  });

  test('fichier vide', () {
    final result = validate([]);

    expect(result.isValid, isFalse);
    expect(result.errors, ['Le fichier est vide.']);
  });

  test('en-tête absente', () {
    final result = validate([
      ['', '   '],
    ]);

    expect(result.isValid, isFalse);
    expect(result.errors, ["La ligne d'en-tête est absente."]);
  });

  test('colonne obligatoire manquante', () {
    final missingType = header.where((column) => column != 'type').toList();
    final result = validate([missingType]);

    expect(result.isValid, isFalse);
    expect(result.errors, contains("La colonne 'Type' est manquante."));
  });

  test('colonne dupliquée', () {
    final duplicateName = [...header, 'nom'];
    final result = validate([duplicateName]);

    expect(result.isValid, isFalse);
    expect(
      result.errors,
      contains("La colonne 'Nom' apparaît plusieurs fois."),
    );
  });

  test('ligne avec trop de colonnes', () {
    final result = validate([
      header,
      [...List<String>.filled(header.length, ''), 'en trop'],
    ]);

    expect(result.isValid, isFalse);
    expect(
      result.errors,
      contains('La ligne 2 contient 8 colonnes au lieu de 7.'),
    );
  });

  test('ligne avec trop peu de colonnes', () {
    final result = validate([
      header,
      ['id-1', 'Compte', 'banque', '', 'actif', '0'],
    ]);

    expect(result.isValid, isFalse);
    expect(
      result.errors,
      contains('La ligne 2 contient 6 colonnes au lieu de 7.'),
    );
  });

  test('espaces autour des noms de colonnes', () {
    final result = validate([header.map((column) => '  $column  ').toList()]);

    expect(result.isValid, isTrue);
  });

  test('casse différente des noms de colonnes', () {
    final result = validate([
      header.map((column) => column.toUpperCase()).toList(),
    ]);

    expect(result.isValid, isTrue);
  });

  test('lignes totalement vides ignorées', () {
    final result = validate([
      header,
      ['', ' ', '', '', '', '', ''],
      ['id-1', 'Compte', 'banque', '', 'actif', '0', '2026-01-01'],
      [],
    ]);

    expect(result.isValid, isTrue);
  });

  test('plusieurs erreurs retournées simultanément', () {
    final result = validate([
      ['nom', 'nom'],
      ['Compte', 'banque', 'supplémentaire'],
    ]);

    expect(result.isValid, isFalse);
    expect(
      result.errors,
      contains("La colonne 'Nom' apparaît plusieurs fois."),
    );
    expect(result.errors, contains("La colonne 'Type' est manquante."));
    expect(
      result.errors,
      contains('La ligne 2 contient 3 colonnes au lieu de 2.'),
    );
  });
}
