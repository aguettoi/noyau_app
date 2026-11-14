import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/noyau_app.dart';
import 'core/config/app_config.dart';
import 'core/data/supabase_bootstrap.dart';
import 'core/platform/native_notification_adapter.dart';
import 'core/platform/platform_link_adapter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  await initializeSupabase(const AppConfig.fromEnvironment());
  runApp(const ProviderScope(child: NoyauApp()));
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }
  unawaited(NativeNotificationAdapter.instance.initialize().catchError((_) {}));
  unawaited(PlatformLinkAdapter.instance.initialize().catchError((_) {}));
}
