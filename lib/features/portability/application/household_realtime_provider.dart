import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/global_refresh_provider.dart';
import '../../finance/application/providers/active_household_provider.dart';
import '../../finance/application/providers/supabase_client_provider.dart';
import '../../finance/application/providers/remote_accounts_provider.dart';
import '../../finance/application/providers/remote_account_balances_provider.dart';
import '../../finance/application/providers/remote_transactions_provider.dart';
import '../../finance/application/providers/remote_debts_provider.dart';
import '../../finance/application/providers/member_compensations_provider.dart';
import '../../envelopes/application/providers/remote_envelopes_provider.dart';
import '../../savings_goals/application/providers/remote_savings_goals_provider.dart';
import '../../shopping_list/application/providers/remote_shopping_list_provider.dart';
import '../../priorities/application/providers/remote_priority_plans_provider.dart';
import '../../organization/application/organization_provider.dart';
import '../../wealth/application/providers/wealth_provider.dart';

enum SyncConnectionState { connecting, synchronized, reconnecting, offline }

final syncConnectionStateProvider = StateProvider<SyncConnectionState>(
  (ref) => SyncConnectionState.connecting,
);

final householdRealtimeProvider = Provider<void>((ref) {
  final household = ref.watch(activeHouseholdProvider).valueOrNull;
  final user = ref.watch(currentUserIdProvider);
  final id = household?.householdId;
  if (id == null || user == null) return;
  final client = ref.watch(optionalSupabaseClientProvider);
  if (client == null) return;
  final channel = client.channel('household:$id');
  const tables = [
    'accounts',
    'envelopes',
    'financial_events',
    'obligations',
    'member_compensations',
    'budget_goals',
    'shopping_items',
    'priority_plans',
    'household_tasks',
    'wealth_assets',
  ];
  for (final table in tables) {
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: table,
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'household_id',
        value: id,
      ),
      callback: (_) {
        _invalidateTable(ref, table);
      },
    );
  }
  channel.subscribe((status, _) {
    ref.read(syncConnectionStateProvider.notifier).state = switch (status) {
      RealtimeSubscribeStatus.subscribed => SyncConnectionState.synchronized,
      RealtimeSubscribeStatus.timedOut ||
      RealtimeSubscribeStatus.channelError => SyncConnectionState.reconnecting,
      RealtimeSubscribeStatus.closed => SyncConnectionState.offline,
    };
    if (status == RealtimeSubscribeStatus.subscribed) {
      ref.read(globalRefreshActionProvider)();
    }
  });
  // Unsubscribe this household without tearing down the shared socket: a
  // household switch may subscribe the replacement channel immediately.
  ref.onDispose(() => unawaited(channel.unsubscribe()));
});

void _invalidateTable(Ref ref, String table) {
  switch (table) {
    case 'accounts':
      ref.invalidate(remoteAccountsProvider);
      ref.invalidate(remoteAccountBalancesProvider);
      break;
    case 'envelopes':
      ref.invalidate(remoteEnvelopeHistoryProvider);
      ref.invalidate(remoteEnvelopeBalancesProvider);
      break;
    case 'financial_events':
      ref.invalidate(remoteTransactionsProvider);
      break;
    case 'obligations':
      ref.invalidate(remoteDebtBalancesProvider);
      ref.invalidate(remoteReceivableBalancesProvider);
      break;
    case 'member_compensations':
      ref.invalidate(memberCompensationsProvider);
      ref.invalidate(organizationAlertsProvider);
      break;
    case 'budget_goals':
      ref.invalidate(savingsGoalsProvider);
      break;
    case 'shopping_items':
      ref.invalidate(shoppingItemsProvider);
      break;
    case 'priority_plans':
      ref.invalidate(priorityPlansProvider);
      break;
    case 'household_tasks':
      ref.invalidate(householdTasksProvider);
      ref.invalidate(organizationCalendarProvider);
      ref.invalidate(organizationAlertsProvider);
      break;
    case 'wealth_assets':
      ref.invalidate(wealthDataProvider);
      break;
  }
}
