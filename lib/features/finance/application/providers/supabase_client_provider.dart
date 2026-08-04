import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Exposes the Supabase client initialized once at application startup.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

abstract interface class SupabaseAuthGateway {
  String? get currentUserId;

  Stream<String?> get userIdChanges;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  Future<void> signOut();
}

class SupabaseClientAuthGateway implements SupabaseAuthGateway {
  SupabaseClientAuthGateway(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userIdChanges =>
      _client.auth.onAuthStateChange.map((state) => state.session?.user.id);

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}

final supabaseAuthGatewayProvider = Provider<SupabaseAuthGateway>(
  (ref) => SupabaseClientAuthGateway(ref.watch(supabaseClientProvider)),
);

/// Emits a restored session first, then later authentication changes.
final supabaseUserIdProvider = StreamProvider<String?>((ref) {
  final gateway = ref.watch(supabaseAuthGatewayProvider);
  return Stream.multi((controller) {
    controller.add(gateway.currentUserId);
    final subscription = gateway.userIdChanges.listen(
      controller.add,
      onError: controller.addError,
    );
    ref.onDispose(subscription.cancel);
  });
});

/// Authenticated user identifier, independently overridable in tests.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(supabaseUserIdProvider).valueOrNull,
);
