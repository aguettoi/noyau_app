import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260903182207_budget_allocation_direct_envelope.sql',
  ).readAsStringSync();
  final sqlTest = File(
    'docs/SANDBOX_BUDGET_ALLOCATION_DIRECT_ENVELOPE_TEST.sql',
  ).readAsStringSync();

  test(
    'une allocation directe crédite une enveloppe ordinaire sans À répartir',
    () {
      expect(
        migration,
        contains(
          'Budget allocation must fund one ordinary destination envelope directly',
        ),
      );
      expect(
        migration,
        contains("v_group_id, 'allocation', 'inflow', p_amount"),
      );
      expect(migration, isNot(contains('v_to_allocate_envelope_id')));
      expect(migration, isNot(contains("'transfer_out', 'outflow', p_amount")));
      expect(migration, contains("v_transaction_type <> 'allocation'"));
      expect(migration, contains('not coalesce(v_all_ordinary, false)'));
    },
  );

  test('le contrat conserve cash_income et sa destination système', () {
    expect(migration, contains("v_event_type = 'cash_income'"));
    expect(migration, contains("v_transaction_type <> 'income'"));
    expect(migration, contains("v_event_type = 'cash_income'"));
    expect(
      migration,
      contains('Income envelope allocations must equal the income amount'),
    );
  });

  test(
    'la recette SQL couvre compte, plusieurs financements, atomicité et revenu',
    () {
      expect(sqlTest, contains('v_before_to_allocate'));
      expect(sqlTest, contains("v_tag || '_MULTI_A'"));
      expect(sqlTest, contains("v_tag || '_MULTI_DEST_B'"));
      expect(sqlTest, contains("v_tag || '_INVALID'"));
      expect(sqlTest, contains("v_tag || '_INCOME'"));
      expect(sqlTest, contains('rollback;'));
    },
  );
}
