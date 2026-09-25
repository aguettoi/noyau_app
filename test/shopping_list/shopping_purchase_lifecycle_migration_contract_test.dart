import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20260924235438_shopping_purchase_lifecycle.sql',
  ).readAsStringSync();

  test('le rattachement Shopping reste une preuve d une dépense canonique', () {
    expect(sql, contains('purchase_shopping_item_with_expense'));
    expect(sql, contains("v_event.event_type <> 'cash_expense'"));
    expect(sql, contains("and type = 'expense'"));
    expect(sql, contains("status = 'purchased'"));
    expect(sql, isNot(contains('insert into public.financial_events')));
    expect(sql, isNot(contains('insert into public.financial_transactions')));
    expect(sql, isNot(contains('insert into public.envelope_movements')));
  });

  test('protège le double rattachement et conserve une trace append-only', () {
    expect(
      sql,
      contains('shopping_items_purchased_financial_event_unique_idx'),
    );
    expect(sql, contains("action in ("));
    expect(sql, contains("'purchased'"));
    expect(sql, contains('insert into public.shopping_item_history'));
    expect(sql, contains('for update'));
  });
}
