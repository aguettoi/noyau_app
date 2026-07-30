import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/source_envelope_import.dart';

void main() {
  testWidgets('charge les 25 enveloppes du manifeste source', (tester) async {
    final envelopes = await SourceEnvelopeImport.loadEnvelopeNames();

    expect(envelopes, hasLength(25));
    expect(envelopes, contains('Traite maison'));
    expect(envelopes, contains('Vignette'));
  });
}
