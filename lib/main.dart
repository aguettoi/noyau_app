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
import 'core/platform/platform_link_contract.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) usePathUrlStrategy();
  await initializeSupabase(const AppConfig.fromEnvironment());
  PlatformLinkIntent? initialLink =
      PlatformLinkAdapter.parseCommandLineArguments(arguments);
  try {
    await PlatformLinkAdapter.instance.initialize();
    initialLink ??= PlatformLinkAdapter.instance.takePendingIntent();
  } catch (_) {
    // A platform-link failure must not prevent a normal application launch.
  }
  runApp(ProviderScope(child: NoyauApp(initialLink: initialLink)));
  if (kIsWeb) {
    SemanticsBinding.instance.ensureSemantics();
  }
  unawaited(NativeNotificationAdapter.instance.initialize().catchError((_) {}));
}
