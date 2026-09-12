import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202608100003_budget_allocation_run_application.sql',
  ).readAsStringSync();

  test('applique un run côté serveur via allocate_budget_event', () {
    expect(
      migration,
      contains('create or replace function public.apply_budget_allocation_run'),
    );
    expect(migration, contains('public.allocate_budget_event('));
    expect(migration, isNot(contains('insert into public.envelope_movements')));
  });

  test('refuse le partiel et conserve une idempotence par run', () {
    expect(migration, contains("if v_status <> 'approved'"));
    expect(migration, contains("if v_remaining < 0"));
    expect(migration, contains('application_idempotency_key'));
    expect(migration, contains("if v_status = 'applied'"));
  });

  test('le financement multi-comptes reste atomique et détaille chaque source', () {
    final multiAccountMigration = File(
      'supabase/migrations/202608100007_budget_allocation_run_multi_account_funding.sql',
    ).readAsStringSync();
    expect(
      multiAccountMigration,
      contains('apply_budget_allocation_run_with_funding'),
    );
    expect(
      multiAccountMigration,
      contains('budget_allocation_run_funding_lines'),
    );
    expect(
      multiAccountMigration,
      contains(
        'foreign key (run_line_id)\n'
        '    references public.budget_allocation_run_lines(id) on delete restrict',
      ),
    );
    expect(
      multiAccountMigration,
      isNot(
        contains(
          'references public.budget_allocation_run_lines(id, household_id)',
        ),
      ),
    );
    expect(
      multiAccountMigration,
      contains('Funding total must equal the budget run total'),
    );
    expect(
      multiAccountMigration,
      contains('Funding must equal the planned amount for every envelope'),
    );
    expect(multiAccountMigration, contains('public.allocate_budget_event('));
    expect(
      multiAccountMigration,
      isNot(contains('insert into public.financial_transactions')),
    );
  });

  test(
    'une allocation débite le compte et bloque le financement insuffisant',
    () {
      final accountDebitMigration = File(
        'supabase/migrations/202608100008_budget_allocation_account_debit.sql',
      ).readAsStringSync();
      expect(accountDebitMigration, contains("when 'to_allocate'"));
      expect(
        accountDebitMigration,
        contains('public.insert_financial_event_ledger_transaction('),
      );
      expect(accountDebitMigration, contains("'allocation'"));
      expect(
        accountDebitMigration,
        contains('Insufficient available balance for budget allocation'),
      );
      expect(
        accountDebitMigration,
        contains('group by (item.value ->> \'source_account_id\')::uuid'),
      );
      expect(accountDebitMigration, contains('for update of accounts'));
      expect(
        accountDebitMigration,
        contains('Insufficient available balance for account %'),
      );
      expect(
        accountDebitMigration,
        contains('financial_transaction_id, envelope_id'),
      );
      expect(
        accountDebitMigration,
        contains('Envelope movement group must reference one FinancialEvent'),
      );
      expect(
        accountDebitMigration,
        contains(
          'A ledger-backed envelope transfer must be a budget allocation',
        ),
      );
    },
  );
}
