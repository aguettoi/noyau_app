import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/envelopes/application/providers/remote_envelopes_provider.dart';
import 'package:noyau_app/features/envelopes/presentation/envelope_dashboard_page.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';

class _DistributionGateway implements ToAllocateDistributionGateway {
  _DistributionGateway({this.onDistribute});

  Map<String, Object?>? request;
  final VoidCallback? onDistribute;

  @override
  Future<String> distribute(Map<String, Object?> params) async {
    request = params;
    onDistribute?.call();
    return 'distribution-event';
  }
}

class _EnvelopeTransferGateway implements EnvelopeTransferGateway {
  _EnvelopeTransferGateway({this.failFirst = false});

  Map<String, Object?>? request;
  final requests = <Map<String, Object?>>[];
  final bool failFirst;
  var callCount = 0;

  @override
  Future<String> transfer(Map<String, Object?> parameters) async {
    callCount++;
    request = Map<String, Object?>.from(parameters);
    requests.add(request!);
    if (failFirst && callCount == 1) {
      throw StateError('Réseau incertain');
    }
    return 'envelope-transfer-event';
  }
}

void main() {
  const userEnvelope = RemoteEnvelopeBalance(
    id: 'user-envelope',
    name: 'Enveloppe utilisateur au nom volontairement long',
    inflows: Money.fromMinorUnits(10000),
    outflows: Money.fromMinorUnits(0),
    balance: Money.fromMinorUnits(10000),
    isSystem: false,
    lastMovementAt: null,
  );
  const zeroEnvelope = RemoteEnvelopeBalance(
    id: 'zero-envelope',
    name: 'Zéro',
    inflows: Money.fromMinorUnits(0),
    outflows: Money.fromMinorUnits(0),
    balance: Money.fromMinorUnits(0),
    isSystem: false,
  );
  const systemEnvelope = RemoteEnvelopeBalance(
    id: 'system-envelope',
    name: 'À répartir',
    inflows: Money.fromMinorUnits(0),
    outflows: Money.fromMinorUnits(10000),
    balance: Money.fromMinorUnits(-10000),
    isSystem: true,
    systemCode: 'to_allocate',
    lastMovementAt: null,
  );
  const availableSystemEnvelope = RemoteEnvelopeBalance(
    id: 'to-allocate-envelope',
    name: 'À répartir',
    inflows: Money.fromMinorUnits(2500),
    outflows: Money.fromMinorUnits(0),
    balance: Money.fromMinorUnits(2500),
    isSystem: true,
    systemCode: 'to_allocate',
    lastMovementAt: null,
  );
  const emptySystemEnvelope = RemoteEnvelopeBalance(
    id: 'to-allocate-envelope',
    name: 'À répartir',
    inflows: Money.fromMinorUnits(2500),
    outflows: Money.fromMinorUnits(2500),
    balance: Money.fromMinorUnits(0),
    isSystem: true,
    systemCode: 'to_allocate',
    lastMovementAt: null,
  );
  const archivedEnvelope = RemoteEnvelopeBalance(
    id: 'archived-envelope',
    name: 'Historique conservé',
    inflows: Money.fromMinorUnits(2500),
    outflows: Money.fromMinorUnits(0),
    balance: Money.fromMinorUnits(2500),
    isSystem: false,
    isArchived: true,
    notes: 'Ne plus utiliser pour de nouvelles opérations.',
  );

  Future<void> pumpDashboard(
    WidgetTester tester,
    Size size, {
    List<RemoteEnvelopeBalance> envelopes = const [
      userEnvelope,
      zeroEnvelope,
      systemEnvelope,
    ],
    _DistributionGateway? distributionGateway,
    _EnvelopeTransferGateway? transferGateway,
    List<RemoteEnvelopeBalance> Function()? envelopeLoader,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remoteEnvelopeHistoryProvider.overrideWith(
            (ref) async => envelopeLoader?.call() ?? envelopes,
          ),
          remoteEnvelopeBalancesProvider.overrideWith(
            (ref) async => (envelopeLoader?.call() ?? envelopes)
                .where((envelope) => !envelope.isArchived)
                .toList(growable: false),
          ),
          activeHouseholdProvider.overrideWith(
            (ref) async => const ActiveHouseholdState(
              status: ActiveHouseholdStatus.singleHousehold,
              householdId: 'household-id',
            ),
          ),
          if (distributionGateway != null)
            toAllocateDistributionGatewayProvider.overrideWithValue(
              distributionGateway,
            ),
          if (transferGateway != null)
            envelopeTransferGatewayProvider.overrideWithValue(transferGateway),
        ],
        child: const MaterialApp(home: Scaffold(body: EnvelopeDashboardPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'les cartes Enveloppes restent sans overflow en fenêtre réduite',
    (tester) async {
      await pumpDashboard(tester, const Size(480, 720));

      expect(
        find.byKey(const Key('envelope-actions-user-envelope')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('envelope-actions-zero-envelope')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('envelope-actions-system-envelope')),
        findsNothing,
      );
      await tester.ensureVisible(find.text('Système'));
      expect(find.text('Système'), findsOneWidget);
      expect(find.textContaining('Entrées :'), findsNWidgets(3));
      expect(find.text('-100.00 MAD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('les cartes Enveloppes restent sans overflow en fenêtre large', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(1200, 720));

    expect(find.text('100.00 MAD'), findsOneWidget);
    expect(find.text('0.00 MAD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'une alerte discrète affiche le solde canonique à répartir et ouvre sa répartition',
    (tester) async {
      await pumpDashboard(
        tester,
        const Size(1000, 760),
        envelopes: const [availableSystemEnvelope, userEnvelope],
      );

      expect(find.byKey(const Key('to-allocate-alert')), findsOneWidget);
      expect(find.text('25,00 MAD à répartir'), findsOneWidget);
      expect(
        find.text('Des fonds attendent d’être affectés à vos enveloppes.'),
        findsOneWidget,
      );
      expect(find.textContaining('to-allocate-envelope'), findsNothing);

      await tester.tap(find.byKey(const Key('to-allocate-alert-action')));
      await tester.pumpAndSettle();

      expect(find.text('Répartir le solde disponible'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('l alerte est masquée quand le solde à répartir est nul', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const Size(1000, 760),
      envelopes: const [emptySystemEnvelope, userEnvelope],
    );

    expect(find.byKey(const Key('to-allocate-alert')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'le transfert visible utilise le contrat FinancialEvent et exclut le système',
    (tester) async {
      final gateway = _EnvelopeTransferGateway();
      await pumpDashboard(
        tester,
        const Size(1000, 760),
        envelopes: const [userEnvelope, zeroEnvelope, systemEnvelope],
        transferGateway: gateway,
      );

      await tester.tap(find.byKey(const Key('envelope-transfer-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('transfer-source-envelope-field')).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('À répartir (Système)'), findsNothing);
      await tester.tap(find.text(userEnvelope.name).last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('transfer-destination-envelope-field')).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(zeroEnvelope.name).last);
      await tester.enterText(
        find.byKey(const Key('transfer-envelope-amount-field')),
        '10',
      );
      await tester.enterText(
        find.byKey(const Key('transfer-envelope-description-field')),
        'Transfert test',
      );
      await tester.tap(
        find.byKey(const Key('confirm-envelope-transfer-button')),
      );
      await tester.pumpAndSettle();

      expect(gateway.callCount, 1);
      expect(gateway.request!['p_source_envelope_id'], userEnvelope.id);
      expect(gateway.request!['p_destination_envelope_id'], zeroEnvelope.id);
      expect(gateway.request!['p_amount'], '10.00');
      expect(gateway.request!['p_idempotency_key'], isNotEmpty);
      expect(gateway.request!['p_notes'], isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('un retry de transfert conserve la même clé idempotente', (
    tester,
  ) async {
    final gateway = _EnvelopeTransferGateway(failFirst: true);
    await pumpDashboard(
      tester,
      const Size(1000, 760),
      envelopes: const [userEnvelope, zeroEnvelope],
      transferGateway: gateway,
    );

    await tester.tap(find.byKey(const Key('envelope-transfer-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('transfer-source-envelope-field')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(userEnvelope.name).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('transfer-destination-envelope-field')).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(zeroEnvelope.name).last);
    await tester.enterText(
      find.byKey(const Key('transfer-envelope-amount-field')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('transfer-envelope-description-field')),
      'Transfert test',
    );

    final submit = find.byKey(const Key('confirm-envelope-transfer-button'));
    await tester.tap(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(gateway.requests, hasLength(2));
    expect(
      gateway.requests[0]['p_idempotency_key'],
      gateway.requests[1]['p_idempotency_key'],
    );
  });

  testWidgets('l alerte à répartir reste sans overflow en fenêtre étroite', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const Size(320, 720),
      envelopes: const [availableSystemEnvelope, userEnvelope],
    );

    await tester.ensureVisible(find.byKey(const Key('to-allocate-alert')));
    expect(find.text('25,00 MAD à répartir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la répartition rafraîchit et masque l alerte épuisée', (
    tester,
  ) async {
    var distributed = false;
    final gateway = _DistributionGateway(
      onDistribute: () => distributed = true,
    );
    List<RemoteEnvelopeBalance> source() => distributed
        ? const [emptySystemEnvelope, userEnvelope]
        : const [availableSystemEnvelope, userEnvelope];
    await pumpDashboard(
      tester,
      const Size(1000, 760),
      envelopeLoader: source,
      distributionGateway: gateway,
    );

    await tester.tap(find.byKey(const Key('to-allocate-alert-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('to-allocate-destination-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(userEnvelope.name).last);
    await tester.enterText(find.byKey(const Key('to-allocate-amount-0')), '25');
    await tester.tap(
      find.byKey(const Key('confirm-to-allocate-distribution-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Confirmer').last);
    await tester.pumpAndSettle();

    expect(distributed, isTrue);
    expect(find.byKey(const Key('to-allocate-alert')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une enveloppe archivee est reservee a la vue d archives', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const Size(480, 720),
      envelopes: const [userEnvelope, archivedEnvelope, systemEnvelope],
    );

    expect(find.text('Historique conservé'), findsNothing);
    await tester.tap(find.byKey(const Key('archived-envelopes-button')));
    await tester.pumpAndSettle();

    expect(find.text('Enveloppes archivées'), findsOneWidget);
    expect(find.text('Historique conservé'), findsOneWidget);
    expect(find.text('Réactiver'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('l archivage demande une confirmation avant toute action', (
    tester,
  ) async {
    await pumpDashboard(tester, const Size(480, 720));

    await tester.tap(find.byKey(const Key('envelope-actions-user-envelope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archiver'));
    await tester.pumpAndSettle();

    expect(find.text('Archiver l’enveloppe ?'), findsOneWidget);
    expect(find.text('Annuler'), findsOneWidget);
    expect(find.text('Archiver'), findsOneWidget);
  });

  testWidgets('les archives sont accessibles hors de la liste active', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const Size(480, 720),
      envelopes: const [userEnvelope, archivedEnvelope, systemEnvelope],
    );

    expect(find.text('Historique conservé'), findsNothing);
    await tester.tap(find.byKey(const Key('archived-envelopes-button')));
    await tester.pumpAndSettle();

    expect(find.text('Enveloppes archivées'), findsOneWidget);
    expect(find.text('Historique conservé'), findsOneWidget);
    expect(find.text('Réactiver'), findsOneWidget);
  });

  testWidgets(
    'Répartir distribue vers plusieurs enveloppes sans exposer À répartir',
    (tester) async {
      final gateway = _DistributionGateway();
      await pumpDashboard(
        tester,
        const Size(1000, 760),
        envelopes: const [availableSystemEnvelope, userEnvelope, zeroEnvelope],
        distributionGateway: gateway,
      );

      await tester.tap(find.byKey(const Key('distribute-to-allocate-button')));
      await tester.pumpAndSettle();
      expect(find.text('Répartir le solde disponible'), findsOneWidget);

      final systemNameCountBeforeMenu = find
          .text('À répartir')
          .evaluate()
          .length;
      await tester.tap(find.byKey(const Key('to-allocate-destination-0')));
      await tester.pumpAndSettle();
      expect(
        find.text('À répartir').evaluate().length,
        systemNameCountBeforeMenu,
      );
      await tester.tap(find.text(userEnvelope.name).last);
      await tester.enterText(
        find.byKey(const Key('to-allocate-amount-0')),
        '10',
      );
      await tester.tap(
        find.byKey(const Key('add-to-allocate-destination-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('to-allocate-destination-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zéro').last);
      await tester.enterText(
        find.byKey(const Key('to-allocate-amount-1')),
        '5',
      );
      await tester.tap(
        find.byKey(const Key('confirm-to-allocate-distribution-button')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmer la répartition'), findsOneWidget);
      expect(
        find.textContaining('Total distribué : 15.00 MAD'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Reste dans À répartir : 10.00 MAD'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Confirmer').last);
      await tester.pumpAndSettle();

      final allocations =
          gateway.request?['p_destination_allocations']
              as List<Map<String, Object?>>?;
      expect(allocations, hasLength(2));
      expect(allocations![0]['envelope_id'], userEnvelope.id);
      expect(allocations[0]['amount'], '10.00');
      expect(allocations[1]['envelope_id'], zeroEnvelope.id);
      expect(allocations[1]['amount'], '5.00');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Répartir bloque un montant supérieur au solde disponible', (
    tester,
  ) async {
    await pumpDashboard(
      tester,
      const Size(1000, 760),
      envelopes: const [availableSystemEnvelope, userEnvelope],
    );
    await tester.tap(find.byKey(const Key('distribute-to-allocate-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('to-allocate-destination-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(userEnvelope.name).last);
    await tester.enterText(find.byKey(const Key('to-allocate-amount-0')), '30');
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-to-allocate-distribution-button')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('dépasse le solde disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
