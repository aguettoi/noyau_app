import 'dart:async';

import 'package:app_links/app_links.dart';

import 'platform_link_contract.dart';

class PlatformLinkAdapter {
  PlatformLinkAdapter._();

  static final instance = PlatformLinkAdapter._();

  final _appLinks = AppLinks();
  final _relay = PlatformLinkIntentRelay();
  StreamSubscription<Uri>? _subscription;
  bool _initialized = false;

  Stream<PlatformLinkIntent> get intents => _relay.intents;

  PlatformLinkIntent? takePendingIntent() => _relay.takePending();

  static PlatformLinkIntent? parseCommandLineArguments(
    Iterable<String> arguments,
  ) {
    for (final argument in arguments) {
      final uri = Uri.tryParse(argument);
      if (uri == null) continue;
      final intent = PlatformLinkContract.parse(uri);
      if (intent != null) return intent;
    }
    return null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final initial = await _appLinks.getInitialLink();
    _emit(initial);
    _subscription = _appLinks.uriLinkStream.listen(_emit);
  }

  void _emit(Uri? uri) {
    if (uri == null) return;
    final intent = PlatformLinkContract.parse(uri);
    if (intent != null) _relay.add(intent);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _relay.close();
  }
}

/// Keeps a cold-start link until the application router is ready to consume it.
///
/// Windows can deliver the initial protocol activation before Flutter has built
/// [NoyauApp]. A broadcast stream alone drops that event when it has no listener.
class PlatformLinkIntentRelay {
  final _controller = StreamController<PlatformLinkIntent>.broadcast();
  PlatformLinkIntent? _pending;

  Stream<PlatformLinkIntent> get intents => _controller.stream;

  void add(PlatformLinkIntent intent) {
    if (_controller.hasListener) {
      _controller.add(intent);
    } else {
      _pending = intent;
    }
  }

  PlatformLinkIntent? takePending() {
    final intent = _pending;
    _pending = null;
    return intent;
  }

  Future<void> close() => _controller.close();
}
