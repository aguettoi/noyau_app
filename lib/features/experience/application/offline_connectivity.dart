import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../finance/application/providers/supabase_client_provider.dart';

enum SyncConnectionState { connecting, synchronized, reconnecting, offline }

final syncConnectionStateProvider = StateProvider<SyncConnectionState>(
  (ref) => SyncConnectionState.connecting,
);

void reportOfflineFailure(Ref ref) {
  ref.read(syncConnectionStateProvider.notifier).state =
      SyncConnectionState.offline;
}

typedef OfflineConnectivityProbe = Future<void> Function();

final offlineConnectivityProbeProvider = Provider<OfflineConnectivityProbe>((
  ref,
) {
  return () async {
    await ref
        .read(supabaseClientProvider)
        .from('household_members')
        .select('household_id')
        .limit(1);
  };
});

final offlineReconnectIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 5),
);

final offlineProbeTimeoutProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 8),
);

final offlineReconnectMonitorProvider = Provider<void>((ref) {
  Timer? timer;
  var probing = false;
  var disposed = false;

  Future<void> probe() async {
    if (probing || disposed) {
      return;
    }
    probing = true;
    final startedAt = DateTime.now();
    try {
      await ref
          .read(offlineConnectivityProbeProvider)()
          .timeout(ref.read(offlineProbeTimeoutProvider));
      if (disposed) return;
      ref.read(syncConnectionStateProvider.notifier).state =
          SyncConnectionState.synchronized;
      debugPrint(
        'offline-connectivity: probe=online '
        'durationMs=${DateTime.now().difference(startedAt).inMilliseconds}',
      );
    } catch (error) {
      if (disposed) return;
      ref.read(syncConnectionStateProvider.notifier).state =
          SyncConnectionState.offline;
      debugPrint(
        'offline-connectivity: probe=offline '
        'durationMs=${DateTime.now().difference(startedAt).inMilliseconds} '
        'errorType=${error.runtimeType}',
      );
    } finally {
      probing = false;
    }
  }

  void schedule(SyncConnectionState state) {
    timer?.cancel();
    timer = null;
    if (state == SyncConnectionState.connecting ||
        state == SyncConnectionState.offline ||
        state == SyncConnectionState.reconnecting) {
      unawaited(probe());
      timer = Timer.periodic(
        ref.read(offlineReconnectIntervalProvider),
        (_) => probe(),
      );
    }
  }

  final subscription = ref.listen<SyncConnectionState>(
    syncConnectionStateProvider,
    (_, next) => schedule(next),
    fireImmediately: true,
  );
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
    subscription.close();
  });
});
