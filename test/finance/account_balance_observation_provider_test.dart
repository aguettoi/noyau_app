import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:noyau_app/features/finance/application/providers/account_balance_observation_provider.dart';
import 'package:noyau_app/features/finance/application/providers/active_household_provider.dart';

void main() {
  ProviderContainer container(_Gateway gateway) => ProviderContainer(
    overrides: [
      activeHouseholdProvider.overrideWith(
        (ref) async => const ActiveHouseholdState(
          status: ActiveHouseholdStatus.singleHousehold,
          householdId: 'household-1',
        ),
      ),
      accountBalanceObservationGatewayProvider.overrideWithValue(gateway),
    ],
  );

  test(
    'le dernier constat conserve le foyer et aucun solde théorique mutable',
    () async {
      final gateway = _Gateway();
      final scope = container(gateway);
      addTearDown(scope.dispose);

      final observation = await scope.read(
        latestAccountBalanceObservationProvider('bank-1').future,
      );

      expect(gateway.readHouseholdId, 'household-1');
      expect(gateway.readAccountId, 'bank-1');
      expect(observation!.actualBalance, Money.fromMinorUnits(100050));
      expect(observation.actorName, 'Ibrahim');
    },
  );

  test(
    'un constat est une observation append-only, sans montant GL ou enveloppe',
    () async {
      final gateway = _Gateway();
      final scope = container(gateway);
      addTearDown(scope.dispose);

      await scope.read(recordAccountBalanceObservationProvider)(
        accountId: 'cash-1',
        observedAt: DateTime.utc(2026, 10, 1, 8, 30),
        actualBalance: Money.fromMinorUnits(23500),
        reason: 'Comptage ouverture',
      );

      expect(gateway.recordedAccountId, 'cash-1');
      expect(gateway.recordedActualBalance, Money.fromMinorUnits(23500));
      expect(gateway.recordedReason, 'Comptage ouverture');
      expect(gateway.glMutationRequested, isFalse);
      expect(gateway.envelopeMutationRequested, isFalse);
    },
  );

  test(
    'un commentaire vide est rejeté avant toute écriture distante',
    () async {
      final gateway = _Gateway();
      final scope = container(gateway);
      addTearDown(scope.dispose);

      await expectLater(
        scope.read(recordAccountBalanceObservationProvider)(
          accountId: 'bank-1',
          observedAt: DateTime.utc(2026, 10, 1),
          actualBalance: Money.fromMinorUnits(100),
          reason: ' ',
        ),
        throwsStateError,
      );
      expect(gateway.recordedAccountId, isNull);
    },
  );
}

class _Gateway implements AccountBalanceObservationGateway {
  String? readHouseholdId;
  String? readAccountId;
  String? recordedAccountId;
  Money? recordedActualBalance;
  String? recordedReason;
  bool glMutationRequested = false;
  bool envelopeMutationRequested = false;

  @override
  Future<AccountBalanceObservation?> fetchLatest({
    required String householdId,
    required String accountId,
  }) async {
    readHouseholdId = householdId;
    readAccountId = accountId;
    return AccountBalanceObservation(
      id: 'observation-1',
      accountId: accountId,
      actualBalance: Money.fromMinorUnits(100050),
      observedAt: DateTime.utc(2026, 10, 1, 8),
      reason: 'Relevé bancaire',
      actorId: 'actor-1',
      actorName: 'Ibrahim',
      createdAt: DateTime.utc(2026, 10, 1, 8),
    );
  }

  @override
  Future<void> record({
    required String accountId,
    required DateTime observedAt,
    required Money actualBalance,
    required String reason,
  }) async {
    recordedAccountId = accountId;
    recordedActualBalance = actualBalance;
    recordedReason = reason;
  }
}
