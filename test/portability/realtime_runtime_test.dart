import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('F7_SUPABASE_URL');
const _publishableKey = String.fromEnvironment('F7_SUPABASE_PUBLISHABLE_KEY');
const _secretKey = String.fromEnvironment('F7_SUPABASE_SECRET_KEY');
const _runId = String.fromEnvironment('F7_RUNTIME_RUN_ID');

Future<void> _subscribed(RealtimeChannel channel) {
  final completer = Completer<void>();
  channel.subscribe((status, error) {
    if (status == RealtimeSubscribeStatus.subscribed &&
        !completer.isCompleted) {
      completer.complete();
    } else if ((status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut) &&
        !completer.isCompleted) {
      completer.completeError(error ?? status);
    }
  });
  return completer.future.timeout(const Duration(seconds: 20));
}

Future<SupabaseClient> _signedIn(String email, String password) async {
  final client = SupabaseClient(_url, _publishableKey);
  final response = await client.auth.signInWithPassword(
    email: email,
    password: password,
  );
  await client.realtime.setAuth(response.session!.accessToken);
  return client;
}

void main() {
  final enabled =
      _url.isNotEmpty &&
      _publishableKey.isNotEmpty &&
      _secretKey.isNotEmpty &&
      _runId.isNotEmpty;

  test(
    'two authenticated clients receive only their household realtime events',
    () async {
      final service = SupabaseClient(_url, _secretKey);
      final password = 'F7-runtime-${_runId}Aa!42';
      final emailA = 'f7-runtime-a-$_runId@example.test';
      final emailB = 'f7-runtime-b-$_runId@example.test';
      final emailC = 'f7-runtime-c-$_runId@example.test';
      final userA = (await service.auth.admin.createUser(
        AdminUserAttributes(
          email: emailA,
          password: password,
          emailConfirm: true,
        ),
      )).user!;
      final userB = (await service.auth.admin.createUser(
        AdminUserAttributes(
          email: emailB,
          password: password,
          emailConfirm: true,
        ),
      )).user!;
      final userC = (await service.auth.admin.createUser(
        AdminUserAttributes(
          email: emailC,
          password: password,
          emailConfirm: true,
        ),
      )).user!;
      final householdA =
          (await service
                  .from('households')
                  .insert({
                    'name': 'F7-RUNTIME-A-$_runId',
                    'classification': 'technical',
                  })
                  .select('id')
                  .single())['id']
              as String;
      final householdB =
          (await service
                  .from('households')
                  .insert({
                    'name': 'F7-RUNTIME-B-$_runId',
                    'classification': 'technical',
                  })
                  .select('id')
                  .single())['id']
              as String;
      await service.from('household_members').insert([
        {'household_id': householdA, 'user_id': userA.id, 'role': 'owner'},
        {'household_id': householdA, 'user_id': userB.id, 'role': 'member'},
        {'household_id': householdB, 'user_id': userB.id, 'role': 'member'},
        {'household_id': householdB, 'user_id': userC.id, 'role': 'owner'},
      ]);

      final clientA = await _signedIn(emailA, password);
      final clientB = await _signedIn(emailB, password);
      final clientC = await _signedIn(emailC, password);
      final seenByB = <String>[];
      final seenByC = <String>[];

      RealtimeChannel channelFor(
        SupabaseClient client,
        String label,
        String householdId,
        List<String> sink,
      ) {
        final channel = client.channel('f7:$label:$householdId');
        for (final table in const [
          'household_tasks',
          'financial_events',
          'member_compensations',
        ]) {
          channel.onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: table,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'household_id',
              value: householdId,
            ),
            callback: (_) => sink.add(table),
          );
        }
        return channel;
      }

      final channelB = channelFor(clientB, 'member', householdA, seenByB);
      final channelC = channelFor(clientC, 'outsider', householdA, seenByC);
      await Future.wait([_subscribed(channelB), _subscribed(channelC)]);
      expect(
        await clientB
            .from('household_members')
            .select('user_id')
            .eq('household_id', householdA),
        isNotEmpty,
      );
      expect(
        await clientC
            .from('household_members')
            .select('user_id')
            .eq('household_id', householdA),
        isEmpty,
      );
      await Future<void>.delayed(const Duration(seconds: 1));

      await clientA.from('household_tasks').insert({
        'household_id': householdA,
        'title': 'F7 runtime task',
        'idempotency_key':
            '10000000-0000-4000-8000-${_runId.padLeft(12, '0').substring(0, 12)}',
        'created_by': userA.id,
      });
      final eventId =
          (await service
                  .from('financial_events')
                  .insert({
                    'household_id': householdA,
                    'event_type': 'cash_expense',
                    'description':
                        'F7 runtime read-only synchronization fixture',
                    'occurred_at': DateTime.now().toUtc().toIso8601String(),
                    'created_by': userA.id,
                  })
                  .select('id')
                  .single())['id']
              as String;
      await service.from('member_compensations').insert({
        'household_id': householdA,
        'source_financial_event_id': eventId,
        'debtor_user_id': userA.id,
        'creditor_user_id': userB.id,
        'initial_amount': 1,
        'reason': 'F7 runtime synchronization fixture',
        'idempotency_key':
            '20000000-0000-4000-8000-${_runId.padLeft(12, '0').substring(0, 12)}',
        'created_by': userA.id,
      });
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(
        seenByB.toSet(),
        containsAll(const {
          'household_tasks',
          'financial_events',
          'member_compensations',
        }),
      );
      expect(seenByC, isEmpty, reason: 'RLS must hide household A from C');

      await channelB.unsubscribe();
      await clientB.auth.signOut();
      expect(clientB.getChannels(), isEmpty);

      await clientB.auth.signInWithPassword(email: emailB, password: password);
      final reloginEvents = <String>[];
      final relogin = channelFor(clientB, 'relogin', householdA, reloginEvents);
      await _subscribed(relogin);
      expect(clientB.getChannels(), hasLength(1));
      await clientB.realtime.disconnect();
      await relogin.unsubscribe();
      final reconnectEvents = <String>[];
      final reconnect = channelFor(
        clientB,
        'reconnect',
        householdA,
        reconnectEvents,
      );
      await _subscribed(reconnect);
      expect(clientB.getChannels(), hasLength(1));
      await service.from('household_tasks').insert({
        'household_id': householdA,
        'title': 'F7 runtime reconnect',
        'idempotency_key':
            '30000000-0000-4000-8000-${_runId.padLeft(12, '0').substring(0, 12)}',
        'created_by': userA.id,
      });
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(reconnectEvents, contains('household_tasks'));

      await reconnect.unsubscribe();
      final changedEvents = <String>[];
      final changed = channelFor(clientB, 'changed', householdB, changedEvents);
      await _subscribed(changed);
      expect(clientB.getChannels(), hasLength(1));
      await service.from('household_tasks').insert({
        'household_id': householdA,
        'title': 'F7 old household after change',
        'idempotency_key':
            '40000000-0000-4000-8000-${_runId.padLeft(12, '0').substring(0, 12)}',
        'created_by': userA.id,
      });
      await service.from('household_tasks').insert({
        'household_id': householdB,
        'title': 'F7 new household after change',
        'idempotency_key':
            '50000000-0000-4000-8000-${_runId.padLeft(12, '0').substring(0, 12)}',
        'created_by': userC.id,
      });
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(changedEvents.where((e) => e == 'household_tasks'), hasLength(1));

      await Future.wait([
        clientA.dispose(),
        clientB.dispose(),
        clientC.dispose(),
        service.dispose(),
      ]);
    },
    skip: enabled ? false : 'F7 runtime credentials are not provided',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
