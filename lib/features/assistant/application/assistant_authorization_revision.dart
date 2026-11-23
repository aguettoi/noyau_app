import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Increased whenever Realtime announces a change that may reduce the data
/// visible to the current user. Conversation memory is then discarded.
final assistantAuthorizationRevisionProvider = StateProvider<int>((_) => 0);

void invalidateAssistantAuthorization(Ref ref) {
  final notifier = ref.read(assistantAuthorizationRevisionProvider.notifier);
  notifier.state = notifier.state + 1;
}
