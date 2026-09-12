import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/envelopes/application/envelope_business_import.dart';
import 'package:noyau_app/features/finance/application/source_envelope_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('les 25 noms historiques sont importables et distincts', () async {
    final names = await SourceEnvelopeImport.loadEnvelopeNames();
    expect(normalizeEnvelopeImportNames(names), hasLength(25));
  });

  test('les noms vides et doublons ne sont pas transmis à la RPC', () {
    expect(
      normalizeEnvelopeImportNames([' Courses ', 'courses', '', 'Maison']),
      ['Courses', 'Maison'],
    );
  });
}
