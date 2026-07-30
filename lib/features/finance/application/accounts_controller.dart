import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local_accounts_repository.dart';
import '../domain/financial_account.dart';

final accountsProvider =
    AsyncNotifierProvider<AccountsController, List<FinancialAccount>>(
      AccountsController.new,
    );

class AccountsController extends AsyncNotifier<List<FinancialAccount>> {
  late AccountsRepository _repository;
  @override
  Future<List<FinancialAccount>> build() async {
    _repository = LocalAccountsRepository(
      await SharedPreferences.getInstance(),
    );
    await _repository.seedInitialAccounts();
    return _repository.all();
  }

  Future<void> save(FinancialAccount account) async {
    await _repository.save(account);
    state = AsyncData(await _repository.all());
  }
}
