import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Realtime transports only household-scoped invalidation payloads', () {
    final source = File(
      'lib/features/portability/application/household_realtime_provider.dart',
    ).readAsStringSync();
    expect(source, contains("table: 'household_realtime_invalidations'"));
    for (final sensitiveTable in [
      'accounts',
      'financial_events',
      'obligations',
      'wealth_assets',
      'financial_reminders',
    ]) {
      expect(source, isNot(contains("table: '$sensitiveTable'")));
    }
    expect(source, contains("payload.newRecord['topic']"));
  });
}
