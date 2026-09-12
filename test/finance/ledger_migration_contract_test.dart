import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/202608050001_ledger_double_entry.sql',
  ).readAsStringSync();

  test(
    'le backfill utilise explicitement le montant de la ligne historique',
    () {
      expect(
        sql,
        contains('when lines.amount > 0 then lines.amount else 0 end'),
      );
      expect(
        sql,
        contains('when lines.amount < 0 then -lines.amount else 0 end'),
      );
    },
  );

  test('le backfill ne réécrit pas une écriture déjà convertie', () {
    expect(sql, contains('where lines.debit = 0'));
    expect(sql, contains('and lines.credit = 0'));
    expect(sql, contains('and lines.amount <> 0'));
  });

  test(
    'la migration est transactionnelle et réinstalle le trigger sans doublon',
    () {
      expect(sql, contains('begin;'));
      expect(sql.trimRight(), endsWith('commit;'));
      expect(
        sql,
        contains('drop trigger if exists financial_transaction_lines_balanced'),
      );
    },
  );

  test('la contrainte SQL refuse des écritures déséquilibrées', () {
    expect(sql, contains('v_debits <> v_credits or v_debits = 0'));
    expect(sql, contains('financial_transaction_lines_debit_credit_check'));
  });
}
