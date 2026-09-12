import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202608080003_financial_events_obligations.sql',
  ).readAsStringSync();
  final orchestration = File(
    'supabase/migrations/202608080004_financial_event_orchestration.sql',
  ).readAsStringSync();
  final preflight = File(
    'docs/SANDBOX_FINANCIAL_EVENTS_PRE_MIGRATION.sql',
  ).readAsStringSync();
  final postflight = File(
    'docs/SANDBOX_FINANCIAL_EVENTS_POST_MIGRATION.sql',
  ).readAsStringSync();
  final after080003 = File(
    'docs/SANDBOX_FINANCIAL_EVENTS_AFTER_080003.sql',
  ).readAsStringSync();
  final after080004 = File(
    'docs/SANDBOX_FINANCIAL_EVENTS_AFTER_080004.sql',
  ).readAsStringSync();
  final businessPrecheck = File(
    'docs/SANDBOX_FINANCIAL_EVENTS_BUSINESS_TEST_PRECHECK.sql',
  ).readAsStringSync();
  final businessTest = File(
    'docs/SANDBOX_FINANCIAL_EVENTS_BUSINESS_TEST.sql',
  ).readAsStringSync();
  final businessPostcheck = File(
    'docs/SANDBOX_FINANCIAL_EVENTS_BUSINESS_TEST_POSTCHECK.sql',
  ).readAsStringSync();
  final businessCleanup = File(
    'docs/SANDBOX_FINANCIAL_EVENTS_BUSINESS_TEST_CLEANUP.sql',
  ).readAsStringSync();
  final failedBusinessTestDiagnostic = File(
    'docs/SANDBOX_FINANCIAL_EVENTS_FAILED_BUSINESS_TEST_DIAGNOSTIC.sql',
  ).readAsStringSync();

  test('introduit FinancialEvent comme racine immutable multi-ledgers', () {
    expect(
      migration,
      contains('create table if not exists public.financial_events'),
    );
    expect(migration, contains('event_id uuid'));
    expect(migration, contains('financial_transactions_event_household_fk'));
    expect(migration, contains('envelope_movements_event_household_fk'));
    expect(migration, contains('financial_events_immutable'));
  });

  test('modele les obligations et les paiements partiels calcules', () {
    expect(
      migration,
      contains('create table if not exists public.obligations'),
    );
    expect(
      migration,
      contains('create table if not exists public.obligation_settlements'),
    );
    expect(
      migration,
      contains('create or replace view public.obligation_balances'),
    );
    expect(migration, contains('remaining_amount'));
    expect(migration, contains('obligation_settlements_limit'));
    expect(migration, contains("obligation_kind in ('debt', 'receivable')"));
    expect(migration, contains('recovery_source_event_id'));
    expect(migration, contains('description text not null'));
  });

  test('trace les allocations sans reservation stricte ni mouvement cash', () {
    expect(
      migration,
      contains('create table if not exists public.budget_funding_links'),
    );
    expect(migration, contains('source_account_id'));
    expect(migration, contains('envelope_id'));
    expect(migration, isNot(contains('reserved_amount')));
  });

  test('protege les nouveaux referentiels par RLS lecture seule', () {
    expect(migration, contains('enable row level security'));
    expect(migration, contains('revoke all on public.financial_events'));
    expect(migration, contains('members read obligations'));
    expect(migration.trimRight(), endsWith('commit;'));
  });

  test('orchestration cree les huit contrats FinancialEvent atomiques', () {
    const rpcNames = <String>[
      'create_cash_expense_event',
      'create_debt_expense_event',
      'settle_debt_event',
      'create_income_receivable_event',
      'settle_receivable_event',
      'create_recovery_receivable_event',
      'settle_recovery_event',
      'allocate_budget_event',
      'create_account_transfer_event',
      'create_envelope_transfer_event',
    ];

    for (final rpcName in rpcNames) {
      expect(
        orchestration,
        contains('create or replace function public.$rpcName'),
        reason: '$rpcName doit être exposée comme RPC atomique.',
      );
    }
    expect(orchestration, contains('begin;'));
    expect(orchestration.trimRight(), endsWith('commit;'));
  });

  test('orchestration rattache event_id aux insertions sans backfill', () {
    expect(
      orchestration,
      contains('event_id, type, occurred_at, reason, description, amount'),
    );
    expect(
      orchestration,
      contains('household_id, event_id, envelope_id, financial_transaction_id'),
    );
    expect(orchestration, isNot(contains('set event_id =')));
  });

  test('orchestration applique idempotence, isolation et permissions', () {
    expect(
      orchestration,
      contains('on conflict (household_id, idempotency_key) do nothing'),
    );
    expect(orchestration, contains('Household access denied'));
    expect(orchestration, contains('from public, anon;'));
    expect(orchestration, contains('to authenticated;'));
  });

  test('diagnostics FinancialEvent tolerent les objets futurs absents', () {
    expect(preflight, contains("to_regclass('public.financial_transactions')"));
    expect(preflight, isNot(contains('financial_events_already_exists')));
    expect(preflight, isNot(contains('::regclass')));
    expect(postflight, isNot(contains('::regclass')));
    expect(preflight, contains('create_cash_expense_event'));
    expect(postflight, contains('obligation_balances'));
  });

  test('préflight termine par une synthèse unique réellement calculée', () {
    for (final field in const [
      'pre_migration_ready',
      'blocking_issue_count',
      'missing_prerequisite_count',
      'conflict_count',
      'blocking_details',
      'warnings',
    ]) {
      expect(
        preflight,
        contains(field),
        reason: '$field doit être synthétisé.',
      );
    }
    expect(preflight, contains('not exists (select 1 from diagnostics)'));
    expect(preflight, contains('jsonb_agg(diagnostics.detail'));
  });

  test('checkpoint après 080003 contrôle le socle avant 080004', () {
    for (final field in const [
      'after_080003_ready',
      'ready_for_080004',
      'legacy_financial_transactions_event_id_null_count',
      'legacy_envelope_movements_event_id_null_count',
      'dependencies_for_080004_ready',
    ]) {
      expect(after080003, contains(field));
    }
    expect(after080003, isNot(contains('::regclass')));
    expect(after080003, contains('obligation_kind_check'));
    expect(after080003, contains('receivable_kind_check'));
  });

  test('checkpoint après 080004 contrôle chaque RPC métier', () {
    for (final rpc in const [
      'create_cash_expense_event',
      'create_debt_expense_event',
      'settle_debt_event',
      'create_income_receivable_event',
      'settle_receivable_event',
      'create_recovery_receivable_event',
      'settle_recovery_event',
      'allocate_budget_event',
      'create_account_transfer_event',
      'create_envelope_transfer_event',
    ]) {
      expect(after080004, contains("('$rpc'"));
    }
    expect(after080004, contains('after_080004_ready'));
    expect(after080004, contains('ready_for_business_tests'));
  });

  test('precheck métier sélectionne un membre sans agrégat UUID', () {
    expect(businessPrecheck, isNot(contains('min(members.user_id)')));
    expect(businessPrecheck, isNot(contains('max(members.user_id)')));
    expect(
      businessPrecheck,
      contains('order by members.household_id, members.user_id'),
    );
  });

  test('recette Sandbox isole les données et couvre les RPC métier', () {
    expect(businessTest, contains('TEST_FE_20260809'));
    expect(businessTest, contains('receipt collision already exists'));
    expect(businessTest, contains('request.jwt.claims'));
    expect(businessTest, contains("current_user <> 'authenticated'"));
    expect(
      businessTest,
      contains('auth.uid() is distinct from context.actor_id'),
    );
    for (final rpc in const [
      'create_cash_expense_event',
      'create_debt_expense_event',
      'settle_debt_event',
      'create_income_receivable_event',
      'settle_receivable_event',
      'create_recovery_receivable_event',
      'settle_recovery_event',
      'allocate_budget_event',
      'create_account_transfer_event',
      'create_envelope_transfer_event',
    ]) {
      expect(businessTest, contains(rpc));
    }
    expect(businessTest, contains('rollback_atomicity'));
    expect(businessTest, contains('v_event_id uuid'));
    expect(businessTest, isNot(contains('where event_id=cash_id')));
  });

  test('postcheck est indépendant, calculé et read-only', () {
    expect(businessPostcheck, contains('business_postcheck_ready'));
    expect(businessPostcheck, contains('blocking_issue_count'));
    expect(businessPostcheck, isNot(contains('true as')));
    expect(businessPostcheck, isNot(contains('insert into')));
    expect(businessPostcheck, isNot(contains('update public.')));
    expect(businessPostcheck, isNot(contains('delete from')));
  });

  test('cleanup reste borné et refuse de contourner l’immutabilité', () {
    expect(businessCleanup, contains('scope_unambiguous'));
    expect(businessCleanup, contains('cleanup_executed'));
    expect(businessCleanup, isNot(contains('delete from')));
    expect(businessCleanup, isNot(contains('update public.')));
    expect(businessCleanup, contains('future audited reversal RPC'));
  });

  test('diagnostic d’échec contrôle uniquement le périmètre de recette', () {
    expect(failedBusinessTestDiagnostic, contains('failed_attempt_clean'));
    expect(failedBusinessTestDiagnostic, contains('TEST_FE_20260809'));
    expect(failedBusinessTestDiagnostic, isNot(contains('insert into')));
    expect(failedBusinessTestDiagnostic, isNot(contains('update public.')));
    expect(failedBusinessTestDiagnostic, isNot(contains('delete from')));
  });
}
