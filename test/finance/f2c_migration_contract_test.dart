import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sql = File(
    'supabase/migrations/20261005223000_f2c_history_reversals_attachments.sql',
  ).readAsStringSync();
  test('reversal quotidien inverse les ledgers sans muter original', () {
    expect(sql, contains('reverse_daily_financial_event'));
    expect(
      sql,
      contains(
        'select v_reversal_tx_id,account_id,envelope_id,member_id,-amount,credit,debit',
      ),
    );
    expect(
      sql,
      contains(
        "'reversal',case direction when 'inflow' then 'outflow' else 'inflow' end",
      ),
    );
    expect(sql, contains('unique (original_event_id)'));
    expect(sql, isNot(contains('update public.financial_events')));
  });
  test('historique est canonique paginé et sécurisé', () {
    expect(sql, contains('with (security_invoker = true)'));
    expect(sql, contains('search_financial_event_history'));
    expect(sql, contains('limit greatest(1,least(coalesce(p_limit,50),100))'));
    expect(sql, contains('expense_payment_contexts'));
  });
  test('justificatifs privés limités et liés au FinancialEvent', () {
    expect(
      sql,
      contains(
        "values ('financial-evidence','financial-evidence',false,10485760",
      ),
    );
    expect(
      sql,
      contains("'image/jpeg','image/png','image/webp','application/pdf'"),
    );
    expect(
      sql,
      contains(
        'financial_event_id uuid not null references public.financial_events',
      ),
    );
    expect(
      sql,
      contains(
        "storage_path = household_id::text||'/'||financial_event_id::text||'/'||id::text",
      ),
    );
    expect(sql, contains('financial_evidence_select'));
    expect(sql, contains('financial_evidence_insert'));
    expect(sql, contains('financial_evidence_delete'));
  });
}
