import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/application/providers/household_onboarding_provider.dart';
import 'package:noyau_app/features/finance/application/providers/supabase_client_provider.dart';
import 'package:noyau_app/features/finance/presentation/household_onboarding_page.dart';

void main() {
  testWidgets('creates a household through the secured gateway', (
    tester,
  ) async {
    final gateway = _OnboardingGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdOnboardingGatewayProvider.overrideWithValue(gateway),
          pendingHouseholdInvitationsProvider.overrideWith((ref) async => []),
          supabaseAuthGatewayProvider.overrideWithValue(_AuthGateway()),
        ],
        child: const MaterialApp(home: HouseholdOnboardingPage()),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('household-name-field')),
      'Foyer test',
    );
    await tester.tap(find.byKey(const Key('create-household-button')));
    await tester.pumpAndSettle();
    expect(gateway.createdName, 'Foyer test');
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows and accepts an email-bound invitation', (tester) async {
    final gateway = _OnboardingGateway();
    final invitation = HouseholdInvitation(
      id: 'invitation-1',
      householdId: 'household-1',
      householdName: 'Foyer partagé',
      invitedByName: 'Ibrahim',
      expiresAt: DateTime.utc(2030),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdOnboardingGatewayProvider.overrideWithValue(gateway),
          pendingHouseholdInvitationsProvider.overrideWith(
            (ref) async => [invitation],
          ),
          supabaseAuthGatewayProvider.overrideWithValue(_AuthGateway()),
        ],
        child: const MaterialApp(home: HouseholdOnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Foyer partagé'), findsOneWidget);
    await tester.tap(find.text('Rejoindre'));
    await tester.pumpAndSettle();
    expect(gateway.acceptedInvitationId, 'invitation-1');
    expect(tester.takeException(), isNull);
  });
}

class _OnboardingGateway implements HouseholdOnboardingGateway {
  String? createdName;
  String? acceptedInvitationId;

  @override
  Future<String> createHousehold(String name) async {
    createdName = name;
    return 'household-1';
  }

  @override
  Future<List<HouseholdInvitation>> pendingInvitations() async => [];

  @override
  Future<String> acceptInvitation(String invitationId) async {
    acceptedInvitationId = invitationId;
    return 'household-1';
  }

  @override
  Future<void> inviteMember({
    required String householdId,
    required String email,
  }) async {}
}

class _AuthGateway implements SupabaseAuthGateway {
  @override
  String? get currentUserId => 'user-1';

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
  }) async => true;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {}
}
