import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';
import 'package:noyau_app/features/finance/application/providers/payment_methods_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_accounts_provider.dart';
import 'package:noyau_app/features/finance/application/providers/remote_household_members_provider.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/features/finance/domain/household_member.dart';
import 'package:noyau_app/features/finance/presentation/payment_methods_page.dart';

void main() {
  testWidgets('création avec compte et titulaire puis édition et archivage', (
    tester,
  ) async {
    final gateway = _FakePaymentMethodsGateway();
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.text('Aucun moyen de paiement configuré.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('payment-methods-add-button')));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un moyen de paiement'), findsOneWidget);
    expect(find.text('Compte associé (facultatif)'), findsOneWidget);
    expect(find.text('Titulaire (facultatif)'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('payment-method-label-field')),
      'Carte principale',
    );
    await tester.tap(find.byKey(const Key('payment-method-account-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compte courant').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('payment-method-holder-field')),
    );
    await tester.tap(find.byKey(const Key('payment-method-holder-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Membre Alpha').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('payment-method-save-button')));
    await tester.pumpAndSettle();

    expect(gateway.items.single.accountId, 'account-1');
    expect(gateway.items.single.holderUserId, 'member-1');
    expect(find.text('Carte principale'), findsOneWidget);

    await tester.tap(find.byKey(const Key('payment-method-method-1')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier le moyen de paiement'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('payment-method-label-field')),
      'Carte ménage',
    );
    await tester.tap(find.byKey(const Key('payment-method-save-button')));
    await tester.pumpAndSettle();
    expect(gateway.items.single.label, 'Carte ménage');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(gateway.items.single.active, isFalse);
    expect(find.textContaining('Archivé'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('chargement et erreur restent explicites', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          paymentMethodsProvider.overrideWith(
            (ref) =>
                Future<List<PaymentMethod>>.error(StateError('indisponible')),
          ),
          remoteAccountsProvider.overrideWith((ref) async => const []),
          remoteHouseholdMembersProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: PaymentMethodsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Moyens de paiement indisponibles.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(_FakePaymentMethodsGateway gateway) => ProviderScope(
  overrides: [
    activeHouseholdProvider.overrideWith(
      (ref) async => const ActiveHouseholdState(
        status: ActiveHouseholdStatus.singleHousehold,
        householdId: 'household-1',
      ),
    ),
    paymentMethodsGatewayProvider.overrideWithValue(gateway),
    paymentMethodsProvider.overrideWith(
      (ref) async => gateway.list('household-1'),
    ),
    remoteAccountsProvider.overrideWith((ref) async => [_account]),
    remoteHouseholdMembersProvider.overrideWith((ref) async => const [_member]),
  ],
  child: const MaterialApp(home: PaymentMethodsPage()),
);

final _account = FinancialAccount(
  id: 'account-1',
  name: 'Compte courant',
  type: FinancialAccountType.bank,
  openingBalance: Money.fromDirhams(0),
);
const _member = HouseholdMember(id: 'member-1', displayName: 'Membre Alpha');

class _FakePaymentMethodsGateway implements PaymentMethodsGateway {
  final items = <PaymentMethod>[];

  @override
  Future<List<PaymentMethod>> list(String householdId) async =>
      List.unmodifiable(items);

  @override
  Future<void> create({
    required String householdId,
    String? accountId,
    String? holderUserId,
    required String type,
    required String label,
  }) async => items.add(
    PaymentMethod(
      id: 'method-${items.length + 1}',
      label: label,
      type: type,
      accountId: accountId,
      holderUserId: holderUserId,
      active: true,
    ),
  );

  @override
  Future<void> update({
    required String id,
    String? accountId,
    String? holderUserId,
    required String type,
    required String label,
    required bool active,
  }) async {
    final index = items.indexWhere((item) => item.id == id);
    items[index] = PaymentMethod(
      id: id,
      label: label,
      type: type,
      accountId: accountId,
      holderUserId: holderUserId,
      active: active,
    );
  }

  @override
  Future<void> setEnvelopeRecommendation({
    required String envelopeId,
    String? accountId,
    String? paymentMethodId,
  }) async {}
}
