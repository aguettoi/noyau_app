import 'package:flutter_test/flutter_test.dart';
import 'package:noyau_app/features/finance/data/local_accounts_repository.dart';
import 'package:noyau_app/features/finance/domain/financial_account.dart';
import 'package:noyau_app/core/money/money.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'initialise les cinq comptes sans duplication après redémarrage',
    () async {
      final first = LocalAccountsRepository(
        await SharedPreferences.getInstance(),
      );
      await first.seedInitialAccounts();
      final second = LocalAccountsRepository(
        await SharedPreferences.getInstance(),
      );
      await second.seedInitialAccounts();
      expect(await second.all(), hasLength(5));
    },
  );
  test('conserve modification, archivage et réactivation', () async {
    final repo = LocalAccountsRepository(await SharedPreferences.getInstance());
    await repo.seedInitialAccounts();
    final account = (await repo.all()).first;
    await repo.save(
      account.copyWith(name: 'Espèces foyer', archivedAt: DateTime(2026)),
    );
    expect((await repo.all()).first.isArchived, isTrue);
    await repo.save((await repo.all()).first.copyWith(clearArchivedAt: true));
    expect((await repo.all()).first.isArchived, isFalse);
    await repo.save(
      FinancialAccount(
        id: 'new',
        name: 'Nouveau',
        type: FinancialAccountType.savings,
        openingBalance: const Money.fromMinorUnits(0),
      ),
    );
    expect(await repo.all(), hasLength(6));
  });
}
