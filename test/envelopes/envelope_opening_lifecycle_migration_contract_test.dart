import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202608080002_envelope_opening_and_lifecycle.sql',
  ).readAsStringSync();

  test('l’ouverture est un groupe immuable équilibré avec À répartir', () {
    expect(migration, contains("'opening'"));
    expect(migration, contains("'opening_offset'"));
    expect(migration, contains('assert_envelope_opening_group'));
    expect(migration, contains("'to_allocate'"));
    expect(migration, contains('v_opening_amount <> v_offset_amount'));
  });

  test(
    'le cycle de vie protège le système et interdit la suppression avec historique',
    () {
      expect(migration, contains('delete_household_envelope'));
      expect(
        migration,
        contains('Envelope with ledger history must be archived'),
      );
      expect(migration, contains('not is_system'));
      expect(migration, contains('update_household_envelope'));
      expect(migration, contains('undo_last_envelope_import'));
    },
  );

  test(
    'l’import conserve une session, le créateur et un rollback transactionnel',
    () {
      expect(migration, contains('envelope_import_sessions'));
      expect(migration, contains('import_session_id'));
      expect(migration, contains('created_by'));
      expect(migration.trimLeft(), startsWith('--'));
      expect(migration, contains('begin;'));
      expect(migration, contains('commit;'));
    },
  );

  test('initialise une enveloppe historique vide une seule fois', () {
    expect(migration, contains('v_initialized_existing integer := 0'));
    expect(
      migration,
      contains('cannot receive a retrospective opening balance'),
    );
    expect(migration, contains('envelope_import_session_envelopes'));
    expect(
      migration,
      contains("'initialized_existing', v_initialized_existing"),
    );
    expect(migration, contains("summary <> '{}'::jsonb"));
  });

  test(
    'annuler conserve les enveloppes préexistantes et contrepasse leur ouverture',
    () {
      expect(
        migration,
        contains("movement_type in ('opening', 'opening_offset')"),
      );
      expect(migration, contains("movement_type, direction,"));
      expect(migration, contains('session_envelopes.created_envelope'));
      expect(migration, contains("'reversal'"));
    },
  );

  test(
    'l’ouverture ne touche que À répartir et jamais le grand livre bancaire',
    () {
      expect(
        migration,
        contains("v_system_code is distinct from 'to_allocate'"),
      );
      expect(migration, isNot(contains('financial_transaction_lines')));
      expect(migration, isNot(contains('account_ledger_balances')));
    },
  );

  test(
    'les enveloppes ne sont plus modifiables directement par authenticated',
    () {
      expect(
        migration,
        contains('revoke insert, update, delete, truncate on public.envelopes'),
      );
      expect(
        migration,
        contains('drop policy if exists "members manage envelopes"'),
      );
      expect(migration, contains('create policy "members read envelopes"'));
    },
  );

  test(
    'les metadonnees sont modifiables sans rendre le solde initial editable',
    () {
      final updateFunction = migration.substring(
        migration.indexOf(
          'create or replace function public.update_household_envelope',
        ),
        migration.indexOf(
          'create or replace function public.delete_household_envelope',
        ),
      );

      expect(updateFunction, contains('p_name text'));
      expect(updateFunction, contains('p_notes text'));
      expect(updateFunction, contains('p_archived boolean'));
      expect(updateFunction, isNot(contains('p_opening_balance')));
      expect(updateFunction, isNot(contains('envelope_movements')));
    },
  );

  test('la creation manuelle reutilise le flux opening idempotent', () {
    final createFunction = migration.substring(
      migration.indexOf(
        'create or replace function public.create_household_envelope',
      ),
      migration.indexOf(
        'create or replace function public.undo_last_envelope_import',
      ),
    );

    expect(createFunction, contains('import_household_envelopes'));
    expect(createFunction, contains("source = 'manual'"));
    expect(createFunction, contains('p_opening_balance numeric default 0'));
  });

  test(
    'undo refuse toute activite posterieure et contrepasse les deux mouvements',
    () {
      final undoFunction = migration.substring(
        migration.indexOf(
          'create or replace function public.undo_last_envelope_import',
        ),
        migration.indexOf(
          'revoke all on function public.import_household_envelopes',
        ),
      );

      expect(
        undoFunction,
        contains('Import cannot be undone after later envelope activity'),
      );
      expect(
        undoFunction,
        contains("movement_type in ('opening', 'opening_offset')"),
      );
      expect(
        undoFunction,
        contains(
          "case when v_movement.direction = 'inflow' then 'outflow' else 'inflow' end",
        ),
      );
      expect(undoFunction, contains('and session_envelopes.created_envelope'));
    },
  );
}
