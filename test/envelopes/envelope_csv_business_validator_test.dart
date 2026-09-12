import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/envelopes/application/envelope_csv_business_validator.dart';
import 'package:noyau_app/features/finance/application/csv_import_templates.dart';

void main() {
  final validator = EnvelopeCsvBusinessValidator();
  final template = byType(ImportTemplateType.envelopes);

  test('importe trois enveloppes avec soldes, statuts et notes', () {
    final result = validator.validate(
      template: template,
      rows: const [
        ['nom', 'solde_initial', 'statut', 'notes'],
        ['Courses', '1000,50', 'actif', 'Priorité'],
        ['Maison', '0', '', ''],
        ['Épargne', '25.25', 'inactif', 'Ancienne'],
      ],
    );
    expect(result.isValid, isTrue);
    expect(result.rows.map((row) => row.openingBalanceMad), [
      '1000.50',
      '0.00',
      '25.25',
    ]);
    expect(result.rows.map((row) => row.isActive), [true, true, false]);
    expect(result.rows.first.notes, 'Priorité');
  });

  test(
    'refuse les doublons, les montants négatifs et les statuts inconnus',
    () {
      final result = validator.validate(
        template: template,
        rows: const [
          ['nom', 'solde_initial', 'statut', 'notes'],
          ['Courses', '0', 'actif', ''],
          [' courses ', '0', 'actif', ''],
          ['Dette', '-1', 'actif', ''],
          ['Loisirs', '1', 'archivé', ''],
        ],
      );
      expect(result.isValid, isFalse);
      expect(result.errors, hasLength(2));
    },
  );
}
