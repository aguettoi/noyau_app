import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/import_execution/accounts_import_execution.dart';
import '../../application/import_models/import_account.dart';
import '../../domain/financial_account.dart';

/// Gateway injectable pour l'appel RPC atomique d'import des comptes.
abstract interface class AccountsSupabaseImportGateway {
  Future<AccountsImportTransactionResult> executeAccountsImport({
    required String householdId,
    required String importExecutionId,
    required List<Map<String, Object?>> operations,
  });
}

/// Adaptateur Supabase concret. Le client est fourni par le bootstrap existant.
class SupabaseAccountsImportGateway implements AccountsSupabaseImportGateway {
  SupabaseAccountsImportGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<AccountsImportTransactionResult> executeAccountsImport({
    required String householdId,
    required String importExecutionId,
    required List<Map<String, Object?>> operations,
  }) async {
    try {
      final response = await _client.rpc(
        'execute_accounts_import',
        params: {
          'p_household_id': householdId,
          'p_import_execution_id': importExecutionId,
          'p_operations': operations,
        },
      );
      final result = Map<String, dynamic>.from(response as Map);
      return AccountsImportTransactionResult(
        result['already_processed'] == true
            ? AccountsImportTransactionStatus.alreadyExecuted
            : AccountsImportTransactionStatus.executed,
      );
    } on Exception catch (error) {
      throw Exception('Erreur Supabase lors de l’import des comptes : $error');
    }
  }
}

/// Implémentation Supabase de la transaction utilisée par
/// [AccountsImportExecutor]. Les opérations sont collectées puis envoyées en
/// une seule RPC afin que PostgreSQL applique ou annule le lot entièrement.
class AccountsSupabaseImportRepository {
  AccountsSupabaseImportRepository({
    required this._gateway,
    required this.householdId,
  });

  final AccountsSupabaseImportGateway _gateway;
  final String householdId;

  Future<AccountsImportTransactionResult> runTransaction({
    required String importExecutionId,
    required Future<void> Function(AccountsImportTransaction transaction)
    operation,
  }) async {
    final transaction = _QueuedAccountsImportTransaction();
    await operation(transaction);
    return _gateway.executeAccountsImport(
      householdId: householdId,
      importExecutionId: importExecutionId,
      operations: transaction.operations,
    );
  }
}

class _QueuedAccountsImportTransaction implements AccountsImportTransaction {
  final _operations = <Map<String, Object?>>[];

  List<Map<String, Object?>> get operations => List.unmodifiable(_operations);

  @override
  Future<void> createAccount(ImportAccount account) async {
    _operations.add({
      'operation': 'create',
      'name': account.name,
      'kind': _accountKind(account.type),
      'opening_balance_cents': account.openingBalanceCents,
    });
  }

  @override
  Future<void> replaceOpeningBalance({
    required ImportAccount account,
    required int openingBalanceCents,
  }) async {
    _operations.add({
      'operation': 'replace_opening_balance',
      'name': account.name,
      'opening_balance_cents': openingBalanceCents,
    });
  }

  static String _accountKind(FinancialAccountType type) => switch (type) {
    FinancialAccountType.bank => 'bank',
    FinancialAccountType.cash => 'cash',
    FinancialAccountType.savings => 'savings',
    FinancialAccountType.debt => 'loan',
  };
}
