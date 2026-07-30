import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/money/money.dart';
import '../domain/financial_account.dart';

abstract interface class AccountsRepository {
  Future<List<FinancialAccount>> all();
  Future<void> seedInitialAccounts();
  Future<void> save(FinancialAccount account);
}

class LocalAccountsRepository implements AccountsRepository {
  LocalAccountsRepository(this._preferences);
  static const _key = 'financial_accounts_v1';
  final SharedPreferences _preferences;

  @override
  Future<List<FinancialAccount>> all() async {
    final raw = _preferences.getString(_key);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List<dynamic>).map(_fromJson).toList();
  }

  @override
  Future<void> seedInitialAccounts() async {
    final existing = await all();
    final ids = existing.map((item) => item.id).toSet();
    final missing = _initial.where((account) => !ids.contains(account.id));
    await _write([...existing, ...missing]);
  }

  @override
  Future<void> save(FinancialAccount account) async {
    final accounts = await all();
    final index = accounts.indexWhere((item) => item.id == account.id);
    if (index < 0) {
      await _write([...accounts, account]);
    } else {
      accounts[index] = account;
      await _write(accounts);
    }
  }

  Future<void> _write(List<FinancialAccount> accounts) =>
      _preferences.setString(_key, jsonEncode(accounts.map(_toJson).toList()));

  static final _initial = <FinancialAccount>[
    _account('cash-common', 'Espèces communes', FinancialAccountType.cash),
    _account(
      'ibrahim-arreda',
      'Compte Ibrahim ARREDA',
      FinancialAccountType.bank,
      'Ibrahim',
    ),
    _account(
      'ibrahim-cih',
      'Compte Ibrahim CIH',
      FinancialAccountType.bank,
      'Ibrahim',
    ),
    _account(
      'ibrahim-awb',
      'Compte Ibrahim AWB',
      FinancialAccountType.bank,
      'Ibrahim',
    ),
    _account('nora-awb', 'Compte Nora AWB', FinancialAccountType.bank, 'Nora'),
  ];
  static FinancialAccount _account(
    String id,
    String name,
    FinancialAccountType type, [
    String? holder,
  ]) => FinancialAccount(
    id: id,
    name: name,
    type: type,
    holder: holder,
    openingBalance: const Money.fromMinorUnits(0),
  );
  static Map<String, Object?> _toJson(FinancialAccount a) => {
    'id': a.id,
    'name': a.name,
    'type': a.type.name,
    'holder': a.holder,
    'opening': a.openingBalance.minorUnits,
    'archived': a.archivedAt?.toIso8601String(),
    'created': a.createdAt.toIso8601String(),
    'updated': a.updatedAt.toIso8601String(),
  };
  static FinancialAccount _fromJson(dynamic value) {
    final v = value as Map<String, dynamic>;
    return FinancialAccount(
      id: v['id'] as String,
      name: v['name'] as String,
      type: FinancialAccountType.values.byName(v['type'] as String),
      holder: v['holder'] as String?,
      openingBalance: Money.fromMinorUnits(v['opening'] as int),
      archivedAt: v['archived'] == null
          ? null
          : DateTime.parse(v['archived'] as String),
      createdAt: DateTime.parse(v['created'] as String),
      updatedAt: DateTime.parse(v['updated'] as String),
    );
  }
}
