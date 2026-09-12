import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260912095721_obligation_settlement_reversal_ledger_sides.sql',
  ).readAsStringSync();

  test('inverse les postings GL du reversal de règlement de dette', () {
    expect(
      migration,
      contains("p_amount,v_account_id,null,v_account_id,v_debt_id,p_notes"),
    );
    expect(
      migration,
      isNot(
        contains(
          "p_amount,v_debt_id,v_account_id,v_debt_id,v_account_id,p_notes",
        ),
      ),
    );
  });

  test('préserve les côtés inverses déjà corrects pour Income et Recovery', () {
    expect(
      migration,
      contains(
        "p_amount,v_account_id,null,v_receivable_id,v_account_id,p_notes",
      ),
    );
    expect(migration, contains("movement_type='refund'"));
    expect(migration, contains("'reversal','outflow'"));
  });
}
