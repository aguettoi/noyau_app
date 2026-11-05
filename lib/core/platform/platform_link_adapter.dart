import 'dart:async';

import 'package:app_links/app_links.dart';

import 'platform_link_contract.dart';

class PlatformLinkAdapter {
  PlatformLinkAdapter._();

  static final instance = PlatformLinkAdapter._();

  final _appLinks = AppLinks();
  final _intents = StreamController<PlatformLinkIntent>.broadcast();
  StreamSubscription<Uri>? _subscription;
  bool _initialized = false;

  Stream<PlatformLinkIntent> get intents => _intents.stream;

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
    if (intent != null) _intents.add(intent);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _intents.close();
  }
}
