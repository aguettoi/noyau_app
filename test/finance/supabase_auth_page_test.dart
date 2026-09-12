import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/finance/presentation/supabase_auth_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('keeps the authentication error generic after an AuthException', (
    tester,
  ) async {
    final gateway = _FailingAuthGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseAuthGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(home: SupabaseAuthPage()),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'member@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'not-a-real-password',
    );
    await tester.tap(find.byKey(const Key('auth-sign-in-button')));
    await tester.pumpAndSettle();

    expect(gateway.calls, 1);
    expect(
      find.text(
        'Connexion impossible. Vérifiez votre e-mail et votre mot de passe.',
      ),
      findsOneWidget,
    );
    expect(find.text('Invalid login credentials'), findsNothing);
  });
}

class _FailingAuthGateway implements SupabaseAuthGateway {
  var calls = 0;

  @override
  String? get currentUserId => null;

  @override
  Stream<String?> get userIdChanges => const Stream.empty();

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    calls++;
    throw const AuthApiException(
      'Invalid login credentials',
      statusCode: '400',
      code: 'invalid_credentials',
    );
  }

  @override
  Future<void> signOut() async {}
}
