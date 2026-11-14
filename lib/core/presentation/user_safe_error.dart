import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../localization/app_locale.dart';
import '../network/network_failure.dart';
import '../theme/app_design_system.dart';

String userSafeErrorMessage(BuildContext context, Object error) {
  if (kDebugMode) {
    debugPrint('Presentation error: $error');
  }
  final words = AppWords.of(context);
  return words.text(isNetworkFailure(error) ? 'error.network' : 'error.load');
}

class UserSafeErrorState extends StatelessWidget {
  const UserSafeErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final words = AppWords.of(context);
    return FpErrorState(
      title: words.text('error.load.title'),
      message: userSafeErrorMessage(context, error),
      action: onRetry == null
          ? null
          : FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(words.text('error.retry')),
            ),
    );
  }
}

class OfflineCachedDataBanner extends StatelessWidget {
  const OfflineCachedDataBanner({super.key, required this.capturedAt});

  final DateTime capturedAt;

  @override
  Widget build(BuildContext context) {
    final local = capturedAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final date =
        '${material.formatShortDate(local)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    final message = AppWords.of(
      context,
    ).format('offline.cached_at', {'date': date});
    return Semantics(
      liveRegion: true,
      child: Card(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}
