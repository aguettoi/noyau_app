import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20261005090000_f1_household_settings_and_membership_admin.sql',
  ).readAsStringSync().toLowerCase();

  test(
    'F1 migration is additive and exposes safe household administration',
    () {
      expect(
        migration,
        contains('add column if not exists budget_validation_mode'),
      );
      expect(migration, contains('update_my_profile'));
      expect(migration, contains('update_household_settings'));
      expect(migration, contains('list_household_invitations'));
      expect(migration, contains('revoke_household_invitation'));
      expect(migration, contains('change_household_member_role'));
      expect(migration, contains('remove_household_member'));
      expect(migration, contains('leave_household'));
      expect(migration, contains('last owner cannot'));
      expect(migration, isNot(contains('financial_events')));
      expect(migration, isNot(contains('envelope_movements')));
      expect(migration, isNot(contains('create table public.accounts')));
    },
  );
}
