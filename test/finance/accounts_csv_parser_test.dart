import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/accounts_csv_parser.dart';

void main() {
  final p = AccountsCsvParser();
  const h =
      'external_id;nom;type;titulaire;statut;solde_initial_mad;date_solde_initial';
  test('CSV valide et BOM', () {
    final r = p.parse(
      utf8.encode('\uFEFF$h\n1;Compte;banque;Ibrahim;;0;2026-01-01'),
    );
    expect(r.valid, hasLength(1));
    expect(r.valid.first.values['statut'], 'actif');
  });
  test('erreurs structurées', () {
    final r = p.parse(utf8.encode('$h\n1;;banque;;;x;2026-99-99\n1;A;banque'));
    expect(
      r.issues.map((x) => x.code),
      containsAll([
        'empty_required_value',
        'invalid_integer',
        'invalid_date',
        'wrong_column_count',
      ]),
    );
  });
  test('mille lignes', () {
    final b = StringBuffer('$h\n');
    for (var i = 0; i < 1000; i++) {
      b.writeln('$i;C$i;banque;;;0;');
    }
    expect(p.parse(utf8.encode(b.toString())).valid, hasLength(1000));
  });
  test('refuse un format ou une date calendaire impossible', () {
    final r = p.parse(
      utf8.encode('$h\n1;A;banque;;;0;2026-02-30\n2;B;banque;;;0;30/07/2026'),
    );
    expect(
      r.issues.where((issue) => issue.code == 'invalid_date'),
      hasLength(1),
    );
  });
}
