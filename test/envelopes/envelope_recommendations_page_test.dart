import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/envelopes/presentation/envelope_recommendations_page.dart';
import 'package:noyau_app/features/finance/application/providers/payment_methods_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/domain/account_ownership.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';

void main() {
  final account = FinancialAccount(
    id: 'account-active',
    name: 'Compte actif',
    type: FinancialAccountType.bank,
    openingBalance: const Money.fromMinorUnits(0),
    ownershipType: AccountOwnershipType.individual,
    holders: const [AccountHolder(userId: 'member-a', displayName: 'Membre A')],
  );
  final archived = FinancialAccount(
    id: 'account-archived',
    name: 'Compte inactif',
    type: FinancialAccountType.bank,
    openingBalance: const Money.fromMinorUnits(0),
    archivedAt: DateTime(2026),
  );
  final otherAccount = FinancialAccount(
    id: 'account-other',
    name: 'Autre compte actif',
    type: FinancialAccountType.cash,
    openingBalance: const Money.fromMinorUnits(0),
  );
  const envelope = RemoteEnvelopeBalance(
    id: 'envelope-1',
    name: 'Besoin perso',
    inflows: Money.fromMinorUnits(52048),
    outflows: Money.fromMinorUnits(0),
    balance: Money.fromMinorUnits(52048),
    isSystem: false,
  );
  const configuredEnvelope = RemoteEnvelopeBalance(
    id: 'envelope-1',
    name: 'Besoin perso',
    inflows: Money.fromMinorUnits(52048),
    outflows: Money.fromMinorUnits(0),
    balance: Money.fromMinorUnits(52048),
    isSystem: false,
    recommendedAccountId: 'account-active',
  );
  const householdEnvelope = RemoteEnvelopeBalance(
    id: 'envelope-household',
    name: 'Sorties WE',
    inflows: Money.fromMinorUnits(100000),
    outflows: Money.fromMinorUnits(0),
    balance: Money.fromMinorUnits(100000),
    isSystem: false,
    recommendedAccountId: 'account-active',
    economicRule: 'household_scenario',
  );

  Future<List<({String envelope, String? account, String? method})>> pump(
    WidgetTester tester,
    Size size, {
    RemoteEnvelopeBalance displayedEnvelope = envelope,
  }) async {
    final saves = <({String envelope, String? account, String? method})>[];
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => [displayedEnvelope],
          ),
          remoteAccountsProvider.overrideWith(
            (ref) async => [account, otherAccount, archived],
          ),
          paymentMethodsProvider.overrideWith(
            (ref) async => const [
              PaymentMethod(
                id: 'method-active',
                label: 'Carte active',
                type: 'bank_card',
                accountId: 'account-active',
                holderUserId: 'member-a',
                active: true,
              ),
              PaymentMethod(
                id: 'method-inactive',
                label: 'Carte inactive',
                type: 'bank_card',
                accountId: 'account-active',
                holderUserId: 'member-a',
                active: false,
              ),
            ],
          ),
          setEnvelopeRecommendationProvider.overrideWithValue(({
            required envelopeId,
            accountId,
            paymentMethodId,
          }) async {
            saves.add((
              envelope: envelopeId,
              account: accountId,
              method: paymentMethodId,
            ));
          }),
        ],
        child: const MaterialApp(home: EnvelopeRecommendationsPage()),
      ),
    );
    await tester.pumpAndSettle();
    return saves;
  }

  for (final size in [const Size(390, 700), const Size(1200, 800)]) {
    testWidgets('configuration centralisée responsive à ${size.width}', (
      tester,
    ) async {
      final saves = await pump(tester, size);
      expect(find.text('Besoin perso'), findsOneWidget);
      expect(find.text('À configurer'), findsOneWidget);
      expect(find.text('Compte inactif'), findsNothing);

      await tester.ensureVisible(
        find.byKey(const Key('recommended-account-envelope-1')),
      );
      await tester.tap(find.byKey(const Key('recommended-account-envelope-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compte actif').last);
      await tester.pumpAndSettle();
      expect(saves.single.account, 'account-active');
      expect(saves.single.method, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('moyen inactif est exclu de la sélection', (tester) async {
    final saves = await pump(
      tester,
      const Size(390, 700),
      displayedEnvelope: configuredEnvelope,
    );
    await tester.ensureVisible(
      find.byKey(const Key('recommended-method-envelope-1')),
    );
    await tester.tap(find.byKey(const Key('recommended-method-envelope-1')));
    await tester.pumpAndSettle();
    expect(find.text('Carte inactive'), findsNothing);
    await tester.tap(find.text('Carte active').last);
    await tester.pumpAndSettle();
    expect(saves.single.method, 'method-active');
    expect(tester.takeException(), isNull);
  });

  testWidgets('un compte recommandé peut être remplacé', (tester) async {
    final saves = await pump(
      tester,
      const Size(1200, 800),
      displayedEnvelope: configuredEnvelope,
    );
    await tester.tap(find.byKey(const Key('recommended-account-envelope-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autre compte actif').last);
    await tester.pumpAndSettle();
    expect(saves.single.account, 'account-other');
    expect(tester.takeException(), isNull);
  });

  testWidgets('la règle économique ne provient pas du compte individuel', (
    tester,
  ) async {
    await pump(
      tester,
      const Size(1200, 800),
      displayedEnvelope: householdEnvelope,
    );
    expect(find.text('Foyer — clé du scénario'), findsOneWidget);
    expect(find.text('Individuel'), findsNothing);
    expect(find.text('Compte actif'), findsOneWidget);
  });

  test('dérive les règles canoniques depuis les étapes Budget', () {
    expect(
      deriveEnvelopeEconomicRule(
        recommendationKind: 'single_account',
        isSystem: false,
        scenarioSteps: const [
          {'contribution_key': 'single_member', 'member_user_id': 'ibrahim'},
        ],
        memberNames: const {'ibrahim': 'Ibrahim'},
      ),
      (rule: 'individual', memberName: 'Ibrahim'),
    );
    expect(
      deriveEnvelopeEconomicRule(
        recommendationKind: 'single_account',
        isSystem: false,
        scenarioSteps: const [
          {'contribution_key': 'custom_percentage'},
        ],
        memberNames: const {},
      ).rule,
      'household_scenario',
    );
    expect(
      deriveEnvelopeEconomicRule(
        recommendationKind: 'scenario_split',
        isSystem: false,
        scenarioSteps: const [],
        memberNames: const {},
      ).rule,
      'household_multi_account',
    );
  });
}
