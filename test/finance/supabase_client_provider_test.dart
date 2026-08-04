import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('le provider reutilise un client Supabase deja initialise', () {
    final existingClient = SupabaseClient(
      'https://example.supabase.co',
      'public-anon-key',
    );
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(existingClient)],
    );
    addTearDown(container.dispose);

    expect(container.read(supabaseClientProvider), same(existingClient));
  });
}
