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

  testWidgets('signup validates identity and forwards metadata', (
    tester,
  ) async {
    final gateway = _RecordingAuthGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseAuthGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(home: SupabaseAuthPage()),
      ),
    );

    await tester.tap(find.byKey(const Key('auth-switch-mode-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('auth-first-name-field')),
      'Nora',
    );
    await tester.enterText(
      find.byKey(const Key('auth-last-name-field')),
      'Test',
    );
    await tester.enterText(
      find.byKey(const Key('auth-email-field')),
      'nora@example.test',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-field')),
      'strong-pass-123',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password-confirmation-field')),
      'strong-pass-123',
    );
    await tester.ensureVisible(find.byKey(const Key('auth-sign-in-button')));
    await tester.tap(find.byKey(const Key('auth-sign-in-button')));
    await tester.pumpAndSettle();

    expect(gateway.signupEmail, 'nora@example.test');
    expect(gateway.signupFirstName, 'Nora');
    expect(
      find.textContaining('Confirmez votre adresse e-mail'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot password uses the entered email', (tester) async {
    final gateway = _RecordingAuthGateway();
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
    await tester.tap(find.byKey(const Key('auth-forgot-password-button')));
    await tester.pumpAndSettle();
    expect(gateway.resetEmail, 'member@example.test');
    expect(find.textContaining('réinitialisation'), findsOneWidget);
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

  @override
  Future<bool> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async => false;

  @override
  Future<void> sendPasswordReset(String email) async {}
}

class _RecordingAuthGateway implements SupabaseAuthGateway {
  String? signupEmail;
  String? signupFirstName;
  String? resetEmail;

  @override
  String? get currentUserId => null;

  @override
  Stream<String?> get userIdChanges => const Stream.empty();

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<bool> signUp({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    signupEmail = email;
    signupFirstName = firstName;
    return false;
  }

  @override
  Future<void> sendPasswordReset(String email) async => resetEmail = email;

  @override
  Future<void> signOut() async {}
}
