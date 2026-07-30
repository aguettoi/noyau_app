import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/config/app_config.dart';

void main() {
  test('Supabase is configured only when both public values are provided', () {
    const incomplete = AppConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: '',
    );
    const configured = AppConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'public-key',
    );

    expect(incomplete.isSupabaseConfigured, isFalse);
    expect(configured.isSupabaseConfigured, isTrue);
  });
}
