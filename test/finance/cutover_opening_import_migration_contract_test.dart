import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260914184757_canonical_cutover_opening_import.sql',
  ).readAsStringSync();
  final correctionMigration = File(
    'supabase/migrations/20260914191453_cutover_b1_reconciliation_and_resume.sql',
  ).readAsStringSync();
  final ownershipMigration = File(
    'supabase/migrations/20260929203237_preserve_cutover_account_ownership.sql',
  ).readAsStringSync();
  final matchedReferencesMigration = File(
    'supabase/migrations/20260929205002_bind_cutover_matched_references.sql',
  ).readAsStringSync();
  final matchedSystemEnvelopeFix = File(
    'supabase/migrations/20260929205156_fix_cutover_matched_system_envelope.sql',
  ).readAsStringSync();
  final zeroEnvelopeMigration = File(
    'supabase/migrations/20260930192845_cutover_zero_balance_envelopes.sql',
  ).readAsStringSync();

  test('B1 persiste un run immuable et une identité de replay stable', () {
    expect(migration, contains('cutover_opening_runs'));
    expect(migration, contains('source_fingerprint'));
    expect(migration, contains('plan_fingerprint'));
    expect(
      migration,
      contains(
        'unique (household_id, source_fingerprint, effective_date, scope)',
      ),
    );
    expect(migration, contains('return v_existing.result'));
    expect(migration, contains('auth.uid()'));
  });

  test('B1 délègue exclusivement les positions aux primitives Cutover A', () {
    expect(migration, contains('create_account_opening_event'));
    expect(migration, contains('create_envelope_opening_event'));
    expect(migration, isNot(contains("'opening_offset'")));
    expect(
      migration,
      contains(
        'opening_balance)\n      values (p_household_id,v_account_name,v_kind,0)',
      ),
    );
    expect(migration, contains('automatic_correction'));
  });

  test(
    'B1 verrouille, valide le household, le fingerprint et les montants',
    () {
      expect(migration, contains('assert_household_access(p_household_id)'));
      expect(migration, contains('for update'));
      expect(migration, contains('SHA-256 source fingerprint'));
      expect(migration, contains('positive opening'));
      expect(migration, contains('Duplicate account target in plan'));
      expect(migration, contains('Duplicate envelope target in plan'));
    },
  );

  test('B1 relit les écritures persistées et restaure un run par identité', () {
    expect(correctionMigration, contains('reconcile_cutover_opening_run'));
    expect(correctionMigration, contains('financial_transaction_lines'));
    expect(correctionMigration, contains('envelope_movements'));
    expect(correctionMigration, contains('account_ledger_balances'));
    expect(correctionMigration, contains('envelope_ledger_balances'));
    expect(correctionMigration, contains("'NOT_RECONCILED'"));
    expect(correctionMigration, contains("'automatic_correction',false"));
    expect(correctionMigration, contains('get_cutover_opening_run'));
    expect(
      correctionMigration,
      contains('source_fingerprint=p_source_fingerprint'),
    );
  });

  test(
    'B1 remplace le digest public temporaire par l’appel extensions explicite',
    () {
      expect(
        correctionMigration,
        contains(
          "extensions.digest(convert_to(p_plan::text, ''UTF8''), ''sha256'')",
        ),
      );
      expect(
        correctionMigration,
        contains('drop function public.digest(text,text)'),
      );
    },
  );

  test('B1 préserve la titularité et refuse les titulaires hors foyer', () {
    expect(
      ownershipMigration,
      contains("v_ownership_type not in ('individual','shared','household')"),
    );
    expect(
      ownershipMigration,
      contains('An account holder must belong to the target household'),
    );
    expect(ownershipMigration, contains('create_account_with_holders'));
    expect(
      ownershipMigration,
      contains("v_ownership_type='household' and cardinality(v_holder_ids)<>0"),
    );
    expect(
      ownershipMigration,
      contains(
        "v_ownership_type='individual' and cardinality(v_holder_ids)<>1",
      ),
    );
    expect(
      ownershipMigration,
      contains("v_ownership_type='shared' and cardinality(v_holder_ids)<2"),
    );
  });

  test('B1 bloque un match incompatible sans réécrire sa titularité', () {
    expect(
      ownershipMigration,
      contains(
        'Existing account ownership conflicts with the confirmed cutover plan',
      ),
    );
    expect(
      ownershipMigration,
      contains('v_existing_holder_ids is distinct from v_holder_ids'),
    );
    expect(
      ownershipMigration,
      isNot(contains('update public.accounts set ownership_type')),
    );
    expect(
      ownershipMigration,
      isNot(contains('update public.account_holders')),
    );
  });

  test('B1 conserve Cutover A et n’utilise aucun mécanisme legacy', () {
    expect(ownershipMigration, contains('create_account_opening_event'));
    expect(ownershipMigration, contains('create_envelope_opening_event'));
    expect(
      ownershipMigration,
      contains(
        'create_account_with_holders(\n        p_household_id,v_account_name,v_kind,0,null',
      ),
    );
    expect(ownershipMigration, isNot(contains("'opening_offset'")));
    expect(ownershipMigration, isNot(contains('accounts.opening_balance')));
    expect(ownershipMigration, isNot(contains('automatic compensation')));
  });

  test('B1 lie chaque match au référentiel explicitement confirmé', () {
    expect(matchedReferencesMigration, contains('matched_account_id'));
    expect(matchedReferencesMigration, contains('matched_envelope_id'));
    expect(
      matchedReferencesMigration,
      contains('does not identify exactly one confirmed reference'),
    );
    expect(matchedReferencesMigration, contains('where id=v_expected_id'));
    expect(matchedReferencesMigration, contains('for update'));
    expect(
      matchedReferencesMigration,
      contains('A conflicting account reference cannot be materialized'),
    );
    expect(
      matchedReferencesMigration,
      contains('A conflicting envelope reference cannot be materialized'),
    );
  });

  test('B1 conserve le replay historique avant le nouveau contrat de match', () {
    final replayCheck = matchedReferencesMigration.indexOf(
      'if exists (\n    select 1 from public.cutover_opening_runs',
    );
    final accountValidation = matchedReferencesMigration.indexOf(
      "for v_account in select value from jsonb_array_elements(p_plan->'accounts')",
    );
    expect(replayCheck, greaterThanOrEqualTo(0));
    expect(accountValidation, greaterThan(replayCheck));
  });

  test('la liaison explicite ne réintroduit aucun mécanisme legacy', () {
    expect(matchedReferencesMigration, isNot(contains('opening_offset')));
    expect(
      matchedReferencesMigration,
      isNot(contains('accounts.opening_balance')),
    );
    expect(
      matchedReferencesMigration,
      contains('execute_cutover_opening_import_materialize'),
    );
    expect(
      matchedReferencesMigration,
      contains('reconcile_cutover_opening_run'),
    );
  });

  test('B1 utilise la colonne système canonique des enveloppes', () {
    expect(matchedSystemEnvelopeFix, contains("system_code='to_allocate'"));
    expect(
      matchedSystemEnvelopeFix,
      isNot(contains("system_key='to_allocate'")),
    );
    expect(matchedSystemEnvelopeFix, contains('matched_account_id'));
    expect(matchedSystemEnvelopeFix, contains('matched_envelope_id'));
  });

  test('Cutover crée les référentiels zéro sans mouvement financier', () {
    expect(zeroEnvelopeMigration, contains('v_amount < 0'));
    expect(zeroEnvelopeMigration, contains('if v_amount > 0 then'));
    expect(
      zeroEnvelopeMigration,
      contains("jsonb_array_length(v_envelope_openings) > 0"),
    );
    expect(
      zeroEnvelopeMigration,
      contains("'envelope_movements',jsonb_array_length(v_envelope_openings)"),
    );
    expect(zeroEnvelopeMigration, contains('ensure_household_system_envelope'));
    expect(
      zeroEnvelopeMigration,
      isNot(contains('import_household_envelopes')),
    );
    expect(zeroEnvelopeMigration, isNot(contains('opening_offset')));
  });
}
