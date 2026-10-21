import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'envelope UI and household export use the server redaction contract',
    () {
      final envelopeProvider = File(
        'lib/features/envelopes/application/providers/'
        'remote_envelopes_provider.dart',
      ).readAsStringSync();
      final exportProvider = File(
        'lib/features/portability/application/portability_provider.dart',
      ).readAsStringSync();
      final recommendationGateway = File(
        'lib/features/finance/application/providers/'
        'payment_methods_provider.dart',
      ).readAsStringSync();

      expect(envelopeProvider, contains("'list_household_envelopes_safe'"));
      expect(exportProvider, contains("'list_household_envelopes_safe'"));
      expect(exportProvider, contains("'list_account_privacy_summaries_v2'"));
      expect(
        exportProvider,
        isNot(contains("'accounts': await rows('accounts')")),
      );
      expect(
        exportProvider,
        isNot(contains("'envelopes': await rows('envelopes')")),
      );
      expect(
        recommendationGateway,
        contains("'set_envelope_recommendation_safe'"),
      );
    },
  );
}
