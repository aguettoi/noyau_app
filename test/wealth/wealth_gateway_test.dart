import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:noyau_app/features/wealth/application/providers/wealth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('expected dues use the occurrence status exposed by the SQL view', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        expect(request.method, 'GET');
        expect(
          request.url.path,
          '/rest/v1/expected_financial_occurrence_overview',
        );
        expect(request.url.queryParameters['household_id'], 'eq.household-1');
        expect(
          request.url.queryParameters['select'],
          'id,label,expected_on,expected_amount,economic_type,occurrence_status',
        );
        expect(
          request.url.queryParameters['occurrence_status'],
          'in.("expected","partially_realized","overdue")',
        );
        expect(request.url.queryParameters, isNot(contains('status')));
        return http.Response(
          jsonEncode(const []),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);

    final rows = await SupabaseWealthGateway(
      client,
    ).fetchExpectedOccurrences('household-1');

    expect(rows, isEmpty);
  });
}
