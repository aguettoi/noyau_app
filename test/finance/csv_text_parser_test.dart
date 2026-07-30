import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/csv_text_parser.dart';

void main() {
  final p = CsvTextParser();
  test(
    'parse un CSV simple',
    () => expect(p.parse('a,b\n1,2'), [
      ['a', 'b'],
      ['1', '2'],
    ]),
  );
  test(
    'gère les fins de ligne CRLF',
    () => expect(p.parse('a,b\r\n1,2'), [
      ['a', 'b'],
      ['1', '2'],
    ]),
  );
  test(
    'gère la dernière ligne sans retour',
    () => expect(p.parse('a,b'), [
      ['a', 'b'],
    ]),
  );
  test(
    'gère une virgule dans un champ entre guillemets',
    () => expect(p.parse('"a,b",c'), [
      ['a,b', 'c'],
    ]),
  );
  test(
    'gère les guillemets échappés',
    () => expect(p.parse('"a""b"'), [
      ['a"b'],
    ]),
  );
  test(
    'gère les champs vides',
    () => expect(p.parse('a,,c'), [
      ['a', '', 'c'],
    ]),
  );
  test(
    'gère une ligne vide',
    () => expect(p.parse('\n'), [
      [''],
    ]),
  );
  test(
    'retourne une liste vide pour un texte vide',
    () => expect(p.parse(''), isEmpty),
  );
  test(
    'rejette un champ entre guillemets non fermé',
    () => expect(() => p.parse('"a'), throwsFormatException),
  );
}
