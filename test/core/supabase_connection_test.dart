import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/config/app_config.dart';

void main() {
  test('reaches Supabase with the provided launch values', () async {
    const config = AppConfig.fromEnvironment();
    const shouldRun = bool.fromEnvironment('RUN_SUPABASE_CONNECTION_TEST');

    if (!config.isSupabaseConfigured || !shouldRun) {
      return;
    }

    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.getUrl(
      Uri.parse('${config.supabaseUrl}/auth/v1/settings'),
    );
    request.headers.set('apikey', config.supabasePublishableKey);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();

    expect(response.statusCode, HttpStatus.ok);
    expect(jsonDecode(body), isA<Map<String, dynamic>>());
  });
}
