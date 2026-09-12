import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/202608050002_envelope_ledger.sql',
  ).readAsStringSync();
  final debtCompatibilityMigration = File(
    'supabase/migrations/202608100001_financial_event_debt_envelope_group_compatibility.sql',
  ).readAsStringSync();
  final debtCompatibilityRepairMigration = File(
    'supabase/migrations/20260903200055_debt_expense_envelope_consumption_compatibility.sql',
  ).readAsStringSync();

  test(
    'le journal des enveloppes est append-only, isolé par foyer et calculé',
    () {
      expect(
        migration,
        contains('create table if not exists public.envelope_movements'),
      );
      expect(
        migration,
        contains('amount numeric(14, 2) not null check (amount > 0)'),
      );
      expect(migration, contains('envelope_movements_envelope_household_fk'));
      expect(
        migration,
        contains('envelope_movements_transaction_household_fk'),
      );
      expect(migration, contains('envelope_movements_creator_household_fk'));
      expect(migration, contains('envelope_movements_reversal_household_fk'));
      expect(migration, contains('enable row level security'));
      expect(migration, contains('for select'));
      expect(
        migration,
        contains(
          'revoke insert, update, delete, truncate on table public.envelope_movements',
        ),
      );
      expect(
        migration,
        contains(
          'grant select on table public.envelope_movements to authenticated',
        ),
      );
      expect(migration, contains('prevent_envelope_movement_mutation'));
      expect(migration, contains('before update or delete'));
      expect(migration, contains('public.envelope_ledger_balances'));
    },
  );

  test('la migration protège l’enveloppe système et les groupes atomiques', () {
    expect(migration, contains("'to_allocate'"));
    expect(migration, contains('envelopes_household_system_code_unique'));
    expect(migration, contains('protect_system_envelope'));
    expect(migration, contains('assert_envelope_movement_group'));
    expect(migration, contains("movement_type = 'transfer_in'"));
    expect(migration, contains("movement_type = 'transfer_out'"));
    expect(migration, contains('envelope_movements_single_reversal_idx'));
    expect(migration, contains('public.create_envelope_transfer'));
    expect(migration, contains('security definer'));
  });

  test(
    'le transfert est contrôlé sans parenthèse ambiguë et la migration est rejouable',
    () {
      expect(
        migration,
        contains(
          "movement_type = 'transfer_in') <> 1\n    or (select count(*)",
        ),
      );
      expect(
        migration,
        contains(
          "movement_type = 'transfer_out') <> 1\n    or (select count(distinct envelope_id)",
        ),
      );
      expect(
        migration,
        contains('create table if not exists public.envelope_movements'),
      );
      expect(
        migration,
        contains('drop policy if exists "members read envelope movements"'),
      );
      expect(
        migration,
        contains('drop trigger if exists envelope_movements_group_valid'),
      );
      expect(
        migration,
        contains('create or replace view public.envelope_ledger_balances'),
      );
    },
  );

  test(
    'la consommation FinancialEvent accepte dette sans affaiblir le split',
    () {
      expect(
        debtCompatibilityMigration,
        contains("v_transaction_type not in ('expense', 'debt_expense')"),
      );
      expect(
        debtCompatibilityMigration,
        contains('v_total <> v_transaction_amount'),
      );
      expect(debtCompatibilityMigration, contains('v_count <> 2'));
      expect(migration, contains('deferrable initially deferred'));
    },
  );

  test('le correctif rétablit exclusivement la consommation debt_expense', () {
    expect(
      debtCompatibilityRepairMigration,
      contains("v_transaction_type not in ('expense','debt_expense')"),
    );
    expect(
      debtCompatibilityRepairMigration,
      contains("v_event_type='cash_income'"),
    );
    expect(
      debtCompatibilityRepairMigration,
      contains("v_event_type='budget_allocation'"),
    );
    expect(
      debtCompatibilityRepairMigration,
      contains("v_transaction_type<>'allocation'"),
    );
    expect(
      debtCompatibilityRepairMigration,
      contains("movement_type='transfer_out'"),
    );
  });
}
